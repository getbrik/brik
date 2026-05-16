#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# @module config
# @description Reads brik.yml via yq and exports stage-relevant environment variables.
#
# Portable configuration reader for the Brik runtime.
# Loaded via: brik.use config
#
# Requires: yq (mikefarah/yq v4+)

# Guard against double-sourcing (compatible with brik.use)
[[ -n "${_BRIK_CORE_CONFIG_LOADED:-}" ]] && return 0
_BRIK_CORE_CONFIG_LOADED=1

# Base directory for config sub-modules
_BRIK_CONFIG_DIR="${BASH_SOURCE[0]%/*}/config"

# Load a config sub-module by stack name.
# Config sub-modules are co-located in _BRIK_CONFIG_DIR and have their own
# double-sourcing guards, so direct sourcing is safe and avoids dependency
# on the brik.use loader (which may be mocked or unavailable in tests).
_config._load_module() {
    local stack="$1"
    local module_path="${_BRIK_CONFIG_DIR}/${stack}.sh"
    if [[ -f "$module_path" ]]; then
        # shellcheck source=/dev/null
        . "$module_path"
    else
        return "$BRIK_EXIT_FAILURE"
    fi
}

# Ensure runtime logging and the brik.use loader are available. base-wrapper
# bootstrap sources them before calling `brik.use config`, but standalone
# callers (specs that Include this file directly, ad-hoc CLI usage) need a
# self-source fallback.
if [[ -z "${_BRIK_LOGGING_LOADED:-}" ]]; then
    local_runtime_dir="${BASH_SOURCE[0]%/*}/../pipeline"
    if [[ -f "${local_runtime_dir}/logging.sh" ]]; then
        # shellcheck source=../pipeline/logging.sh
        . "${local_runtime_dir}/logging.sh"
    fi
    unset local_runtime_dir
fi
if [[ -z "${_BRIK_LOADER_LOADED:-}" ]]; then
    local_runtime_dir="${BASH_SOURCE[0]%/*}/../pipeline"
    if [[ -f "${local_runtime_dir}/loader.sh" ]]; then
        # shellcheck source=../pipeline/loader.sh
        . "${local_runtime_dir}/loader.sh"
    fi
    unset local_runtime_dir
fi
# Default BRIK_LIB_EXTENSIONS for standalone callers (specs, ad-hoc CLI).
# base-wrapper sets a richer value during bootstrap; we keep that one when
# present.
if [[ -z "${BRIK_LIB_EXTENSIONS:-}" && -n "${BRIK_HOME:-}" ]]; then
    export BRIK_LIB_EXTENSIONS="${BRIK_HOME}/lib/transverse:${BRIK_HOME}/lib"
fi

# Eagerly load all per-stage export modules so config.export_*_vars are
# available to direct callers (stages call individual exports;
# config.export_all orchestrates the full pass). Each module has its own
# double-source guard, and brik.use is idempotent, so re-entrancy is safe.
# Load release first because package and deploy depend on
# _config._export_trigger_vars hosted there.
brik.use transverse.config.exports.release
brik.use transverse.config.exports.build
brik.use transverse.config.exports.test
brik.use transverse.config.exports.quality
brik.use transverse.config.exports.security
brik.use transverse.config.exports.package
brik.use transverse.config.exports.deploy
brik.use transverse.config.exports.notify
brik.use transverse.config.exports.hooks
brik.use transverse.config.exports.publish
brik.use transverse.config.exports.runner

# ---------------------------------------------------------------------------
# Core config functions
# ---------------------------------------------------------------------------

# Load and validate that the config file exists.
# Usage: config.read <brik_yml_path>
config.read() {
    local config_path="${1:-brik.yml}"

    if [[ ! -f "$config_path" ]]; then
        log.error "config file not found: $config_path"
        return "$BRIK_EXIT_CONFIG_ERROR"
    fi

    if ! command -v yq >/dev/null 2>&1; then
        log.error "yq is required but not found on PATH"
        return "$BRIK_EXIT_MISSING_DEP"
    fi

    # Validate YAML is parseable
    if ! yq '.' "$config_path" >/dev/null 2>&1; then
        log.error "failed to parse $config_path as YAML"
        return "$BRIK_EXIT_INVALID_INPUT"
    fi

    export BRIK_CONFIG_FILE="$config_path"
    return 0
}

# Read a value from brik.yml with optional default.
# Usage: config.get <yq_path> [default]
# Example: config.get '.project.stack' 'auto'
config.get() {
    local yq_path="$1"
    local default_value="${2:-}"
    local config_file="${BRIK_CONFIG_FILE:-brik.yml}"

    if [[ ! -f "$config_file" ]]; then
        if [[ -n "$default_value" ]]; then
            printf '%s' "$default_value"
            return 0
        fi
        return "$BRIK_EXIT_CONFIG_ERROR"
    fi

    local value
    value="$(yq "${yq_path}" "$config_file" 2>/dev/null)"

    # yq returns "null" for missing keys
    if [[ "$value" == "null" || -z "$value" ]]; then
        if [[ -n "$default_value" ]]; then
            printf '%s' "$default_value"
            return 0
        fi
        return "$BRIK_EXIT_FAILURE"
    fi

    printf '%s' "$value"
    return 0
}

# Check if a stage is enabled in brik.yml.
# Usage: config.stage_enabled <stage_name>
# Returns 0 if enabled, 1 if disabled.
config.stage_enabled() {
    local stage_name="$1"

    case "$stage_name" in
        init|build|test|notify|verify)
            # These stages are always enabled
            return 0
            ;;
        lint)
            local enabled
            enabled="$(config.get '.quality.lint.enabled')" || enabled="true"
            [[ "$enabled" == "true" ]]
            return $?
            ;;
        sast|scan)
            # Always enabled when reached (non-negotiable scans)
            return 0
            ;;
        container_scan)
            # Enabled only if container image is configured
            local container_image
            container_image="$(config.get '.security.container.image' '')"
            [[ -n "$container_image" ]]
            return $?
            ;;
        release)
            # Enabled if version section exists
            local version_strategy
            version_strategy="$(config.get '.release.strategy' '')"
            [[ -n "$version_strategy" ]]
            return $?
            ;;
        package)
            # Enabled if package section exists
            local package_type
            package_type="$(config.get '.package.docker.image' '')"
            [[ -n "$package_type" ]]
            return $?
            ;;
        deploy)
            # Enabled if deploy.workflow is set OR deploy.environments exists and is not empty
            local workflow
            workflow="$(config.get '.deploy.workflow' '' 2>/dev/null)" || workflow=""
            if [[ -n "$workflow" && "$workflow" != "null" ]]; then
                return 0
            fi
            local env_count
            env_count="$(config.get '.deploy.environments | length' '0')"
            [[ "$env_count" -gt 0 ]] 2>/dev/null
            return $?
            ;;
        *)
            return "$BRIK_EXIT_FAILURE"
            ;;
    esac
}

# ---------------------------------------------------------------------------
# Stack detection and defaults
# ---------------------------------------------------------------------------

# Stack defaults table
# Returns the default value for a stack-specific setting.
# Usage: config.stack_default <stack> <setting>
config.stack_default() {
    local stack="$1"
    local setting="$2"

    # Load stack config module if available
    _config._load_module "$stack" || return "$BRIK_EXIT_FAILURE"

    local fn="config.${stack}.default"
    if declare -f "$fn" >/dev/null 2>&1; then
        "$fn" "$setting"
        return $?
    fi
    return "$BRIK_EXIT_FAILURE"
}


# ---------------------------------------------------------------------------
# JSON Schema validation
# ---------------------------------------------------------------------------

# Validate brik.yml against the bundled JSON Schema.
# Prefers jv (Go static binary, shipped in brik-runner-base); falls back
# to check-jsonschema (Python) for dev hosts without jv.
# Returns 7 on validation failure, 0 on success or graceful skip.
# Skips silently when no validator is available; warns when the schema is missing.
# Usage: config.validate_schema [config_path] [schema_path]
config.validate_schema() {
    local config_file="${1:-${BRIK_CONFIG_FILE:-}}"
    local schema_file="${2:-${BRIK_HOME:-/opt/brik}/schemas/config/v1/brik.schema.json}"

    if [[ -z "$config_file" || ! -f "$config_file" ]]; then
        log.error "config file not found: ${config_file:-<unset>}"
        return "$BRIK_EXIT_CONFIG_ERROR"
    fi

    if [[ ! -f "$schema_file" ]]; then
        log.warn "schema file not found: $schema_file - skipping validation"
        return 0
    fi

    local validator
    if command -v jv >/dev/null 2>&1; then
        validator="jv"
    elif command -v check-jsonschema >/dev/null 2>&1; then
        validator="check-jsonschema"
    else
        log.debug "no JSON Schema validator found - skipping schema validation"
        return 0
    fi

    local output rc
    if [[ "$validator" == "jv" ]]; then
        output="$(yq -o json '.' "$config_file" 2>/dev/null | jv "$schema_file" - 2>&1)" && rc=0 || rc=$?
    else
        output="$(yq -o json '.' "$config_file" 2>/dev/null | check-jsonschema --schemafile "$schema_file" - 2>&1)" && rc=0 || rc=$?
    fi

    if [[ $rc -ne 0 ]]; then
        log.error "brik.yml schema validation failed (rc=$rc)"
        while IFS= read -r line; do
            [[ -n "$line" ]] && log.error "  $line"
        done <<< "$output"
        return "$BRIK_EXIT_CONFIG_ERROR"
    fi

    log.debug "brik.yml schema validation passed (via ${validator})"
    return 0
}

# ---------------------------------------------------------------------------
# Config coherence validation
# ---------------------------------------------------------------------------

# Validate that resolved config values are coherent with the actual project.
# Called from init after config.export_all to fail fast on mismatches.
# Returns 7 on coherence errors, 0 otherwise.
config.validate_coherence() {
    local stack="${BRIK_BUILD_STACK:-auto}"
    local config_file="${BRIK_CONFIG_FILE:-${BRIK_WORKSPACE:-.}/brik.yml}"

    if [[ -z "${BRIK_WORKSPACE:-}" ]]; then
        log.warn "BRIK_WORKSPACE not set - skipping coherence validation"
        return 0
    fi

    local workspace="$BRIK_WORKSPACE"

    # Cross-block coherence rules (run regardless of stack auto-detection).
    # All four rules originate from chantier 6 §2.12.
    local errors=0

    # Rule 1: build.<stack>_version was removed in favour of project.stack_version.
    # Old brik.yml files still using these keys would otherwise pass JSON Schema
    # silently (additionalProperties already rejects them, but we log a clearer
    # error here when the file is parsed via legacy paths).
    local legacy_v
    for legacy_v in node_version java_version python_version dotnet_version rust_version; do
        if [[ -n "$(yq ".build.${legacy_v} // \"\"" "$config_file" 2>/dev/null)" ]]; then
            log.error "build.${legacy_v} is no longer supported; use project.stack_version"
            ((errors++))
        fi
    done

    # Rule 2: publish.docker.image is deprecated (will be removed in a future
    # release in favour of package.docker.image as the single source of truth).
    if [[ -n "$(yq '.publish.docker.image // ""' "$config_file" 2>/dev/null)" ]]; then
        log.warn "publish.docker.image is deprecated; declare the image in package.docker.image instead"
    fi

    # Rule 3: deploy.environments.*.target=gitops requires both repo and path.
    # Without these the gitops deploy crashes late with an unhelpful error.
    local env_name target repo path
    while IFS= read -r env_name; do
        [[ -z "$env_name" ]] && continue
        target="$(yq ".deploy.environments.\"${env_name}\".target // \"\"" "$config_file" 2>/dev/null)"
        if [[ "$target" == "gitops" ]]; then
            repo="$(yq ".deploy.environments.\"${env_name}\".repo // \"\"" "$config_file" 2>/dev/null)"
            path="$(yq ".deploy.environments.\"${env_name}\".path // \"\"" "$config_file" 2>/dev/null)"
            if [[ -z "$repo" || -z "$path" ]]; then
                log.error "deploy.environments.${env_name}.target=gitops requires both 'repo' and 'path'"
                ((errors++))
            fi
        fi
    done < <(yq '.deploy.environments | keys | .[]' "$config_file" 2>/dev/null)

    # Rule 4: a tag was pushed but release is disabled. Warn so the silent
    # skip does not surprise the user.
    if [[ "$(yq '.release.enabled // ""' "$config_file" 2>/dev/null)" == "false" \
       && -n "${CI_COMMIT_TAG:-}" ]]; then
        log.warn "tag '${CI_COMMIT_TAG}' pushed but release.enabled is false; release stage will be skipped"
    fi

    if [[ $errors -gt 0 ]]; then
        log.error "config validation failed: ${errors} error(s)"
        return "$BRIK_EXIT_CONFIG_ERROR"
    fi

    if [[ "$stack" == "auto" || "$stack" == "unknown" ]]; then
        return 0
    fi

    # Delegate to stack-specific coherence validator
    if _config._load_module "$stack"; then
        local fn="config.${stack}.validate_coherence"
        if declare -f "$fn" >/dev/null 2>&1; then
            "$fn" "$workspace" || return "$BRIK_EXIT_CONFIG_ERROR"
        fi
    fi

    return 0
}

# Export all configuration variables at once.
# Convenience function for jobs that need full context.
config.export_all() {
    local config_path="${1:-${BRIK_CONFIG_FILE:-brik.yml}}"

    config.read "$config_path" || return $?

    # Project-level vars
    local project_name
    project_name="$(config.get '.project.name' '')"
    export BRIK_PROJECT_NAME="$project_name"

    local project_root
    project_root="$(config.get '.project.root' '.')"
    export BRIK_PROJECT_ROOT="$project_root"

    config.export_build_vars
    config.export_runner_vars
    config.export_test_vars
    config.export_quality_vars
    config.export_security_vars
    config.export_package_vars
    config.export_deploy_vars
    config.export_notify_vars
    config.export_hooks_vars
    config.export_release_vars
    config.export_publish_vars

    return 0
}
