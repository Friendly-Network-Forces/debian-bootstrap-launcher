#!/usr/bin/env bash

# fscrypt and filesystem detection for debian-bootstrap-launcher.

detect_target_filesystem() {
    local probe_path="${TARGET_HOME}"

    if [[ ! -e "${probe_path}" ]]; then
        probe_path="$(dirname "${TARGET_HOME}")"
    fi

    TARGET_MOUNTPOINT="$(findmnt -no TARGET --target "${probe_path}")"
    TARGET_DEVICE="$(findmnt -no SOURCE --target "${probe_path}")"
    TARGET_FSTYPE="$(findmnt -no FSTYPE --target "${probe_path}")"

    if [[ -z "${TARGET_MOUNTPOINT}" ||
          -z "${TARGET_DEVICE}" ||
          -z "${TARGET_FSTYPE}" ]]; then
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
    local output

    command -v fscrypt >/dev/null 2>&1 || return 1

    output="$(fscrypt status "${TARGET_HOME}" 2>/dev/null || true)"

    grep -q 'is encrypted with fscrypt' <<< "${output}"
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

get_login_protector_id() {
    fscrypt status "${TARGET_MOUNTPOINT}" 2>/dev/null |
        awk -v user="${TARGET_USER}" '
            $0 ~ "login protector for " user {
                print $1
                exit
            }
        '
}

get_target_policy_id() {
    fscrypt status "${TARGET_HOME}" 2>/dev/null |
        awk '/^Policy:/ {print $2; exit}'
}

get_filesystem_policy_count() {
    fscrypt status "${TARGET_MOUNTPOINT}" 2>/dev/null |
        awk '
            /^POLICY[[:space:]]/ {
                in_policy_table=1
                next
            }

            in_policy_table && /^[0-9a-f]{32}[[:space:]]/ {
                count++
            }

            END {
                print count + 0
            }
        '
}

login_protector_exists() {
    [[ -n "$(get_login_protector_id)" ]]
}

detect_encryption_state() {
    HOME_EXISTS=0
    HOME_ENCRYPTED=0
    HOME_EMPTY=0
    LOGIN_PROTECTOR_EXISTS=0
    RECOVERY_PROTECTOR_EXISTS=0
    POLICY_EXISTS=0
    FILESYSTEM_POLICY_COUNT=0
    POLICY_ORPHANED=0

    if [[ -e "${TARGET_HOME}" ]]; then
        HOME_EXISTS=1
    fi

    if [[ -d "${TARGET_HOME}" ]]; then
        if home_is_encrypted; then
            HOME_ENCRYPTED=1
        elif home_is_empty; then
            HOME_EMPTY=1
        fi
    fi

    if login_protector_exists; then
        LOGIN_PROTECTOR_EXISTS=1
    fi

    if recovery_protector_check; then
        RECOVERY_PROTECTOR_EXISTS=1
    fi

    if [[ -n "$(get_target_policy_id)" ]]; then
        POLICY_EXISTS=1
    fi

    log_debug "Encryption state:"
    log_debug "  HOME_EXISTS=${HOME_EXISTS}"
    log_debug "  HOME_ENCRYPTED=${HOME_ENCRYPTED}"
    log_debug "  HOME_EMPTY=${HOME_EMPTY}"
    log_debug "  LOGIN_PROTECTOR_EXISTS=${LOGIN_PROTECTOR_EXISTS}"
    log_debug "  RECOVERY_PROTECTOR_EXISTS=${RECOVERY_PROTECTOR_EXISTS}"
    log_debug "  POLICY_EXISTS=${POLICY_EXISTS}"
    log_debug "  FILESYSTEM_POLICY_COUNT=${FILESYSTEM_POLICY_COUNT}"
    log_debug "  POLICY_ORPHANED=${POLICY_ORPHANED}"
}

enforce_consistent_encryption_state() {
    if [[ "${LOGIN_PROTECTOR_EXISTS}" -eq 1 &&
          "${HOME_ENCRYPTED}" -eq 0 ]]; then
        log_error "Inconsistent fscrypt state detected for ${TARGET_USER}."
        printf '\n'
        printf 'A login protector exists, but %s is not encrypted.\n' "${TARGET_HOME}"
        printf 'The launcher will not continue automatically.\n'
        printf '\n'
        printf 'Protector ID: %s\n' "$(get_login_protector_id)"
        printf '\n'
        printf 'This usually means a previous run created fscrypt metadata,\n'
        printf 'then the encrypted home directory was removed or replaced.\n'
        printf '\n'
        return 1
    fi
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

enforce_encryption_readiness() {
    if [[ "${SKIP_ENCRYPTION}" -eq 1 ]]; then
        return 0
    fi

    if [[ "${TARGET_FSTYPE}" != "ext4" ]]; then
        log_error "Unsupported filesystem: ${TARGET_FSTYPE}. RC1 supports ext4 only."
        return 1
    fi

    if [[ "${EXT4_ENCRYPT_FEATURE}" != "enabled" ]]; then
        printf '\n'
        log_error "The ext4 encrypt feature is not enabled on ${TARGET_DEVICE}."
        printf '\n'
        printf 'Encryption cannot continue safely.\n'
        printf '\n'
        printf 'Boot from Debian live media and run:\n'
        printf '\n'
        printf '  sudo e2fsck -f %s\n' "${TARGET_DEVICE}"
        printf '  sudo tune2fs -O encrypt %s\n' "${TARGET_DEVICE}"
        printf '  sudo e2fsck -f %s\n' "${TARGET_DEVICE}"
        printf '\n'
        printf 'Then reboot into the installed system and run the launcher again.\n'
        printf '\n'

        return 1
    fi
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

    [[ "${HOME_EXISTS}" -eq 1 ]] || return 1
    [[ "${HOME_ENCRYPTED}" -eq 0 ]] || return 1
    [[ "${HOME_EMPTY}" -eq 1 ]] || return 1
    [[ "${LOGIN_PROTECTOR_EXISTS}" -eq 0 ]] || return 1

    fscrypt_metadata_check
}

#
# Configure PAM fscrypt integration
#

pam_fscrypt_check() {
    local pam_file

    local pam_files=(
        /etc/pam.d/common-auth
        /etc/pam.d/common-session
        /etc/pam.d/common-password
    )

    for pam_file in "${pam_files[@]}"; do
        [[ -r "${pam_file}" ]] || return 1
        grep -q 'pam_fscrypt\.so' "${pam_file}" || return 1
    done

    return 0
}

pam_fscrypt_plan() {
    log_info "Plan: configure PAM integration for fscrypt."
}

pam_fscrypt_run() {
    if ! package_is_installed libpam-fscrypt; then
        log_error "Cannot configure PAM because libpam-fscrypt is not installed."
        return 1
    fi

    if command -v pam-auth-update >/dev/null 2>&1; then
        DEBIAN_FRONTEND=noninteractive pam-auth-update --package
    fi

    if pam_fscrypt_check; then
        return 0
    fi

    log_error "libpam-fscrypt was installed, but PAM integration was not configured."
    return 1
}

pam_fscrypt_verify() {
    pam_fscrypt_check
}

pam_fscrypt_task_enabled() {
    fscrypt_setup_task_enabled
}

#
# Create Recovery Protector
#

recovery_protector_check() {
    fscrypt status "${TARGET_HOME}" 2>/dev/null |
        grep -q 'custom protector "Recovery"'
}

recovery_protector_plan() {
    log_info "Plan: create and attach a custom recovery protector."
}

recovery_protector_run() {
    local protector_id
    local policy_id

    if ! home_is_encrypted; then
        log_error "Cannot create a recovery protector because ${TARGET_HOME} is not encrypted."
        return 1
    fi

    fscrypt metadata create protector \
        --source=custom_passphrase \
        "${TARGET_MOUNTPOINT}" \
        --name="Recovery"

    protector_id="$(
        fscrypt status "${TARGET_MOUNTPOINT}" |
            awk '
                /custom protector "Recovery"/ {
                    print $1
                    exit
                }
            '
    )"

    policy_id="$(
        fscrypt status "${TARGET_HOME}" |
            awk '/^Policy:/ {print $2; exit}'
    )"

    if [[ -z "${protector_id}" || -z "${policy_id}" ]]; then
        log_error "Unable to determine recovery protector or policy ID."
        return 1
    fi

    fscrypt metadata add-protector-to-policy \
        --protector="${TARGET_MOUNTPOINT}:${protector_id}" \
        --policy="${TARGET_MOUNTPOINT}:${policy_id}"
}

recovery_protector_verify() {
    recovery_protector_check
}

recovery_protector_task_enabled() {
    [[ "${SKIP_ENCRYPTION}" -eq 0 ]]
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
        "configure_pam_fscrypt" \
        "Configure PAM fscrypt integration" \
        "Encryption" \
        pam_fscrypt_check \
        pam_fscrypt_plan \
        pam_fscrypt_run \
        pam_fscrypt_verify \
        pam_fscrypt_task_enabled

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

    register_task \
        "create_recovery_protector" \
        "Create recovery protector" \
        "Encryption" \
        recovery_protector_check \
        recovery_protector_plan \
        recovery_protector_run \
        recovery_protector_verify \
        recovery_protector_task_enabled
}
