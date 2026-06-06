#!/usr/bin/env bash
# @module cli.deploy
# @description CLI entrypoint for "brik deploy" -- the CD verb.
#
# Mode 2 (explicit, parameterized by version + environment), the counterpart of
# the event-driven CI flow. It loads config, resolves the version to a
# digest-pinned image ref within the channel the environment accepts, enforces
# the require_digest gate (fail-closed), writes a deploy-kind plan, and runs the
# deploy stage restricted to the chosen environment with the pinned ref injected.
#
# All business logic lives here / in lib/; the platform wrappers only map their
# inputs to `brik deploy --version <v> --environment <e>`.

# Guard against double-sourcing.
[[ -n "${_BRIK_MODULE_CLI_DEPLOY_LOADED:-}" ]] && return 0
_BRIK_MODULE_CLI_DEPLOY_LOADED=1

# cli.deploy.run - deploy <version> to <environment>.
# Usage: brik deploy --version <v> --environment <e> [--strategy <s>]
#        [--config <path>] [--workspace <path>] [--dry-run]
cli.deploy.run() {
    brik.use cli.helpers

    local version="" environment="" strategy="" dry_run=""
    local config_path="" workspace=""
    workspace="$(pwd)"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --version)     brik_require_arg "--version" "${2-}" || return "$?"
                           version="$2"; shift 2 ;;
            --environment) brik_require_arg "--environment" "${2-}" || return "$?"
                           environment="$2"; shift 2 ;;
            --strategy)    brik_require_arg "--strategy" "${2-}" || return "$?"
                           strategy="$2"; shift 2 ;;
            --config)      brik_require_arg "--config" "${2-}" || return "$?"
                           config_path="$2"; shift 2 ;;
            --workspace)   brik_require_arg "--workspace" "${2-}" || return "$?"
                           workspace="$2"; shift 2 ;;
            --dry-run)     dry_run="true"; shift ;;
            *) brik_usage_error "unknown option: $1" || return "$?" ;;
        esac
    done

    if [[ -z "$version" ]]; then
        brik_error "'brik deploy' requires --version"
        return "${BRIK_EXIT_INVALID_INPUT}"
    fi
    if [[ -z "$environment" ]]; then
        brik_error "'brik deploy' requires --environment"
        return "${BRIK_EXIT_INVALID_INPUT}"
    fi

    if [[ -z "$config_path" ]]; then
        config_path="${workspace}/${BRIK_DEFAULT_CONFIG}"
    fi

    export BRIK_PROJECT_DIR="${workspace}"
    export BRIK_WORKSPACE="${workspace}"
    export BRIK_CONFIG_FILE="${config_path}"
    export BRIK_LOG_DIR="${BRIK_LOG_DIR:-${workspace}/.brik-logs}"
    mkdir -p "${BRIK_LOG_DIR}"
    [[ "$dry_run" == "true" ]] && export BRIK_DRY_RUN="true"

    # Bring up the local runtime: this loads brik.yml and exports the
    # BRIK_DEPLOY_<ENV>_* variables (target, channel, require_digest, ...).
    local wrapper="${BRIK_HOME}/shared-libs/local/scripts/local-wrapper.sh"
    pipeline.require_file "${wrapper}" || return "$?"
    # shellcheck source=/dev/null
    . "${wrapper}"
    local rc
    set +e
    brik.local.setup
    rc=$?
    set -e
    [[ "$rc" -ne 0 ]] && return "$rc"

    brik.use transverse.env

    local upper_env
    upper_env="$(printf '%s' "$environment" | tr '[:lower:]-' '[:upper:]_')"

    local target
    target="$(transverse.env.resolve_indirect "BRIK_DEPLOY_${upper_env}_TARGET")"
    if [[ -z "$target" ]]; then
        brik_error "unknown deploy environment '${environment}' (no target in brik.yml)"
        return "${BRIK_EXIT_CONFIG_ERROR}"
    fi

    # Resolve the version to a digest-pinned ref in the channel this env
    # accepts, then enforce the require_digest gate fail-closed.
    local channel require_digest pinned=""
    channel="$(transverse.env.resolve_indirect "BRIK_DEPLOY_${upper_env}_CHANNEL")"
    require_digest="$(transverse.env.resolve_indirect "BRIK_DEPLOY_${upper_env}_REQUIRE_DIGEST")"

    if [[ -n "$channel" ]]; then
        brik.use transverse.channel
        if pinned="$(channel.resolve_digest "$version" "$channel")"; then
            export BRIK_DEPLOY_IMAGE_REF="$pinned"
            log.info "resolved ${version} in channel '${channel}' -> ${pinned}"
        elif [[ "$require_digest" == "true" ]]; then
            brik_error "require_digest: cannot resolve '${version}' in channel '${channel}' -- failing closed"
            return "${BRIK_EXIT_EXTERNAL_FAIL}"
        else
            log.warn "could not resolve a digest for '${version}' in channel '${channel}'; deploying without a pinned ref"
        fi
    elif [[ "$require_digest" == "true" ]]; then
        brik_error "require_digest is set for '${environment}' but no accepts_channel is configured -- failing closed"
        return "${BRIK_EXIT_CONFIG_ERROR}"
    fi

    # Strategy override (CLI wins over brik.yml) and single-env targeting.
    [[ -n "$strategy" ]] && export "BRIK_DEPLOY_${upper_env}_STRATEGY=$strategy"
    export BRIK_DEPLOY_ONLY_ENV="$environment"

    # Write a deploy-kind plan (parity with CI / informational). Best-effort:
    # a plan write failure does not block an otherwise valid deploy.
    brik.use cli.plan
    local _plan="${BRIK_LOG_DIR}/plan.json"
    set +e
    cli.plan.run --workspace "$workspace" --type deploy \
        --version "$version" --environment "$environment" --out "$_plan" >/dev/null 2>&1
    set -e

    # Run the deploy stage (restricted to this env, pinned ref injected).
    set +e
    brik.local.run_deploy
    rc=$?
    set -e
    return "$rc"
}
