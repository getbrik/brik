#!/usr/bin/env bash
# @module config.dotnet
# @description .NET stack defaults and version export.
#
# Loaded via: brik.use config.dotnet

# Guard against double-sourcing
[[ -n "${_BRIK_CORE_CONFIG_DOTNET_LOADED:-}" ]] && return 0
_BRIK_CORE_CONFIG_DOTNET_LOADED=1

# Return the default value for a .NET setting.
# Usage: config.dotnet.default <setting>
config.dotnet.default() {
    local setting="$1"

    case "$setting" in
        build_command)  printf '' ;;
        build_tool)     printf 'auto' ;;
        test_framework) printf 'xunit' ;;
        lint_tool)      printf 'dotnet-format' ;;
        format_tool)    printf 'dotnet-format' ;;
        *) return "$BRIK_EXIT_FAILURE" ;;
    esac
    return 0
}

# Export .NET version pinning.
# Sets: BRIK_BUILD_DOTNET_VERSION (if configured)
config.dotnet.export_build_vars() {
    local dotnet_version
    dotnet_version="$(config.get '.build.dotnet_version' '')"
    [[ -n "$dotnet_version" ]] && export BRIK_BUILD_DOTNET_VERSION="$dotnet_version"
    return 0
}

# Validate .NET project coherence.
# A .csproj or .sln file must exist for a .NET project.
# Usage: config.dotnet.validate_coherence <workspace>
config.dotnet.validate_coherence() {
    local workspace="$1"

    if ! compgen -G "${workspace}/*.csproj" >/dev/null 2>&1 \
        && ! compgen -G "${workspace}/*.sln" >/dev/null 2>&1; then
        log.error "config mismatch: stack is 'dotnet' but no .csproj or .sln file found"
        log.error "fix: create a .csproj or .sln file, or change project.stack in brik.yml"
        return "$BRIK_EXIT_CONFIG_ERROR"
    fi

    return 0
}
