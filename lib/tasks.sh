#!/usr/bin/env bash

# Task registry and execution engine for debian-bootstrap-launcher.

declare -a TASK_IDS=()

declare -A TASK_NAMES=()
declare -A TASK_CHECK_FUNCTIONS=()
declare -A TASK_PLAN_FUNCTIONS=()
declare -A TASK_RUN_FUNCTIONS=()
declare -A TASK_VERIFY_FUNCTIONS=()
declare -A TASK_ENABLED_FUNCTIONS=()
declare -A TASK_RESULTS=()
declare -A TASK_CATEGORIES=()

register_task() {
    local task_id="$1"
    local task_name="$2"
    local task_category="$3"
    local check_function="$4"
    local plan_function="$5"
    local run_function="$6"
    local verify_function="$7"
    local enabled_function="${8:-task_always_enabled}"

    if [[ ! "${task_id}" =~ ^[a-z0-9_]+$ ]]; then
        log_error "Invalid task ID: ${task_id}"
        return 1
    fi

    if [[ -n "${TASK_NAMES[${task_id}]:-}" ]]; then
        log_error "Task already registered: ${task_id}"
        return 1
    fi

    TASK_IDS+=("${task_id}")
    TASK_NAMES["${task_id}"]="${task_name}"
    TASK_CATEGORIES["${task_id}"]="${task_category}"
    TASK_CHECK_FUNCTIONS["${task_id}"]="${check_function}"
    TASK_PLAN_FUNCTIONS["${task_id}"]="${plan_function}"
    TASK_RUN_FUNCTIONS["${task_id}"]="${run_function}"
    TASK_VERIFY_FUNCTIONS["${task_id}"]="${verify_function}"
    TASK_ENABLED_FUNCTIONS["${task_id}"]="${enabled_function}"
    TASK_RESULTS["${task_id}"]="PENDING"

    log_debug "Registered task: ${task_id}"
}

task_always_enabled() {
    return 0
}

validate_task_function() {
    local task_id="$1"
    local function_role="$2"
    local function_name="$3"

    if ! declare -F "${function_name}" >/dev/null 2>&1; then
        log_error \
            "Task ${task_id} references missing ${function_role} function: ${function_name}"
        return 1
    fi
}

validate_task() {
    local task_id="$1"

    validate_task_function \
        "${task_id}" \
        "check" \
        "${TASK_CHECK_FUNCTIONS[${task_id}]}"

    validate_task_function \
        "${task_id}" \
        "plan" \
        "${TASK_PLAN_FUNCTIONS[${task_id}]}"

    validate_task_function \
        "${task_id}" \
        "run" \
        "${TASK_RUN_FUNCTIONS[${task_id}]}"

    validate_task_function \
        "${task_id}" \
        "verify" \
        "${TASK_VERIFY_FUNCTIONS[${task_id}]}"

    validate_task_function \
        "${task_id}" \
        "enabled" \
        "${TASK_ENABLED_FUNCTIONS[${task_id}]}"
}

run_registered_task() {
    local task_id="$1"
    local task_name="${TASK_NAMES[${task_id}]}"
    local check_function="${TASK_CHECK_FUNCTIONS[${task_id}]}"
    local plan_function="${TASK_PLAN_FUNCTIONS[${task_id}]}"
    local run_function="${TASK_RUN_FUNCTIONS[${task_id}]}"
    local verify_function="${TASK_VERIFY_FUNCTIONS[${task_id}]}"
    local enabled_function="${TASK_ENABLED_FUNCTIONS[${task_id}]}"
    local task_category="${TASK_CATEGORIES[${task_id}]}"

    print_section "${task_category}: ${task_name}"

    validate_task "${task_id}"

    if ! "${enabled_function}"; then
        TASK_RESULTS["${task_id}"]="SKIPPED"
        log_info "Task skipped: ${task_name}. Reason: disabled"
        return 0
    fi

    if "${check_function}"; then
        TASK_RESULTS["${task_id}"]="SATISFIED"
        log_info "Task skipped: ${task_name}. Reason: already satisfied"
        return 0
    fi

    "${plan_function}"

    if [[ "${DRY_RUN}" -eq 1 ]]; then
        TASK_RESULTS["${task_id}"]="PLANNED"
        log_info "Task skipped: ${task_name}. Reason: dry-run mode"
        return 0
    fi

    if ! "${run_function}"; then
        TASK_RESULTS["${task_id}"]="FAILED"
        log_error "Task failed: ${task_name}. Reason: execution failed"
        return 1
    fi

    if ! "${verify_function}"; then
        TASK_RESULTS["${task_id}"]="FAILED"
        log_error "Task failed: ${task_name}. Reason: verification failed"
        return 1
    fi

    TASK_RESULTS["${task_id}"]="SUCCESS"
    log_success "Task completed: ${task_name}"
}

run_registered_tasks() {
    local task_id

    for task_id in "${TASK_IDS[@]}"; do
        run_registered_task "${task_id}"
    done
}

print_task_summary() {
    local task_id
    local task_name
    local task_category
    local task_result

    print_section "Execution Summary"

    for task_id in "${TASK_IDS[@]}"; do
        task_name="${TASK_NAMES[${task_id}]}"
        task_category="${TASK_CATEGORIES[${task_id}]}"
        task_result="${TASK_RESULTS[${task_id}]}"

        printf '%-12s %-38s %s\n' \
            "${task_category}" \
            "${task_name}" \
            "${task_result}"
    done
}
