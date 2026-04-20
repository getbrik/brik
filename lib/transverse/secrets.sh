#!/usr/bin/env bash
# @module transverse.secrets
# @description Guards for secret environment variables referenced by name.

# Guard against double-sourcing.
[[ -n "${_BRIK_MODULE_SECRETS_LOADED:-}" ]] && return 0
_BRIK_MODULE_SECRETS_LOADED=1

# transverse.secrets.require_var - validate that a secret env var is defined.
# Given a variable name (e.g. "BRIK_PUBLISH_NPM_TOKEN_VAR"), check:
#   1. the name itself is non-empty
#   2. the name is a valid bash identifier
#   3. the variable referenced by that name is set and non-empty
# The <label> argument is woven into error messages for operator context
# (e.g. "npm token", "docker password"). Returns BRIK_EXIT_CONFIG_ERROR on
# any guard violation, 0 on success.
# Usage: transverse.secrets.require_var <var_name> <label>
transverse.secrets.require_var() {
    local var_name="$1"
    local label="$2"

    if [[ -z "$var_name" ]]; then
        log.error "$label variable name is not configured"
        return "$BRIK_EXIT_CONFIG_ERROR"
    fi

    if [[ ! "$var_name" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
        log.error "$label variable name '$var_name' is not a valid identifier"
        return "$BRIK_EXIT_CONFIG_ERROR"
    fi

    if [[ -z "${!var_name:-}" ]]; then
        log.error "$label variable '$var_name' is not set or empty"
        return "$BRIK_EXIT_CONFIG_ERROR"
    fi

    return 0
}
