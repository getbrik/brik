#!/usr/bin/env bash
# @module transverse.env
# @description Single point for variable indirection and user env-file sourcing.
#
# Public surface:
#   transverse.env.resolve_indirect <var_name>
#       Return the value of the variable whose name is $1. Empty when unset.
#       This is the replacement for the ${!var:-} pattern scattered across lib/.
#
#   transverse.env.load_project
#       Source the project-level env file. Resolution order:
#           1. .project.env declared in brik.yml (if BRIK_CONFIG_FILE is set).
#           2. brik.env at the current working directory (auto-detection).
#           3. No-op (returns 0).
#       Policy: variables already exported take precedence over file entries.
#
#   transverse.env.load_deploy_env <env_name>
#       Source the file declared at .deploy.environments.<env>.env_file in
#       brik.yml. Returns 0 on success or no-op (env not declared). Returns 1
#       when env_file is declared but the file is missing on disk.
#
# Scope boundary with pipeline.env.*:
#   pipeline.env.* handles cross-stage KEY=VALUE persistence written under
#   $BRIK_LOG_DIR/pipeline.env. transverse.env.* handles user-authored
#   KEY=VALUE files declared in brik.yml. The two modules do not share state.

# Guard against double-sourcing.
[[ -n "${_BRIK_MODULE_TRANSVERSE_ENV_LOADED:-}" ]] && return 0
_BRIK_MODULE_TRANSVERSE_ENV_LOADED=1

# -----------------------------------------------------------------------------
# transverse.env.resolve_indirect <var_name>
# -----------------------------------------------------------------------------
transverse.env.resolve_indirect() {
    local var_name="$1"
    [[ -z "$var_name" ]] && return 0
    printf '%s' "${!var_name:-}"
}

# -----------------------------------------------------------------------------
# transverse.env.load_project
# -----------------------------------------------------------------------------
transverse.env.load_project() {
    local env_path=""
    local declared=0

    if [[ -n "${BRIK_CONFIG_FILE:-}" && -f "${BRIK_CONFIG_FILE}" ]]; then
        env_path="$(config.get '.project.env' '' 2>/dev/null)" || env_path=""
        [[ -n "$env_path" ]] && declared=1
    fi

    if [[ -z "$env_path" ]]; then
        if [[ -f "brik.env" ]]; then
            env_path="brik.env"
        else
            return 0
        fi
    fi

    if [[ ! -f "$env_path" ]]; then
        if [[ "$declared" -eq 1 ]]; then
            log.error "project.env '$env_path' declared in brik.yml but file is missing"
            return 1
        fi
        return 0
    fi

    transverse.env._source_file "$env_path"
}

# -----------------------------------------------------------------------------
# transverse.env.load_deploy_env <env_name>
# -----------------------------------------------------------------------------
transverse.env.load_deploy_env() {
    local env_name="$1"
    [[ -z "$env_name" ]] && return 0

    if [[ -z "${BRIK_CONFIG_FILE:-}" || ! -f "${BRIK_CONFIG_FILE}" ]]; then
        return 0
    fi

    local env_path
    env_path="$(config.get ".deploy.environments.${env_name}.env_file" '' 2>/dev/null)" || env_path=""
    [[ -z "$env_path" ]] && return 0

    if [[ ! -f "$env_path" ]]; then
        log.error "deploy environment '$env_name' declares env_file '$env_path' but it is missing"
        return 1
    fi

    transverse.env._source_file "$env_path"
}

# -----------------------------------------------------------------------------
# transverse.env._source_file <path>
#
# Private KEY=VALUE parser. Does not execute the file as bash - this avoids
# arbitrary code execution from user-authored .env files. Skips comment lines
# (# ...), blank lines, and anything that does not match a valid bash
# identifier followed by '='. Strips matched surrounding double or single
# quotes. Never overwrites a variable that is already set in the environment.
# -----------------------------------------------------------------------------
transverse.env._source_file() {
    local file="$1"
    [[ ! -f "$file" ]] && return 0

    local line key value
    while IFS= read -r line || [[ -n "$line" ]]; do
        # Strip CRLF line endings from Windows-authored .env files.
        line="${line%$'\r'}"

        # Skip blank lines and comment lines (ignoring leading whitespace).
        [[ -z "${line//[[:space:]]/}" ]] && continue
        [[ "$line" =~ ^[[:space:]]*# ]] && continue

        # Must match KEY=VALUE where KEY is a valid bash identifier.
        if [[ ! "$line" =~ ^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
            continue
        fi
        key="${BASH_REMATCH[1]}"
        value="${BASH_REMATCH[2]}"

        # Strip matched surrounding double or single quotes.
        if [[ "$value" =~ ^\"(.*)\"$ ]]; then
            value="${BASH_REMATCH[1]}"
        elif [[ "$value" =~ ^\'(.*)\'$ ]]; then
            value="${BASH_REMATCH[1]}"
        fi

        # Already-set variables win (CI precedence).
        if [[ -z "${!key+x}" ]]; then
            export "$key=$value"
        fi
    done < "$file"

    return 0
}
