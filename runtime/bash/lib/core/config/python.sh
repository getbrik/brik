#!/usr/bin/env bash
# @module config.python
# @description Python stack defaults and version export.
#
# Loaded via: brik.use config.python

# Guard against double-sourcing
[[ -n "${_BRIK_CORE_CONFIG_PYTHON_LOADED:-}" ]] && return 0
_BRIK_CORE_CONFIG_PYTHON_LOADED=1

# Return the default value for a Python setting.
# Usage: config.python.default <setting>
config.python.default() {
    local setting="$1"

    case "$setting" in
        build_command)  printf 'pip install .' ;;
        test_framework) printf 'pytest' ;;
        lint_tool)      printf 'ruff' ;;
        format_tool)    printf 'ruff format' ;;
        *) return 1 ;;
    esac
    return 0
}

# Export Python version pinning.
# Sets: BRIK_BUILD_PYTHON_VERSION (if configured)
config.python.export_build_vars() {
    local python_version
    python_version="$(config.get '.build.python_version' '')"
    [[ -n "$python_version" ]] && export BRIK_BUILD_PYTHON_VERSION="$python_version"
    return 0
}
