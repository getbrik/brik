#!/usr/bin/env bash
# @module build.node
# @requires node
# @uses version
# @description Build Node.js projects (npm, yarn, pnpm).

# Guard against double-sourcing
[[ -n "${_BRIK_CORE_BUILD_NODE_LOADED:-}" ]] && return 0
_BRIK_CORE_BUILD_NODE_LOADED=1

# Detect the package manager from lock files.
# Prints npm, yarn, or pnpm on stdout.
_build.node._detect_pm() {
    local workspace="$1"

    if [[ -f "${workspace}/pnpm-lock.yaml" ]]; then
        printf 'pnpm'
    elif [[ -f "${workspace}/yarn.lock" ]]; then
        printf 'yarn'
    else
        printf 'npm'
    fi
}

# Install dependencies.
# Usage: build.node.install <workspace> [--package-manager <npm|yarn|pnpm>]
build.node.install() {
    local workspace="$1"
    shift
    local pm=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --package-manager) pm="$2"; shift 2 ;;
            *) log.error "unknown option: $1"; return 2 ;;
        esac
    done

    [[ -z "$pm" ]] && pm="$(_build.node._detect_pm "$workspace")"

    runtime.require_tool "$pm" || return 3
    runtime.require_file "${workspace}/package.json" || return 6

    log.info "installing dependencies with $pm"

    local install_cmd="install"
    # Use ci/frozen lockfile for reproducible installs when lock file exists
    case "$pm" in
        npm)
            [[ -f "${workspace}/package-lock.json" ]] && install_cmd="ci"
            ;;
        yarn)
            [[ -f "${workspace}/yarn.lock" ]] && install_cmd="install --frozen-lockfile"
            ;;
        pnpm)
            [[ -f "${workspace}/pnpm-lock.yaml" ]] && install_cmd="install --frozen-lockfile"
            ;;
    esac

    # $install_cmd intentionally word-splits (e.g. "install --frozen-lockfile")
    # shellcheck disable=SC2086
    (cd "$workspace" && $pm $install_cmd) || {
        log.error "dependency installation failed"
        return 5
    }

    return 0
}

# Run the build.
# Usage: build.node.run <workspace> [--package-manager <npm|yarn|pnpm>]
build.node.run() {
    local workspace="$1"
    shift
    local pm=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --package-manager) pm="$2"; shift 2 ;;
            *) log.error "unknown option: $1"; return 2 ;;
        esac
    done

    [[ -z "$pm" ]] && pm="$(_build.node._detect_pm "$workspace")"

    runtime.require_tool node || return 3
    runtime.require_tool "$pm" || return 3
    runtime.require_file "${workspace}/package.json" || return 6

    # Install if node_modules is missing
    if [[ ! -d "${workspace}/node_modules" ]]; then
        build.node.install "$workspace" --package-manager "$pm" || return $?
    fi

    log.info "running build with $pm"
    (cd "$workspace" && $pm run build) || {
        log.error "build failed"
        return 5
    }

    log.info "build completed successfully"
    return 0
}
