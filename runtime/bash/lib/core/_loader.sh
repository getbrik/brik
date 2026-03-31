#!/usr/bin/env bash
# @module _loader
# @description Module loader for brik-lib. Provides brik.use for lazy loading.
#
# Resolution order:
#   1. Project extensions: ${BRIK_PROJECT_DIR}/.brik/lib/core/
#   2. Organization extensions: BRIK_LIB_EXTENSIONS (colon-separated paths)
#   3. Standard library: ${BRIK_LIB}
#
# Double-load prevention via guard variables.

# Guard against double-sourcing of loader itself
[[ -n "${_BRIK_LOADER_LOADED:-}" ]] && return 0
_BRIK_LOADER_LOADED=1

# Ensure runtime logging is available
if [[ -z "${_BRIK_LOGGING_LOADED:-}" ]]; then
    local_runtime_dir="${BASH_SOURCE[0]%/*}/../runtime"
    if [[ -f "${local_runtime_dir}/logging.sh" ]]; then
        # shellcheck source=../runtime/logging.sh
        . "${local_runtime_dir}/logging.sh"
    fi
    unset local_runtime_dir
fi

# Load a brik-lib module by dot-notation name.
# Usage: brik.use <module>
# Example: brik.use build.node  ->  resolves to build/node.sh
brik.use() {
    local module_name="$1"

    # Build guard variable name: _BRIK_MODULE_<NAME>_LOADED
    local guard_name="_BRIK_MODULE_${module_name//./_}_LOADED"
    guard_name="${guard_name^^}"

    # Check double-load guard
    if [[ -n "${!guard_name:-}" ]]; then
        log.debug "module already loaded: $module_name"
        return 0
    fi

    # Convert dot notation to path: build.node -> build/node.sh
    local relative_path="${module_name//.//}.sh"

    local resolved=""

    # 1. Project extensions
    local project_dir="${BRIK_PROJECT_DIR:-$(pwd)}"
    local project_path="${project_dir}/.brik/lib/core/${relative_path}"
    if [[ -f "$project_path" ]]; then
        resolved="$project_path"
    fi

    # 2. Organization extensions (colon-separated)
    if [[ -z "$resolved" && -n "${BRIK_LIB_EXTENSIONS:-}" ]]; then
        local IFS=':'
        local ext_dir
        for ext_dir in $BRIK_LIB_EXTENSIONS; do
            if [[ -f "${ext_dir}/${relative_path}" ]]; then
                resolved="${ext_dir}/${relative_path}"
                break
            fi
        done
    fi

    # 3. Standard library
    if [[ -z "$resolved" ]]; then
        local std_lib="${BRIK_LIB:-${BRIK_HOME}/runtime/bash/lib/core}"
        local std_path="${std_lib}/${relative_path}"
        if [[ -f "$std_path" ]]; then
            resolved="$std_path"
        fi
    fi

    if [[ -z "$resolved" ]]; then
        log.error "module not found: $module_name (searched: $relative_path)"
        return 1
    fi

    log.debug "loading module: $module_name from $resolved"

    # shellcheck source=/dev/null
    . "$resolved" || {
        log.error "failed to source module: $resolved"
        return 1
    }

    # Set guard variable
    eval "$guard_name=1"
    export "${guard_name?}"

    return 0
}
