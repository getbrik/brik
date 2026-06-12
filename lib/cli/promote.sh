#!/usr/bin/env bash
# @module cli.promote
# @description CLI entrypoint for "brik promote" -- the artifact-scoped
#   promotion verb.
#
# Promotes a version from one artifact channel to another through
# channel.copy_with_referrers: the image moves digest-pinned WITH its signed
# evidence graph (OCI referrers), the destination channel is immutable, and
# the move is proven on the destination (digest identity + attestation
# verification) fail-closed. The CI promote stage consumes the same primitive
# on tagged runs; this verb is its on-demand counterpart.

# Guard against double-sourcing.
[[ -n "${_BRIK_MODULE_CLI_PROMOTE_LOADED:-}" ]] && return 0
_BRIK_MODULE_CLI_PROMOTE_LOADED=1

# _cli.promote._notify - best-effort webhook notification of the promotion.
# An unreachable webhook is a warning, never a refusal: the journal entry
# and the destination registry ARE the promotion; the notification only
# broadcasts it. Skips silently when no webhook is configured.
# Usage: _cli.promote._notify <version> <digest> <from> <to>
_cli.promote._notify() {
    local version="$1" digest="$2" from="$3" to="$4"

    brik.use stages.notify
    notify.webhook_configured || return 0

    local payload
    payload="$(jq -n \
        --arg version "$version" \
        --arg digest "$digest" \
        --arg from "$from" \
        --arg to "$to" \
        '{event: "artifact_promoted", version: $version, digest: $digest,
          from_channel: $from, to_channel: $to}')"

    if ! notify.webhook --payload "$payload"; then
        log.warn "promote: webhook notification failed (the promotion stands; delivery is best-effort)"
    fi
    return 0
}

# cli.promote.run - promote <version> from one channel to another.
# Usage: brik promote --version <v> [--from <channel>] [--to <channel>]
#        [--config <path>] [--workspace <path>]
#        [--identity <re>] [--issuer <re>] [--dry-run]
cli.promote.run() {
    brik.use cli.helpers

    local version="" from="candidate" to="release"
    local config_path="" workspace="" identity="" issuer="" dry_run=""
    workspace="$(pwd)"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --version)   brik_require_arg "--version" "${2-}" || return "$?"
                         version="$2"; shift 2 ;;
            --from)      brik_require_arg "--from" "${2-}" || return "$?"
                         from="$2"; shift 2 ;;
            --to)        brik_require_arg "--to" "${2-}" || return "$?"
                         to="$2"; shift 2 ;;
            --config)    brik_require_arg "--config" "${2-}" || return "$?"
                         config_path="$2"; shift 2 ;;
            --workspace) brik_require_arg "--workspace" "${2-}" || return "$?"
                         workspace="$2"; shift 2 ;;
            --identity)  brik_require_arg "--identity" "${2-}" || return "$?"
                         identity="$2"; shift 2 ;;
            --issuer)    brik_require_arg "--issuer" "${2-}" || return "$?"
                         issuer="$2"; shift 2 ;;
            --dry-run)   dry_run="true"; shift ;;
            *) brik_usage_error "unknown option: $1" || return "$?" ;;
        esac
    done

    if [[ -z "$version" ]]; then
        brik_error "'brik promote' requires --version"
        return "${BRIK_EXIT_INVALID_INPUT}"
    fi
    if [[ "$from" == "$to" ]]; then
        brik_error "'brik promote' requires two distinct channels (--from ${from} --to ${to})"
        return "${BRIK_EXIT_INVALID_INPUT}"
    fi

    [[ -z "$config_path" ]] && config_path="${workspace}/${BRIK_DEFAULT_CONFIG}"
    pipeline.require_file "${config_path}" || return "${BRIK_EXIT_IO_FAILURE}"
    export BRIK_CONFIG_FILE="${config_path}"
    export BRIK_LOG_DIR="${BRIK_LOG_DIR:-${workspace}/.brik-logs}"
    mkdir -p "${BRIK_LOG_DIR}"

    # Promotion init gate (parity with the CD verb): the referential is
    # mandatory and validated eagerly -- the copy derives its registry
    # transport from it and the verification its trust material.
    brik.use transverse.infra
    local infra_root
    infra_root="$(infra.root)" || return "$?"
    infra.validate "$infra_root" || return "$?"

    brik.use transverse.channel

    if [[ "$dry_run" == "true" ]]; then
        local from_registry to_registry
        from_registry="$(channel.registry "$from")" || return "$?"
        to_registry="$(channel.registry "$to")" || return "$?"
        log.info "[dry-run] would copy ${from_registry}:${version} -> ${to_registry}:${version} (with referrers) and verify the destination"
        return 0
    fi

    local -a copy_args=("$version" "$from" "$to")
    [[ -n "$identity" ]] && copy_args+=(--identity "$identity")
    [[ -n "$issuer" ]]   && copy_args+=(--issuer "$issuer")

    local pinned
    pinned="$(channel.copy_with_referrers "${copy_args[@]}")" || return "$?"

    # Journal the transition in the project's state-repo (self-skips when
    # none is declared); a declared journal that cannot record refuses the
    # promotion outcome, as the eligibility gates read it as source of truth.
    brik.use transverse.promotion_journal
    promotion_journal.record_promotion \
        --version "$version" --digest "${pinned##*@}" \
        --from-channel "$from" --to-channel "$to" || return "$?"

    _cli.promote._notify "$version" "${pinned##*@}" "$from" "$to"

    log.info "promoted ${version}: ${from} -> ${to}"
    brik_print "$pinned"
}
