#!/usr/bin/env bash

# Terminal UI helpers for debian-bootstrap-launcher.

print_rule() {
    local character="${1:--}"

    printf '%*s\n' 56 '' | tr ' ' "${character}"
}

print_header() {
    print_rule "="
    printf ' %s %s\n' "${PROGRAM_NAME}" "${PROGRAM_VERSION}"
    print_rule "="
    printf '\n'
}

print_section() {
    local title="$1"

    printf '\n%b%s%b\n' \
        "${COLOR_BOLD:-}" \
        "${title}" \
        "${COLOR_RESET:-}"

    printf '%*s\n' "${#title}" '' | tr ' ' '-'
}

print_key_value() {
    local key="$1"
    local value="$2"

    printf '%-16s %s\n' "${key}" "${value}"
}

prompt_yes_no() {
    local prompt="$1"
    local default_answer="${2:-no}"
    local reply

    while true; do
        if [[ "${default_answer}" == "yes" ]]; then
            read -r -p "${prompt} [Y/n] " reply
            reply="${reply:-y}"
        else
            read -r -p "${prompt} [y/N] " reply
            reply="${reply:-n}"
        fi

        case "${reply,,}" in
            y|yes)
                return 0
                ;;
            n|no)
                return 1
                ;;
            *)
                printf 'Please answer yes or no.\n'
                ;;
        esac
    done
}

print_readiness_summary() {
    print_section "System Summary"

    print_key_value "Target user" "${TARGET_USER}"
    print_key_value "Target home" "${TARGET_HOME}"
    print_key_value "Filesystem" "${TARGET_FSTYPE}"
    print_key_value "Device" "${TARGET_DEVICE}"
    print_key_value "Mountpoint" "${TARGET_MOUNTPOINT}"
    print_key_value "Home state" "${HOME_STATE}"
    print_key_value "ext4 encrypt" "${EXT4_ENCRYPT_FEATURE}"

    if [[ "${FSCRYPT_INSTALLED}" -eq 1 ]]; then
        print_key_value "fscrypt package" "Installed"
    else
        print_key_value "fscrypt package" "Missing"
    fi

    if [[ "${PAM_FSCRYPT_INSTALLED}" -eq 1 ]]; then
        print_key_value "PAM package" "Installed"
    else
        print_key_value "PAM package" "Missing"
    fi

    if [[ "${PAM_FSCRYPT_CONFIGURED}" -eq 1 ]]; then
        print_key_value "PAM integration" "Configured"
    else
        print_key_value "PAM integration" "Not configured"
    fi

    if [[ "${ENCRYPTION_ELIGIBLE}" -eq 1 ]]; then
        print_key_value "Encryption" "Eligible"
    else
        print_key_value "Encryption" "Not eligible"
    fi
}

handle_unavailable_encryption() {
    if [[ "${SKIP_ENCRYPTION}" -eq 1 ]]; then
        log_info "Encryption decision skipped by command-line option."
        return 0
    fi

    case "${HOME_STATE}" in
        POPULATED_UNENCRYPTED)
            printf '\n'
            log_warn "The target home cannot be encrypted safely by this launcher."

            if [[ "${DRY_RUN}" -eq 1 ]]; then
                log_info "Dry-run mode: would ask whether to continue without encryption."
                return 0
            fi

            if prompt_yes_no "Continue without home-directory encryption?" "no"; then
                SKIP_ENCRYPTION=1
                log_warn "Continuing without home-directory encryption."
            else
                log_info "Launcher stopped by user."
                exit 0
            fi
            ;;
    esac
}
