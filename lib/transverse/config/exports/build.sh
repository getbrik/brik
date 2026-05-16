#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# @module transverse.config.exports.build
# @description Exports BRIK_BUILD_* variables from brik.yml.
#
# Loaded by transverse.config (lib/transverse/config.sh). Relies on
# config.get / config.stack_default / _config._load_module from the
# parent module being already defined.

# Guard against double-sourcing
[[ -n "${_BRIK_CONFIG_EXPORTS_BUILD_LOADED:-}" ]] && return 0
_BRIK_CONFIG_EXPORTS_BUILD_LOADED=1

# Export build-related variables from brik.yml.
# Sets: BRIK_BUILD_STACK, BRIK_BUILD_COMMAND, BRIK_BUILD_NODE_VERSION, etc.
config.export_build_vars() {
    local stack
    stack="$(config.get '.project.stack' 'auto')"
    export BRIK_BUILD_STACK="$stack"

    local stack_version
    stack_version="$(config.get '.project.stack_version' '')"
    export BRIK_BUILD_STACK_VERSION="$stack_version"

    local default_cmd=""
    if [[ "$stack" != "auto" ]]; then
        # optional: stack may not define a default build command
        default_cmd="$(config.stack_default "$stack" "build_command" 2>/dev/null || true)"
    fi

    local build_cmd
    build_cmd="$(config.get '.build.command' "$default_cmd")"
    export BRIK_BUILD_COMMAND="$build_cmd"

    # Build tool (Tier 2 of 3-tier resolution: command > tool > auto)
    local build_tool
    build_tool="$(config.get '.build.tool' '')"
    if [[ -z "$build_tool" && "$stack" != "auto" ]]; then
        # optional: stack may not define a default build tool
        build_tool="$(config.stack_default "$stack" "build_tool" 2>/dev/null || true)"
    fi
    export BRIK_BUILD_TOOL="$build_tool"

    # Delegate version pinning to stack config module
    if [[ "$stack" != "auto" ]]; then
        if _config._load_module "$stack"; then
            local fn="config.${stack}.export_build_vars"
            declare -f "$fn" >/dev/null 2>&1 && "$fn"
        fi
    fi

    return 0
}
