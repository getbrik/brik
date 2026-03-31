#!/usr/bin/env bash
# @module build
# @description Build dispatcher for brik-lib. Detects stack and delegates.

# Guard against double-sourcing
[[ -n "${_BRIK_CORE_BUILD_LOADED:-}" ]] && return 0
_BRIK_CORE_BUILD_LOADED=1

# Detect the project stack based on marker files.
# Prints the stack name on stdout. Returns 1 if not detected.
build.detect_stack() {
    local workspace="$1"

    if [[ -f "${workspace}/package.json" ]]; then
        printf 'node'
        return 0
    fi
    if [[ -f "${workspace}/pom.xml" || -f "${workspace}/build.gradle" || -f "${workspace}/build.gradle.kts" ]]; then
        printf 'java'
        return 0
    fi
    if [[ -f "${workspace}/setup.py" || -f "${workspace}/pyproject.toml" ]]; then
        printf 'python'
        return 0
    fi
    if [[ -f "${workspace}/Cargo.toml" ]]; then
        printf 'rust'
        return 0
    fi
    # Check for .csproj or .sln files
    if compgen -G "${workspace}/*.csproj" >/dev/null 2>&1 || compgen -G "${workspace}/*.sln" >/dev/null 2>&1; then
        printf 'dotnet'
        return 0
    fi

    log.error "cannot detect stack in workspace: $workspace"
    return 1
}

# Run a build for the detected or specified stack.
# Usage: build.run <workspace> [--stack <name>] [--config <path>]
build.run() {
    local workspace="$1"
    shift
    local stack=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --stack) stack="$2"; shift 2 ;;
            --config) shift 2 ;;  # accepted but not yet used
            *) log.error "unknown option: $1"; return 2 ;;
        esac
    done

    runtime.require_dir "$workspace" || return 6

    # Auto-detect stack if not specified
    if [[ -z "$stack" ]]; then
        stack="$(build.detect_stack "$workspace")" || return 7
    fi

    log.info "building with stack: $stack"

    # Load and delegate to the stack-specific module
    brik.use "build.${stack}" || {
        log.error "unsupported build stack: $stack"
        return 7
    }

    local build_fn="build.${stack}.run"
    if ! declare -f "$build_fn" >/dev/null 2>&1; then
        log.error "build function not found: $build_fn"
        return 7
    fi

    "$build_fn" "$workspace"
    return $?
}
