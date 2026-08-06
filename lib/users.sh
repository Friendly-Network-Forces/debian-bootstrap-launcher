#!/usr/bin/env bash

# Permanent-user discovery, creation, and validation.

TARGET_USER="${TARGET_USER:-}"
TARGET_FULL_NAME="${TARGET_FULL_NAME:-}"
TARGET_HOME="${TARGET_HOME:-}"
TARGET_GROUPS="${TARGET_GROUPS:-}"

user_exists() {
    local username="$1"

    getent passwd "${username}" >/dev/null 2>&1
}

get_user_home() {
    local username="$1"

    getent passwd "${username}" | awk -F: '{print $6}'
}

get_user_full_name() {
    local username="$1"

    getent passwd "${username}" |
        awk -F: '{print $5}' |
        cut -d',' -f1
}

validate_username() {
    local username="$1"

    if [[ ! "${username}" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
        log_error "Invalid username: ${username}"
        return 1
    fi

    if [[ "${username}" == "root" ]]; then
        log_error "The permanent username cannot be root."
        return 1
    fi
}

prompt_for_target_user() {
    local username
    local full_name
    local groups

    print_section "Permanent User"

    while true; do
        read -r -p "Permanent username: " username

        if [[ -z "${username}" ]]; then
            printf 'A username is required.\n'
            continue
        fi

        if ! validate_username "${username}"; then
            continue
        fi

        if user_exists "${username}"; then
            if [[ "${ALLOW_EXISTING_USERS:-false}" != "true" ]]; then
                log_warn "Existing user detected: ${username}"
                log_info "The launcher will evaluate the user's home and fscrypt state before continuing."
            fi
        fi

        break
    done

    if user_exists "${username}"; then
        full_name="$(get_user_full_name "${username}")"

        if [[ -n "${full_name}" ]]; then
            log_info "Existing full name: ${full_name}"
        else
            log_info "Existing user has no full name configured."
        fi
    else
        read -r -p "Full name: " full_name
    fi

    TARGET_USER="${username}"
    TARGET_FULL_NAME="${full_name}"
    TARGET_HOME="/home/${TARGET_USER}"
    TARGET_GROUPS="${PERMANENT_USER_GROUPS:-sudo}"

    log_success "Permanent username: ${TARGET_USER}"
    log_success "Permanent home: ${TARGET_HOME}"

    if [[ -n "${TARGET_FULL_NAME}" ]]; then
        log_success "Full name: ${TARGET_FULL_NAME}"
    fi

    groups="${TARGET_GROUPS}"
    log_info "Requested groups: ${groups}"
}

resolve_target_user() {
    if [[ -n "${TARGET_USER}" ]]; then
        validate_username "${TARGET_USER}"

        if user_exists "${TARGET_USER}"; then
            TARGET_HOME="$(get_user_home "${TARGET_USER}")"
        else
            TARGET_HOME="/home/${TARGET_USER}"
        fi

        TARGET_GROUPS="${PERMANENT_USER_GROUPS:-sudo}"
        return 0
    fi

    prompt_for_target_user
}

build_existing_group_list() {
    local requested_groups="${TARGET_GROUPS}"
    local group_name
    local existing_groups=()

    IFS=',' read -r -a group_array <<< "${requested_groups}"

    for group_name in "${group_array[@]}"; do
        group_name="${group_name//[[:space:]]/}"

        [[ -n "${group_name}" ]] || continue

        if getent group "${group_name}" >/dev/null 2>&1; then
            existing_groups+=("${group_name}")
        else
            log_warn "Configured group does not exist and will be skipped: ${group_name}"
        fi
    done

    if [[ "${#existing_groups[@]}" -gt 0 ]]; then
        EXISTING_TARGET_GROUPS="$(
            IFS=,
            printf '%s' "${existing_groups[*]}"
        )"
    else
        EXISTING_TARGET_GROUPS=""
    fi
}

target_user_check() {
    user_exists "${TARGET_USER}"
}

target_user_plan() {
    log_info "Plan: create permanent user ${TARGET_USER}."
}

target_user_run() {
    local useradd_args=(
        --no-create-home
        --shell /bin/bash
    )

    build_existing_group_list

    if [[ -n "${TARGET_FULL_NAME}" ]]; then
        useradd_args+=(--comment "${TARGET_FULL_NAME}")
    fi

    if [[ -n "${EXISTING_TARGET_GROUPS}" ]]; then
        useradd_args+=(--groups "${EXISTING_TARGET_GROUPS}")
    fi

    useradd "${useradd_args[@]}" "${TARGET_USER}"

    printf '\nSet the login password for %s.\n' "${TARGET_USER}"
    passwd "${TARGET_USER}"
}

target_user_verify() {
    user_exists "${TARGET_USER}"
}

target_user_task_enabled() {
    ! user_exists "${TARGET_USER}"
}

users_tasks_register() {
    register_task \
        "create_permanent_user" \
        "Create permanent user" \
        "User Management" \
        target_user_check \
        target_user_plan \
        target_user_run \
        target_user_verify \
        target_user_task_enabled
}
