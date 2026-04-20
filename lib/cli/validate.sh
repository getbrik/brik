#!/usr/bin/env bash
# @module cli.validate
# @description CLI entrypoint for "brik validate". Parses --config/--schema
#   and validates the brik.yml against the bundled JSON Schema.

# Guard against double-sourcing.
[[ -n "${_BRIK_MODULE_CLI_VALIDATE_LOADED:-}" ]] && return 0
_BRIK_MODULE_CLI_VALIDATE_LOADED=1

# validate.run - validate a brik.yml file against the JSON Schema.
# Usage: validate.run <config_path> <schema_path>
# Outputs result to stdout, errors to stderr.
validate.run() {
    local config_path="${1:-brik.yml}"
    local schema_path="${2:-${BRIK_HOME}/schemas/config/v1/brik.schema.json}"
    local json_output=""
    local validation_output=""

    pipeline.require_file "$config_path" || return "$?"
    pipeline.require_file "$schema_path" || return "$?"
    pipeline.require_tool "yq" || return "$?"
    pipeline.require_tool "check-jsonschema" || return "$?"

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

# cli.validate.run - parse CLI args and validate a brik.yml config file.
# Usage: cli.validate.run [--config <path>] [--schema <path>]
# Defaults: BRIK_DEFAULT_CONFIG (fallback "brik.yml") and BRIK_DEFAULT_SCHEMA
#   (fallback "$BRIK_HOME/schemas/config/v1/brik.schema.json").
cli.validate.run() {
    brik.use cli.helpers

    local config_path="${BRIK_DEFAULT_CONFIG:-brik.yml}"
    local schema_path="${BRIK_DEFAULT_SCHEMA:-${BRIK_HOME}/schemas/config/v1/brik.schema.json}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --config)
                brik_require_arg "--config" "${2-}" || return "$?"
                config_path="$2"
                shift 2
                ;;
            --schema)
                brik_require_arg "--schema" "${2-}" || return "$?"
                schema_path="$2"
                shift 2
                ;;
            *)
                brik_usage_error "unknown option: $1" || return "$?"
                ;;
        esac
    done

    validate.run "${config_path}" "${schema_path}"
}
