#!/usr/bin/env bash
# @module cli.validate
# @description CLI entrypoint for "brik validate". Parses --config/--schema
#   and validates the brik.yml against the bundled JSON Schema.

# Guard against double-sourcing.
[[ -n "${_BRIK_MODULE_CLI_VALIDATE_LOADED:-}" ]] && return 0
_BRIK_MODULE_CLI_VALIDATE_LOADED=1

# validate.run - validate a brik.yml file against the JSON Schema and
# coherence rules. Thin wrapper that delegates to config.* primitives so
# the same checks run from `brik validate` (CLI) and `stages.init` (CI).
# Usage: validate.run <config_path> <schema_path>
# Outputs result to stdout, errors to stderr.
# Codes: 0 valid, 2 invalid input/schema, 3 missing tool, 6 missing file.
validate.run() {
    local config_path="${1:-brik.yml}"
    local schema_path="${2:-${BRIK_HOME}/schemas/config/v1/brik.schema.json}"

    pipeline.require_file "$config_path" || return "$?"
    pipeline.require_file "$schema_path" || return "$?"
    pipeline.require_tool "yq" || return "$?"

    brik.use transverse.config

    # Well-formed YAML. config.read returns 2 on parse failure.
    config.read "$config_path" || return "$?"

    # Schema validation. config.validate_schema returns 7 on violation;
    # remap to 2 (invalid input) for the CLI contract.
    if ! config.validate_schema "$config_path" "$schema_path"; then
        log.error "$config_path is invalid"
        return "$BRIK_EXIT_INVALID_INPUT"
    fi

    # Coherence (cross-block + stack rules). Default the workspace to
    # the directory of the config file so coherence rules that need a
    # workspace (e.g. stack-specific file checks) can run.
    : "${BRIK_WORKSPACE:=$(dirname "$config_path")}"
    export BRIK_WORKSPACE
    if ! config.validate_coherence; then
        log.error "$config_path is invalid"
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
            -h|--help)
                brik_print_verb_help validate
                return 0
                ;;
            *)
                brik_usage_error "unknown option: $1" || return "$?"
                ;;
        esac
    done

    validate.run "${config_path}" "${schema_path}"
}
