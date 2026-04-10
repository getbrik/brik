#!/usr/bin/env bash
# @module build.dotnet
# @requires dotnet
# @description Build .NET projects (dotnet build).

# Guard against double-sourcing
[[ -n "${_BRIK_CORE_BUILD_DOTNET_LOADED:-}" ]] && return 0
_BRIK_CORE_BUILD_DOTNET_LOADED=1

# Build a .NET project.
# Usage: build.dotnet.run <workspace> [--configuration <Debug|Release>]
build.dotnet.run() {
    local workspace="$1"
    shift
    local configuration=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --configuration) configuration="$2"; shift 2 ;;
            *) log.error "unknown option: $1"; return "$BRIK_EXIT_INVALID_INPUT" ;;
        esac
    done

    runtime.require_dir "$workspace" || return "$BRIK_EXIT_IO_FAILURE"

    # Need at least one .csproj or .sln file
    if ! compgen -G "${workspace}/*.csproj" >/dev/null 2>&1 && \
       ! compgen -G "${workspace}/*.sln" >/dev/null 2>&1; then
        log.error "no .csproj or .sln found in workspace: $workspace"
        return "$BRIK_EXIT_IO_FAILURE"
    fi

    runtime.require_tool dotnet || return "$BRIK_EXIT_MISSING_DEP"

    log.info "building with dotnet"

    local dotnet_args="build"
    if [[ -n "$configuration" ]]; then
        dotnet_args="build --configuration $configuration"
    fi

    # $dotnet_args intentionally word-splits
    # shellcheck disable=SC2086
    (cd "$workspace" && dotnet $dotnet_args) || {
        log.error "build failed"
        return "$BRIK_EXIT_EXTERNAL_FAIL"
    }

    log.info "build completed successfully"
    return 0
}
