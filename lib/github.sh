#!/usr/bin/env bash

# GitHub readiness and connectivity tasks.

#
# Configuration
#

DEBIAN_BOOTSTRAP_REPO="${DEBIAN_BOOTSTRAP_REPO:-git@github.com:Friendly-Network-Forces/DebianBootstrap.git}"
DEBIAN_BOOTSTRAP_DIR="${DEBIAN_BOOTSTRAP_DIR:-}"

github_init_paths() {
    if [[ -z "${DEBIAN_BOOTSTRAP_DIR}" ]]; then
        DEBIAN_BOOTSTRAP_DIR="${TARGET_HOME}/Projects/DebianBootstrap"
    fi
}

#
# GitHub SSH Authentication Task
#

github_ssh_check() {
    local output

    if [[ "${SKIP_GITHUB}" -eq 1 ]]; then
        return 0
    fi

    output="$(
        sudo -u "${TARGET_USER}" \
            ssh \
            -o BatchMode=yes \
            -o ConnectTimeout=10 \
            -o StrictHostKeyChecking=accept-new \
            -T git@github.com 2>&1 || true
    )"

    grep -q "successfully authenticated" <<< "${output}"
}

github_ssh_plan() {
    log_info "Plan: verify GitHub SSH authentication for ${TARGET_USER}."
}

github_ssh_run() {
    log_info "Testing GitHub SSH authentication for ${TARGET_USER}."

    sudo -u "${TARGET_USER}" \
        ssh \
        -o BatchMode=yes \
        -o StrictHostKeyChecking=accept-new \
        -T git@github.com 2>&1 |
        tee /tmp/debian-bootstrap-github-test.log

    local ssh_status="${PIPESTATUS[0]}"

    # GitHub intentionally returns exit code 1 after successful authentication
    # because it does not provide interactive shell access.
    if grep -q "successfully authenticated" \
        /tmp/debian-bootstrap-github-test.log; then
        return 0
    fi

    return "${ssh_status}"
}

github_ssh_verify() {
    github_ssh_check
}

#
# DebianBootstrap Clone Task
#

debian_bootstrap_check() {
    [[ "${SKIP_GITHUB}" -eq 1 ]] && return 0

    [[ -d "${DEBIAN_BOOTSTRAP_DIR}/.git" ]]
}

debian_bootstrap_plan() {
    log_info "Plan: clone DebianBootstrap into ${DEBIAN_BOOTSTRAP_DIR}."
}

debian_bootstrap_run() {
    local parent_directory

    parent_directory="$(dirname "${DEBIAN_BOOTSTRAP_DIR}")"

    install -d \
        -m 0755 \
        -o "${TARGET_USER}" \
        -g "${TARGET_USER}" \
        "${parent_directory}"

    sudo -u "${TARGET_USER}" \
        git clone \
        "${DEBIAN_BOOTSTRAP_REPO}" \
        "${DEBIAN_BOOTSTRAP_DIR}"
}

debian_bootstrap_verify() {
    [[ -d "${DEBIAN_BOOTSTRAP_DIR}/.git" ]]
}

github_tasks_register() {
    github_init_paths

    register_task \
        "github_ssh_auth" \
        "GitHub SSH authentication" \
        "GitHub" \
        github_ssh_check \
        github_ssh_plan \
        github_ssh_run \
        github_ssh_verify

    register_task \
        "clone_debian_bootstrap" \
        "Clone DebianBootstrap repository" \
        "GitHub" \
        debian_bootstrap_check \
        debian_bootstrap_plan \
        debian_bootstrap_run \
        debian_bootstrap_verify
}
