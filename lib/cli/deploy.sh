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

# _cli.deploy._resolve_version_tag - echo the git tag for a version, or fail.
# Tries the version verbatim, then prefixed with .release.tag_prefix (default
# "v"). Used to resolve the deployment definition at the version's ref.
# Usage: tag="$(_cli.deploy._resolve_version_tag <workspace> <version>)"
_cli.deploy._resolve_version_tag() {
    local ws="$1" version="$2" prefix cand
    brik.use transverse.config
    prefix="$(BRIK_CONFIG_FILE="${ws}/${BRIK_DEFAULT_CONFIG}" \
        config.get '.release.tag_prefix' 'v' 2>/dev/null || printf 'v')"
    for cand in "$version" "${prefix}${version}"; do
        if git -C "$ws" rev-parse -q --verify "refs/tags/${cand}^{commit}" >/dev/null 2>&1; then
            printf '%s' "$cand"
            return 0
        fi
    done
    return 1
}

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

    local config_explicit=""
    [[ -n "$config_path" ]] && config_explicit="true"

    # T6 -- co-versioned definition resolution: deploy the templates/manifests
    # AS OF the version's git ref, not the current working tree, so re-deploying
    # an older version reproduces that version's definition. When HEAD is already
    # at the tag (CI->CD immediate) or no tag matches, deploy from the current
    # tree (no checkout). An explicit --config opts out (caller pinned the file).
    local orig_workspace="${workspace}" worktree=""
    if [[ -z "$config_explicit" ]] && git -C "${workspace}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        brik.use transverse.git
        local _tag _head _tagsha
        if _tag="$(_cli.deploy._resolve_version_tag "${workspace}" "${version}")"; then
            _head="$(git -C "${workspace}" rev-parse HEAD 2>/dev/null || true)"
            _tagsha="$(git -C "${workspace}" rev-parse "${_tag}^{commit}" 2>/dev/null || true)"
            if [[ -n "$_tagsha" && "$_head" != "$_tagsha" ]]; then
                worktree="$(transverse.git.worktree_at "${workspace}" "${_tagsha}")" || worktree=""
                if [[ -n "$worktree" ]]; then
                    workspace="$worktree"
                    log.info "resolving deployment definition at ${_tag} (${version})"
                fi
            fi
        fi
    fi

    if [[ -z "$config_path" ]]; then
        config_path="${workspace}/${BRIK_DEFAULT_CONFIG}"
    fi

    # The deploy targets resolve manifest/chart/values/source relative to the
    # working directory, so run from the resolved workspace (the version tree
    # when checked out, otherwise the caller's project dir).
    cd "${workspace}" || return "${BRIK_EXIT_IO_FAILURE}"

    export BRIK_PROJECT_DIR="${workspace}"
    export BRIK_WORKSPACE="${workspace}"
    export BRIK_CONFIG_FILE="${config_path}"
    export BRIK_LOG_DIR="${BRIK_LOG_DIR:-${orig_workspace}/.brik-logs}"
    mkdir -p "${BRIK_LOG_DIR}"
    [[ "$dry_run" == "true" ]] && export BRIK_DRY_RUN="true"

    # Bring up the local runtime: this loads brik.yml and exports the
    # BRIK_DEPLOY_<ENV>_* variables (target, channel, require_digest, ...).
    local wrapper="${BRIK_HOME}/shared-libs/local/scripts/local-wrapper.sh"
    if ! pipeline.require_file "${wrapper}"; then
        [[ -n "$worktree" ]] && transverse.git.worktree_remove "${orig_workspace}" "${worktree}"
        return "${BRIK_EXIT_IO_FAILURE}"
    fi
    # shellcheck source=/dev/null
    . "${wrapper}"
    local rc
    set +e
    brik.local.setup
    rc=$?
    set -e
    if [[ "$rc" -ne 0 ]]; then
        [[ -n "$worktree" ]] && transverse.git.worktree_remove "${orig_workspace}" "${worktree}"
        return "$rc"
    fi

    brik.use transverse.env

    local upper_env
    upper_env="$(printf '%s' "$environment" | tr '[:lower:]-' '[:upper:]_')"

    local target
    target="$(transverse.env.resolve_indirect "BRIK_DEPLOY_${upper_env}_TARGET")"
    if [[ -z "$target" ]]; then
        brik_error "unknown deploy environment '${environment}' (no target in brik.yml)"
        return "${BRIK_EXIT_CONFIG_ERROR}"
    fi

    # The append-only guarantee of the evidence store rests on host-side
    # branch protection: check it before consuming evidence. Until the
    # referential's Policy kind sets the gate semantics per profile, an
    # unprotected or unverifiable branch is a loud warning, not a refusal
    # (the lab carries no protection before its first hardening tier).
    if [[ "$dry_run" != "true" ]]; then
        brik.use transverse.config
        local ev_repo
        ev_repo="$(config.get '.artifacts.evidence.repo' '' 2>/dev/null || printf '')"
        if [[ -n "$ev_repo" ]]; then
            brik.use transverse.state_repo
            local ev_branch prot_rc=0
            ev_branch="$(config.get '.artifacts.evidence.branch' '' 2>/dev/null || printf '')"
            transverse.state_repo.check_protection "$ev_repo" "${ev_branch:-main}" \
                --environment "$environment" || prot_rc=$?
            if [[ "$prot_rc" -ne 0 && "$prot_rc" -ne 10 ]]; then
                log.warn "state-repo branch protection could not be verified (rc=${prot_rc})"
            fi
        fi
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

    # Provenance gate: verify the signed attestation on the resolved digest
    # before deploying. Fail-closed -- an environment that requires provenance
    # but has no digest to verify, or whose attestation does not verify, is
    # refused rather than deployed.
    local require_provenance
    require_provenance="$(transverse.env.resolve_indirect "BRIK_DEPLOY_${upper_env}_REQUIRE_PROVENANCE")"
    if [[ "$require_provenance" == "true" ]]; then
        if [[ -z "$pinned" ]]; then
            brik_error "require_provenance: no digest-pinned ref to verify for '${environment}' -- failing closed"
            return "${BRIK_EXIT_EXTERNAL_FAIL}"
        fi
        brik.use transverse.attest
        local verify_identity verify_issuer
        verify_identity="$(transverse.env.resolve_indirect "BRIK_DEPLOY_${upper_env}_VERIFY_IDENTITY")"
        verify_issuer="$(transverse.env.resolve_indirect "BRIK_DEPLOY_${upper_env}_VERIFY_ISSUER")"
        local -a verify_args=("$pinned")
        [[ -n "$verify_identity" ]] && verify_args+=(--identity "$verify_identity")
        [[ -n "$verify_issuer" ]]   && verify_args+=(--issuer "$verify_issuer")
        if ! attest.verify "${verify_args[@]}"; then
            brik_error "require_provenance: attestation did not verify for ${pinned} -- failing closed"
            return "${BRIK_EXIT_EXTERNAL_FAIL}"
        fi
        log.info "provenance verified for ${pinned}"
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

    # Serialize concurrent deploys to the same environment (E5): two
    # `brik deploy` runs against one env must not interleave their applies.
    brik.use transverse.lock
    if ! transverse.lock.acquire "deploy-${environment}"; then
        [[ -n "$worktree" ]] && transverse.git.worktree_remove "${orig_workspace}" "${worktree}"
        return "${BRIK_EXIT_FAILURE}"
    fi

    # Run the deploy stage (restricted to this env, pinned ref injected).
    set +e
    brik.local.run_deploy
    rc=$?
    set -e

    transverse.lock.release "deploy-${environment}"
    [[ -n "$worktree" ]] && transverse.git.worktree_remove "${orig_workspace}" "${worktree}"
    return "$rc"
}
