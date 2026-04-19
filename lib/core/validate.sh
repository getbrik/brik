#!/usr/bin/env bash
# @module validate
# @description Validate brik.yml against the JSON Schema.
#
# Extracted from bin/brik cmd_validate (Phase 4 - U8).
# Requires: logging, error, tools (runtime modules).

# Guard against double-sourcing
[[ -n "${_BRIK_CORE_VALIDATE_LOADED:-}" ]] && return 0
_BRIK_CORE_VALIDATE_LOADED=1

# Validate a brik.yml file against the JSON Schema.
# Usage: validate.run [--config <path>] [--schema <path>]
# Outputs result to stdout, errors to stderr.
validate.run() {
    local config_path="${1:-brik.yml}"
    local schema_path="${2:-${BRIK_HOME}/schemas/config/v1/brik.schema.json}"
    local json_output=""
    local validation_output=""

    runtime.require_file "$config_path" || return "$?"
    runtime.require_file "$schema_path" || return "$?"
    runtime.require_tool "yq" || return "$?"
    runtime.require_tool "check-jsonschema" || return "$?"

    if ! json_output="$(yq -o json "$config_path" 2>&1)"; then
        log.error "failed to parse $config_path as YAML"
        printf '%s\n' "$json_output" >&2
        return "$BRIK_EXIT_INVALID_INPUT"
    fi

    if ! validation_output="$(printf '%s\n' "$json_output" | check-jsonschema --schemafile "$schema_path" - 2>&1)"; then
        log.error "$config_path is invalid"
        printf '%s\n' "$validation_output" >&2
        return "$BRIK_EXIT_INVALID_INPUT"
    fi

    printf '%s\n' "$config_path is valid"
    return "$BRIK_EXIT_OK"
}
