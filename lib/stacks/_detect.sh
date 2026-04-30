#!/usr/bin/env bash
# @module stacks._detect
# @description Stack detection from workspace marker files and test framework names.
#
# Provides the two detection primitives used across stages:
#   stacks.detect <workspace>           - from marker files (package.json, pom.xml, ...)
#   stacks.detect_from_framework <name> - from a framework name (jest, pytest, ...)

# Guard against double-sourcing.
[[ -n "${_BRIK_MODULE_STACKS_DETECT_LOADED:-}" ]] && return 0
_BRIK_MODULE_STACKS_DETECT_LOADED=1

# Detect the project stack based on marker files.
# Prints the stack name on stdout. Returns 1 if not detected.
stacks.detect() {
    local workspace="$1"

    if [[ -f "${workspace}/package.json" ]]; then
        printf 'node'
        return 0
    fi
    if [[ -f "${workspace}/pom.xml" || -f "${workspace}/build.gradle" || -f "${workspace}/build.gradle.kts" ]]; then
        printf 'java'
        return 0
    fi
    if [[ -f "${workspace}/requirements.txt" || -f "${workspace}/setup.py" || -f "${workspace}/pyproject.toml" ]]; then
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

# Map a framework name to its stack.
# Prints the stack name on stdout.
# Returns 1 for unknown frameworks.
stacks.detect_from_framework() {
    case "$1" in
        jest|npm|vitest)            printf 'node' ;;
        junit|maven|gradle)         printf 'java' ;;
        pytest|unittest|tox)        printf 'python' ;;
        cargo)                      printf 'rust' ;;
        dotnet|xunit|nunit)         printf 'dotnet' ;;
        *)                          return "$BRIK_EXIT_FAILURE" ;;
    esac
}
