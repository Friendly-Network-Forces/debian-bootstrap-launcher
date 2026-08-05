#!/usr/bin/env bash

# User discovery and validation for debian-bootstrap-launcher.

user_exists() {
    local username="$1"

    getent passwd "${username}" >/dev/null 2>&1
}

get_user_home() {
    local username="$1"

    getent passwd "${username}" | awk -F: '{print $6}'
}

validate_username() {
    local username="$1"

    if [[ ! "${username}" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
        log_error "Invalid username: ${username}"
        return 1
    fi
}

resolve_target_user() {
    if [[ -n "${TARGET_USER}" ]]; then
        validate_username "${TARGET_USER}"

        if ! user_exists "${TARGET_USER}"; then
            log_error "Target user does not exist: ${TARGET_USER}"
            return 1
        fi
    else
        if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
            TARGET_USER="${SUDO_USER}"
        else
            log_error "No target user was supplied and SUDO_USER is unavailable."
            return 1
        fi
    fi

    TARGET_HOME="$(get_user_home "${TARGET_USER}")"

    if [[ -z "${TARGET_HOME}" ]]; then
        log_error "Unable to determine home directory for ${TARGET_USER}."
        return 1
    fi

    log_success "Target user: ${TARGET_USER}"
    log_success "Target home: ${TARGET_HOME}"
}
