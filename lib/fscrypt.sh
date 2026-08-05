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
