#!/usr/bin/env bash

# Terminal color support for debian-bootstrap-launcher.

init_colors() {
    if [[ -n "${NO_COLOR:-}" ]] || [[ ! -t 1 ]] || [[ "${USE_COLOR:-1}" -eq 0 ]]; then
        readonly COLOR_RESET=""
        readonly COLOR_BOLD=""
        readonly COLOR_RED=""
        readonly COLOR_GREEN=""
        readonly COLOR_YELLOW=""
        readonly COLOR_BLUE=""
        readonly COLOR_CYAN=""
        return
    fi

    readonly COLOR_RESET=$'\033[0m'
    readonly COLOR_BOLD=$'\033[1m'
    readonly COLOR_RED=$'\033[31m'
    readonly COLOR_GREEN=$'\033[32m'
    readonly COLOR_YELLOW=$'\033[33m'
    readonly COLOR_BLUE=$'\033[34m'
    readonly COLOR_CYAN=$'\033[36m'
}
