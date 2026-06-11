#!/usr/bin/env bash
# @module cli.authorize
# @description CLI entrypoint for "brik authorize" -- the release
#   authorization verb.
#
# Grants an artifact the eligibility to deploy to an environment by
# appending an artifact_authorized_for event to the PromotionJournal. The
# grant is digest-bound: the version is resolved in the channel the target
# environment accepts and the journal entry carries that digest, so an
# authorization can never be replayed against a different artifact. The
# requires_eligibility gate at deploy reads this journal as its source of
# truth.

# Guard against double-sourcing.
[[ -n "${_BRIK_MODULE_CLI_AUTHORIZE_LOADED:-}" ]] && return 0
_BRIK_MODULE_CLI_AUTHORIZE_LOADED=1

# Best-effort webhook notification of the grant. An unreachable webhook is a
# warning, never a refusal: the journal entry IS the authorization; the
# notification only broadcasts it.
# Usage: _cli.authorize._notify <version> <digest> <environment>
_cli.authorize._notify() {
    local version="$1" digest="$2" environment="$3"
    local url="${BRIK_NOTIFY_WEBHOOK_URL:-}"
    [[ -z "$url" ]] && return 0

    local payload
    payload="$(jq -n \
        --arg version "$version" \
        --arg digest "$digest" \
        --arg environment "$environment" \
        '{event: "artifact_authorized_for", version: $version, digest: $digest, environment: $environment}')"

    if ! curl -sf --max-time 10 -H 'Content-Type: application/json' \
            -d "$payload" "$url" >/dev/null 2>&1; then
        log.warn "authorize: webhook notification failed (the grant stands; delivery is best-effort)"
    fi
    return 0
}

# cli.authorize.run - authorize <version> for <environment>.
# Usage: brik authorize --version <v> --for <env>
#        [--config <path>] [--workspace <path>] [--dry-run]
cli.authorize.run() {
    brik.use cli.helpers

    local version="" environment="" config_path="" workspace="" dry_run=""
    workspace="$(pwd)"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --version)   brik_require_arg "--version" "${2-}" || return "$?"
                         version="$2"; shift 2 ;;
            --for)       brik_require_arg "--for" "${2-}" || return "$?"
                         environment="$2"; shift 2 ;;
            --config)    brik_require_arg "--config" "${2-}" || return "$?"
                         config_path="$2"; shift 2 ;;
            --workspace) brik_require_arg "--workspace" "${2-}" || return "$?"
                         workspace="$2"; shift 2 ;;
            --dry-run)   dry_run="true"; shift ;;
            *) brik_usage_error "unknown option: $1" || return "$?" ;;
        esac
    done

    if [[ -z "$version" ]]; then
        brik_error "'brik authorize' requires --version"
        return "${BRIK_EXIT_INVALID_INPUT}"
    fi
    if [[ -z "$environment" ]]; then
        brik_error "'brik authorize' requires --for <environment>"
        return "${BRIK_EXIT_INVALID_INPUT}"
    fi

    [[ -z "$config_path" ]] && config_path="${workspace}/${BRIK_DEFAULT_CONFIG}"
    pipeline.require_file "${config_path}" || return "${BRIK_EXIT_IO_FAILURE}"
    export BRIK_CONFIG_FILE="${config_path}"
    export BRIK_LOG_DIR="${BRIK_LOG_DIR:-${workspace}/.brik-logs}"
    mkdir -p "${BRIK_LOG_DIR}"

    # Authorization init gate (parity with the deploy and promote verbs):
    # the referential is mandatory and validated eagerly -- the channel
    # resolution derives its registry transport from it.
    brik.use transverse.infra
    local infra_root
    infra_root="$(infra.root)" || return "$?"
    infra.validate "$infra_root" || return "$?"

    # The grant binds to a digest in the channel the environment accepts; an
    # environment without an accepted channel has no digest to bind to.
    brik.use transverse.config
    local channel
    channel="$(config.get ".deploy.environments.${environment}.accepts_channel" '' 2>/dev/null || printf '')"
    if [[ -z "$channel" ]]; then
        brik_error "environment '${environment}' declares no accepts_channel -- an authorization binds to a digest, refusing"
        return "${BRIK_EXIT_CONFIG_ERROR}"
    fi

    brik.use transverse.channel
    local pinned rc=0
    pinned="$(channel.resolve_digest "$version" "$channel")" || rc=$?
    if [[ "$rc" -ne 0 ]]; then
        brik_error "cannot resolve '${version}' in channel '${channel}' -- failing closed"
        return "$rc"
    fi
    local digest="${pinned##*@}"

    if [[ "$dry_run" == "true" ]]; then
        log.info "[dry-run] would journal artifact_authorized_for ${version} (${digest}) for ${environment}"
        return 0
    fi

    brik.use transverse.promotion_journal
    promotion_journal.record_authorization \
        --version "$version" --digest "$digest" \
        --environment "$environment" || return "$?"

    _cli.authorize._notify "$version" "$digest" "$environment"

    log.info "authorized ${version} for ${environment} (${digest})"
    brik_print "$pinned"
}
