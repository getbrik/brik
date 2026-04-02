#!/usr/bin/env bash
# @module test.dotnet
# @requires dotnet
# @description Test commands for .NET projects.

# Guard against double-sourcing
[[ -n "${_BRIK_CORE_TEST_DOTNET_LOADED:-}" ]] && return 0
_BRIK_CORE_TEST_DOTNET_LOADED=1

# Build the test command for a given .NET framework.
# Usage: test.dotnet.cmd <framework> <workspace> <report_dir>
# Frameworks: dotnet
test.dotnet.cmd() {
    local framework="$1"
    local cmd=""

    case "$framework" in
        dotnet)
            cmd="dotnet test"
            ;;
        *)
            log.error "unsupported .NET test framework: $framework"
            return 7
            ;;
    esac

    printf '%s' "$cmd"
    return 0
}

# Auto-detect and return the test command for a .NET workspace.
# Usage: test.dotnet.run_cmd <workspace> <report_dir>
test.dotnet.run_cmd() {
    local workspace="$1" report_dir="$2"

    test.dotnet.cmd "dotnet" "$workspace" "$report_dir"
}
