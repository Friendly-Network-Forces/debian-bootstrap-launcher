#!/usr/bin/env bash

# System preflight checks for debian-bootstrap-launcher.

require_root() {
    if [[ "${EUID}" -ne 0 ]]; then
        log_error "This launcher must be run with sudo or as root."
        return 1
    fi

    log_success "Root privileges confirmed."
}

check_debian() {
    if [[ ! -r /etc/os-release ]]; then
        log_error "Cannot read /etc/os-release."
        return 1
    fi

    # shellcheck disable=SC1091
    source /etc/os-release

    if [[ "${ID:-}" != "debian" ]]; then
        log_error "Unsupported operating system: ${PRETTY_NAME:-unknown}."
        return 1
    fi

    log_success "Detected ${PRETTY_NAME:-Debian}."
}

check_debian_version() {
    # VERSION_ID may contain a quoted string after sourcing os-release.
    local major_version="${VERSION_ID%%.*}"

    if [[ "${major_version}" != "13" ]]; then
        log_error "Debian 13 is required. Detected version: ${VERSION_ID:-unknown}."
        return 1
    fi

    log_success "Debian 13 requirement satisfied."
}

detect_execution_context() {
    if [[ -n "${SSH_CONNECTION:-}" || -n "${SSH_TTY:-}" ]]; then
        EXECUTION_CONTEXT="ssh"
        log_warn "Launcher is running through SSH."
    else
        EXECUTION_CONTEXT="local"
        log_success "Launcher is running from a local session."
    fi
}

check_required_commands() {
    local missing=0
    local command_name

    local required_commands=(
        awk
        findmnt
        getent
        grep
        id
        sed
    )

    for command_name in "${required_commands[@]}"; do
        if ! command -v "${command_name}" >/dev/null 2>&1; then
            log_error "Required command not found: ${command_name}"
            missing=1
        else
            log_debug "Required command found: ${command_name}"
        fi
    done

    if [[ "${missing}" -ne 0 ]]; then
        return 1
    fi

    log_success "Required preflight commands are available."
}
