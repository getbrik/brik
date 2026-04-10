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
    return "$BRIK_EXIT_FAILURE"
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
            *) log.error "unknown option: $1"; return "$BRIK_EXIT_INVALID_INPUT" ;;
        esac
    done

    runtime.require_dir "$workspace" || return "$BRIK_EXIT_IO_FAILURE"

    # Auto-detect stack if not specified
    if [[ -z "$stack" ]]; then
        stack="$(build.detect_stack "$workspace")" || return "$BRIK_EXIT_CONFIG_ERROR"
    fi

    log.info "building with stack: $stack"

    # If BRIK_BUILD_COMMAND is set, use it as custom command override
    if [[ -n "${BRIK_BUILD_COMMAND:-}" ]]; then
        log.info "using custom build command: $BRIK_BUILD_COMMAND"
        (cd "$workspace" && eval "$BRIK_BUILD_COMMAND")
        return $?
    fi

    # Load and delegate to the stack-specific module
    brik.use "build.${stack}" || {
        log.error "unsupported build stack: $stack"
        return "$BRIK_EXIT_CONFIG_ERROR"
    }

    local build_fn="build.${stack}.run"
    if ! declare -f "$build_fn" >/dev/null 2>&1; then
        log.error "build function not found: $build_fn"
        return "$BRIK_EXIT_CONFIG_ERROR"
    fi

    # Pass BRIK_BUILD_TOOL to stack module if set and not 'auto'
    local tool_args=()
    if [[ -n "${BRIK_BUILD_TOOL:-}" && "${BRIK_BUILD_TOOL}" != "auto" ]]; then
        tool_args=(--tool "$BRIK_BUILD_TOOL")
    fi

    "$build_fn" "$workspace" "${tool_args[@]}"
    return $?
}
