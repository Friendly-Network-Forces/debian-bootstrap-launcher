#!/usr/bin/env bash

# fscrypt and filesystem detection for debian-bootstrap-launcher.

detect_target_filesystem() {
    TARGET_MOUNTPOINT="$(findmnt -no TARGET --target "${TARGET_HOME}")"
    TARGET_DEVICE="$(findmnt -no SOURCE --target "${TARGET_HOME}")"
    TARGET_FSTYPE="$(findmnt -no FSTYPE --target "${TARGET_HOME}")"

    if [[ -z "${TARGET_MOUNTPOINT}" || -z "${TARGET_DEVICE}" || -z "${TARGET_FSTYPE}" ]]; then
        log_error "Unable to determine filesystem details for ${TARGET_HOME}."
        return 1
    fi

    log_success "Filesystem type: ${TARGET_FSTYPE}"
    log_success "Filesystem device: ${TARGET_DEVICE}"
    log_debug "Filesystem mountpoint: ${TARGET_MOUNTPOINT}"
}

detect_ext4_encrypt_feature() {
    EXT4_ENCRYPT_FEATURE="unknown"

    if [[ "${TARGET_FSTYPE}" != "ext4" ]]; then
        log_warn "Filesystem is not ext4; fscrypt support is outside the v0.1 scope."
        return 0
    fi

    if ! command -v tune2fs >/dev/null 2>&1; then
        log_error "tune2fs is required to inspect ext4 filesystem features."
        return 1
    fi

    if tune2fs -l "${TARGET_DEVICE}" 2>/dev/null |
        awk -F: '/Filesystem features/ {print $2}' |
        grep -qw encrypt; then
        EXT4_ENCRYPT_FEATURE="enabled"
        log_success "The ext4 encrypt feature is enabled."
    else
        EXT4_ENCRYPT_FEATURE="missing"
        log_warn "The ext4 encrypt feature is not enabled."
    fi
}

package_is_installed() {
    local package_name="$1"

    dpkg-query -W \
        -f='${db:Status-Status}' \
        "${package_name}" 2>/dev/null |
        grep -qx 'installed'
}

detect_fscrypt_packages() {
    if package_is_installed fscrypt; then
        FSCRYPT_INSTALLED=1
        log_success "Package installed: fscrypt"
    else
        FSCRYPT_INSTALLED=0
        log_warn "Package missing: fscrypt"
    fi

    if package_is_installed libpam-fscrypt; then
        PAM_FSCRYPT_INSTALLED=1
        log_success "Package installed: libpam-fscrypt"
    else
        PAM_FSCRYPT_INSTALLED=0
        log_warn "Package missing: libpam-fscrypt"
    fi
}

detect_pam_fscrypt() {
    local missing=0
    local pam_file

    local pam_files=(
        /etc/pam.d/common-auth
        /etc/pam.d/common-session
        /etc/pam.d/common-password
    )

    for pam_file in "${pam_files[@]}"; do
        if [[ ! -r "${pam_file}" ]] ||
            ! grep -q 'pam_fscrypt\.so' "${pam_file}"; then
            log_warn "pam_fscrypt is not configured in ${pam_file}."
            missing=1
        else
            log_debug "pam_fscrypt found in ${pam_file}."
        fi
    done

    if [[ "${missing}" -eq 0 ]]; then
        PAM_FSCRYPT_CONFIGURED=1
        log_success "PAM fscrypt integration is configured."
    else
        PAM_FSCRYPT_CONFIGURED=0
    fi
}

home_is_encrypted() {
    command -v fscrypt >/dev/null 2>&1 || return 1

    fscrypt status "${TARGET_HOME}" 2>/dev/null |
        grep -q 'is encrypted with fscrypt'
}

home_is_empty() {
    [[ -d "${TARGET_HOME}" ]] || return 1

    ! find "${TARGET_HOME}" \
        -mindepth 1 \
        -maxdepth 1 \
        -print -quit |
        grep -q .
}

detect_home_state() {
    if [[ ! -e "${TARGET_HOME}" ]]; then
        HOME_STATE="MISSING"
        log_warn "Target home directory does not exist."
        return 0
    fi

    if [[ ! -d "${TARGET_HOME}" ]]; then
        log_error "Target home path exists but is not a directory: ${TARGET_HOME}"
        return 1
    fi

    if home_is_encrypted; then
        HOME_STATE="ENCRYPTED"
        log_success "Target home is encrypted with fscrypt."
        return 0
    fi

    if home_is_empty; then
        HOME_STATE="EMPTY_UNENCRYPTED"
        log_warn "Target home is empty and not encrypted."
    else
        HOME_STATE="POPULATED_UNENCRYPTED"
        log_warn "Target home contains data and is not encrypted."
    fi
}

report_home_state() {
    log_info "Home state: ${HOME_STATE}"

    case "${HOME_STATE}" in
        ENCRYPTED)
            log_success "No home-directory migration is required."
            ;;
        EMPTY_UNENCRYPTED)
            log_info "The home directory is eligible for the empty-home encryption workflow."
            ;;
        POPULATED_UNENCRYPTED)
            log_warn "The launcher will not delete or migrate a populated home directory."
            ;;
        MISSING)
            log_info "The launcher can create the target home directory later."
            ;;
        *)
            log_error "Unknown home state: ${HOME_STATE}"
            return 1
            ;;
    esac
}

determine_encryption_eligibility() {
    ENCRYPTION_ELIGIBLE=0

    if [[ "${SKIP_ENCRYPTION}" -eq 1 ]]; then
        log_info "Home-directory encryption was skipped by command-line option."
        return 0
    fi

    if [[ "${TARGET_FSTYPE}" != "ext4" ]]; then
        log_warn "Encryption is unavailable: v0.1 supports ext4 only."
        return 0
    fi

    if [[ "${EXT4_ENCRYPT_FEATURE}" != "enabled" ]]; then
        log_warn "Encryption is unavailable until the ext4 encrypt feature is enabled offline."
        return 0
    fi

    case "${HOME_STATE}" in
        ENCRYPTED)
            log_success "Home-directory encryption is already configured."
            ;;
        EMPTY_UNENCRYPTED|MISSING)
            ENCRYPTION_ELIGIBLE=1
            log_success "The target home is eligible for fscrypt setup."
            ;;
        POPULATED_UNENCRYPTED)
            log_warn "Encryption is unavailable because the target home contains data."
            ;;
        *)
            log_error "Cannot determine encryption eligibility from home state: ${HOME_STATE}"
            return 1
            ;;
    esac
}

#
# Shared task enablement
#

fscrypt_task_enabled() {
    [[ "${SKIP_ENCRYPTION}" -eq 0 ]] || return 1

    case "${HOME_STATE}" in
        ENCRYPTED|EMPTY_UNENCRYPTED|MISSING)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

fscrypt_setup_task_enabled() {
    fscrypt_task_enabled || return 1
    [[ "${TARGET_FSTYPE}" == "ext4" ]] || return 1
    [[ "${EXT4_ENCRYPT_FEATURE}" == "enabled" ]] || return 1

    case "${HOME_STATE}" in
        EMPTY_UNENCRYPTED|MISSING)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

#
# Install fscrypt packages
#

fscrypt_packages_check() {
    package_is_installed fscrypt &&
        package_is_installed libpam-fscrypt
}

fscrypt_packages_plan() {
    log_info "Plan: install fscrypt and libpam-fscrypt."
}

fscrypt_packages_run() {
    export DEBIAN_FRONTEND=noninteractive

    apt-get update &&
        apt-get install -y fscrypt libpam-fscrypt
}

fscrypt_packages_verify() {
    fscrypt_packages_check
}

#
# Initialize fscrypt metadata
#

fscrypt_metadata_check() {
    [[ -d "${TARGET_MOUNTPOINT}/.fscrypt" ]] &&
        [[ -r /etc/fscrypt.conf ]]
}

fscrypt_metadata_plan() {
    log_info "Plan: initialize fscrypt metadata on ${TARGET_MOUNTPOINT}."
}

fscrypt_metadata_run() {
    fscrypt setup \
        --quiet \
        --all-users \
        "${TARGET_MOUNTPOINT}"
}

fscrypt_metadata_verify() {
    fscrypt_metadata_check
}

#
# Create target home
#

target_home_check() {
    [[ -d "${TARGET_HOME}" ]]
}

target_home_plan() {
    log_info "Plan: create ${TARGET_HOME} for ${TARGET_USER}."
}

target_home_run() {
    install -d \
        -m 0700 \
        -o "${TARGET_USER}" \
        -g "${TARGET_USER}" \
        "${TARGET_HOME}"

    HOME_STATE="EMPTY_UNENCRYPTED"
}

target_home_verify() {
    [[ -d "${TARGET_HOME}" ]] &&
        [[ "$(stat -c '%U' "${TARGET_HOME}")" == "${TARGET_USER}" ]] &&
        [[ "$(stat -c '%G' "${TARGET_HOME}")" == "${TARGET_USER}" ]] &&
        [[ "$(stat -c '%a' "${TARGET_HOME}")" == "700" ]]
}

target_home_task_enabled() {
    [[ "${SKIP_ENCRYPTION}" -eq 0 ]] || return 1
    [[ "${ENCRYPTION_ELIGIBLE}" -eq 1 ]] || return 1
    [[ "${HOME_STATE}" == "MISSING" ]]
}

#
# Encrypt target home
#

target_home_encrypt_check() {
    home_is_encrypted
}

target_home_encrypt_plan() {
    log_info "Plan: encrypt ${TARGET_HOME} using ${TARGET_USER}'s login passphrase."
}

target_home_encrypt_run() {
    if [[ "${EXECUTION_CONTEXT:-unknown}" == "ssh" ]]; then
        log_error "Refusing to encrypt the target home over SSH. Run locally from a TTY."
        return 1
    fi

    if [[ ! -d "${TARGET_HOME}" ]]; then
        log_error "Target home does not exist: ${TARGET_HOME}"
        return 1
    fi

    if ! home_is_empty; then
        log_error "Target home is not empty: ${TARGET_HOME}"
        return 1
    fi

    fscrypt encrypt \
        --user="${TARGET_USER}" \
        "${TARGET_HOME}"
}

target_home_encrypt_verify() {
    home_is_encrypted
}

target_home_encrypt_task_enabled() {
    [[ "${SKIP_ENCRYPTION}" -eq 0 ]] || return 1
    [[ "${ENCRYPTION_ELIGIBLE}" -eq 1 ]] || return 1
    [[ "${TARGET_FSTYPE}" == "ext4" ]] || return 1
    [[ "${EXT4_ENCRYPT_FEATURE}" == "enabled" ]] || return 1
    [[ -d "${TARGET_HOME}" ]] || return 1
    home_is_empty || return 1
    fscrypt_metadata_check
}

#
# Task registration
#

fscrypt_tasks_register() {
    register_task \
        "install_fscrypt_packages" \
        "Install fscrypt packages" \
        "Encryption" \
        fscrypt_packages_check \
        fscrypt_packages_plan \
        fscrypt_packages_run \
        fscrypt_packages_verify \
        fscrypt_task_enabled

    register_task \
        "initialize_fscrypt_metadata" \
        "Initialize fscrypt metadata" \
        "Encryption" \
        fscrypt_metadata_check \
        fscrypt_metadata_plan \
        fscrypt_metadata_run \
        fscrypt_metadata_verify \
        fscrypt_setup_task_enabled

    register_task \
        "create_target_home" \
        "Create target home directory" \
        "Encryption" \
        target_home_check \
        target_home_plan \
        target_home_run \
        target_home_verify \
        target_home_task_enabled

    register_task \
        "encrypt_target_home" \
        "Encrypt target home directory" \
        "Encryption" \
        target_home_encrypt_check \
        target_home_encrypt_plan \
        target_home_encrypt_run \
        target_home_encrypt_verify \
        target_home_encrypt_task_enabled
}
