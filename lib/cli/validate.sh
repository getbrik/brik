#!/usr/bin/env bash
# @module cli.validate
# @description CLI entrypoint for "brik validate". Parses --config and
#   --schema, delegates the actual validation to validate.run.

# Guard against double-sourcing.
[[ -n "${_BRIK_MODULE_CLI_VALIDATE_LOADED:-}" ]] && return 0
_BRIK_MODULE_CLI_VALIDATE_LOADED=1

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

    brik.use validate
    validate.run "${config_path}" "${schema_path}"
}
