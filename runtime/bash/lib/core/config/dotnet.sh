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
        build_command)  printf 'dotnet build' ;;
        test_framework) printf 'xunit' ;;
        lint_tool)      printf 'dotnet-format' ;;
        format_tool)    printf 'dotnet-format' ;;
        *) return 1 ;;
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
