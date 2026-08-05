#!/usr/bin/env bash

# Logging helpers for debian-bootstrap-launcher.

LOG_FILE="${LOG_FILE:-/var/log/debian-bootstrap-launcher.log}"
VERBOSE="${VERBOSE:-0}"

timestamp() {
    date '+%Y-%m-%d %H:%M:%S'
}

write_log() {
    local level="$1"
    shift
    local message="$*"

    printf '%s [%s] %s\n' "$(timestamp)" "${level}" "${message}" >> "${LOG_FILE}"
}

log_info() {
    local message="$*"

    printf '%b[INFO]%b %s\n' \
        "${COLOR_BLUE:-}" \
        "${COLOR_RESET:-}" \
        "${message}"

    write_log "INFO" "${message}"
}

log_success() {
    local message="$*"

    printf '%b[OK]%b %s\n' \
        "${COLOR_GREEN:-}" \
        "${COLOR_RESET:-}" \
        "${message}"

    write_log "SUCCESS" "${message}"
}

log_warn() {
    local message="$*"

    printf '%b[WARN]%b %s\n' \
        "${COLOR_YELLOW:-}" \
        "${COLOR_RESET:-}" \
        "${message}" >&2

    write_log "WARNING" "${message}"
}

log_error() {
    local message="$*"

    printf '%b[ERROR]%b %s\n' \
        "${COLOR_RED:-}" \
        "${COLOR_RESET:-}" \
        "${message}" >&2

    write_log "ERROR" "${message}"
}

log_debug() {
    local message="$*"

    if [[ "${VERBOSE}" -eq 1 ]]; then
        printf '%b[DEBUG]%b %s\n' \
            "${COLOR_CYAN:-}" \
            "${COLOR_RESET:-}" \
            "${message}"
    fi

    write_log "DEBUG" "${message}"
}

init_logging() {
    local log_directory

    log_directory="$(dirname "${LOG_FILE}")"

    if [[ ! -d "${log_directory}" ]]; then
        mkdir -p "${log_directory}"
    fi

    touch "${LOG_FILE}"
    chmod 600 "${LOG_FILE}"

    write_log "INFO" "Logging initialized."
}
