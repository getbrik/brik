#!/usr/bin/env bash
# @module cli.status
# @description CLI entrypoint for "brik status" -- the three-layer
#   environment status and drift query.
#
# Reports an environment as three independent layers and never presents any
# single one as "the state":
#   journal -- the last 'deployed' event recorded in the state-repo (intent
#              that was observed live at deploy time);
#   desired -- the definition a deploy would apply NOW, re-derived as a
#              definition_hash at the ref that governs the environment
#              (config_ref when declared, otherwise the recorded version
#              tag commit);
#   live    -- the digest currently running, read back from the target.
#
# Drift verdicts compare the layers: a desired hash that differs from the
# recorded one is DEFINITION drift (a redeploy would change the env); a live
# digest that differs from the recorded one is LIVE drift. On a gitops
# target the reconciler corrects live drift (a mismatch is a transient
# OutOfSync); on a push-based target it is detected but NOT corrected.

# Guard against double-sourcing.
[[ -n "${_BRIK_MODULE_CLI_STATUS_LOADED:-}" ]] && return 0
_BRIK_MODULE_CLI_STATUS_LOADED=1

# cli.status.run - report the three-layer status of <environment>.
# Usage: brik status --environment <e> [--config <path>] [--workspace <path>]
#        [--json]
cli.status.run() {
    brik.use cli.helpers

    local environment="" config_path="" workspace="" json=""
    workspace="$(pwd)"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --environment) brik_require_arg "--environment" "${2-}" || return "$?"
                           environment="$2"; shift 2 ;;
            --config)      brik_require_arg "--config" "${2-}" || return "$?"
                           config_path="$2"; shift 2 ;;
            --workspace)   brik_require_arg "--workspace" "${2-}" || return "$?"
                           workspace="$2"; shift 2 ;;
            --json)        json="true"; shift ;;
            -h|--help)     brik_print_verb_help status; return 0 ;;
            *) brik_usage_error "unknown option: $1" || return "$?" ;;
        esac
    done

    if [[ -z "$environment" ]]; then
        brik_error "'brik status' requires --environment"
        return "${BRIK_EXIT_INVALID_INPUT}"
    fi

    # Containerized local execution: on a bare host the query re-execs inside
    # the deploy-class container, where the target tooling (kubectl, argocd)
    # and the network posture match the CI CD jobs. Inside a CI job or a brik
    # container the verb continues below, in-process.
    if brik_host_local; then
        brik.use cli.local_runner
        export BRIK_PROJECT_DIR="${workspace}"
        [[ -n "$config_path" ]] && export BRIK_CONFIG_FILE="$config_path"
        cli.local_runner.setup_docker_env || return "$?"

        local -a verb_args=(--environment "$environment")
        [[ "$json" == "true" ]] && verb_args+=(--json)
        [[ -n "$config_path" ]] && verb_args+=(--config "$config_path")
        cli.local_runner.runtime brik.local.docker.run_status_container "${verb_args[@]}"
        return "$?"
    fi

    [[ -z "$config_path" ]] && config_path="${workspace}/${BRIK_DEFAULT_CONFIG}"

    cd "${workspace}" || return "${BRIK_EXIT_IO_FAILURE}"
    export BRIK_PROJECT_DIR="${workspace}"
    export BRIK_WORKSPACE="${workspace}"
    export BRIK_CONFIG_FILE="${config_path}"
    export BRIK_LOG_DIR="${BRIK_LOG_DIR:-${workspace}/.brik-logs}"
    mkdir -p "${BRIK_LOG_DIR}"

    # Bring up the local runtime: this loads brik.yml and exports the
    # BRIK_DEPLOY_<ENV>_* variables the read-back layer resolves.
    local wrapper="${BRIK_HOME}/shared-libs/local/scripts/local-wrapper.sh"
    pipeline.require_file "${wrapper}" || return "${BRIK_EXIT_IO_FAILURE}"
    # shellcheck source=/dev/null
    . "${wrapper}"
    local rc
    set +e
    brik.local.setup
    rc=$?
    set -e
    [[ "$rc" -ne 0 ]] && return "$rc"

    # Referential gate (parity with the CD verbs): the journal clone and the
    # live read-back derive their transport posture from it.
    brik.use transverse.infra
    local infra_root
    infra_root="$(infra.root)" || return "$?"
    infra.validate "$infra_root" || return "$?"

    brik.use transverse.env
    local upper_env
    upper_env="$(printf '%s' "$environment" | tr '[:lower:]-' '[:upper:]_')"

    local target
    target="$(transverse.env.resolve_indirect "BRIK_DEPLOY_${upper_env}_TARGET")"
    if [[ -z "$target" ]]; then
        brik_error "unknown deploy environment '${environment}' (no target in brik.yml)"
        return "${BRIK_EXIT_CONFIG_ERROR}"
    fi

    # --- Journal layer: the last deployed event recorded for this env. ----
    brik.use transverse.config
    local ev_repo journal_event="" journal_note=""
    ev_repo="$(config.get '.artifacts.evidence.repo' '' 2>/dev/null || printf '')"
    if [[ -z "$ev_repo" ]]; then
        journal_note="no state-repo declared (.artifacts.evidence.repo)"
    else
        brik.use transverse.state_repo
        local ev_branch ev_token_var ev_sign ev_clone ev_rc=0
        ev_branch="$(config.get '.artifacts.evidence.branch' '' 2>/dev/null || printf '')"
        ev_token_var="$(config.get '.artifacts.evidence.token_var' '' 2>/dev/null || printf '')"
        ev_sign="$(config.get '.artifacts.evidence.sign' 'false' 2>/dev/null || printf 'false')"
        ev_clone="$(mktemp -d)" || return "${BRIK_EXIT_IO_FAILURE}"
        local -a _clone_args=("$ev_repo" "$ev_clone")
        [[ -n "$ev_branch" ]]    && _clone_args+=(--branch "$ev_branch")
        [[ -n "$ev_token_var" ]] && _clone_args+=(--token-var "$ev_token_var")
        if ! transverse.state_repo.clone "${_clone_args[@]}" >/dev/null; then
            rm -rf "$ev_clone"
            brik_error "cannot read the deployment journal at ${ev_repo} -- failing closed"
            return "${BRIK_EXIT_EXTERNAL_FAIL}"
        fi
        # A status that would present a forged journal as truth is worse
        # than no status: signed evidence is verified fail-closed.
        if [[ "$ev_sign" == "true" ]]; then
            if ! transverse.state_repo.verify_head "$ev_clone" >/dev/null; then
                rm -rf "$ev_clone"
                brik_error "the journal tip signature did not verify -- failing closed"
                return "${BRIK_EXIT_EXTERNAL_FAIL}"
            fi
        fi
        brik.use transverse.deployment_journal
        local events
        events="$(deployment_journal.events_for "$ev_clone" \
            --environment "$environment")" || ev_rc=$?
        rm -rf "$ev_clone"
        if [[ "$ev_rc" -ne 0 ]]; then
            brik_error "the deployment journal could not be read fail-closed (rc=${ev_rc})"
            return "$ev_rc"
        fi
        journal_event="$(printf '%s' "$events" | jq 'sort_by(.timestamp) | last // empty')"
        [[ -z "$journal_event" ]] && journal_note="no deployed event recorded for '${environment}'"
    fi

    local j_version="" j_digest="" j_hash="" j_timestamp="" j_version_ref=""
    if [[ -n "$journal_event" ]]; then
        j_version="$(printf '%s' "$journal_event" | jq -r '.version')"
        j_digest="$(printf '%s' "$journal_event" | jq -r '.digest')"
        j_hash="$(printf '%s' "$journal_event" | jq -r '.definition_hash')"
        j_timestamp="$(printf '%s' "$journal_event" | jq -r '.timestamp')"
        j_version_ref="$(printf '%s' "$journal_event" | jq -r '.version_ref // empty')"
    fi

    # --- Desired layer: the definition a deploy would apply NOW, hashed ---
    # at the governing ref (config_ref regime, else the recorded version
    # tag commit, else the current tree).
    local desired_tree="$workspace" desired_ref="worktree" worktree=""
    _cli.status._cleanup() { [[ -n "$worktree" ]] \
        && transverse.git.worktree_remove "$workspace" "$worktree"; return 0; }
    local cfg_ref
    cfg_ref="$(config.get ".deploy.environments.${environment}.config_ref" '' 2>/dev/null || printf '')"
    if git -C "$workspace" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        brik.use transverse.git
        if [[ -n "$cfg_ref" ]]; then
            local _cand
            for _cand in "$cfg_ref" "origin/${cfg_ref}"; do
                if worktree="$(transverse.git.worktree_at "$workspace" "$_cand")"; then
                    break
                fi
                worktree=""
            done
            if [[ -z "$worktree" ]]; then
                brik_error "config_ref: cannot resolve '${cfg_ref}' for environment '${environment}' -- failing closed"
                return "${BRIK_EXIT_CONFIG_ERROR}"
            fi
            desired_tree="$worktree"
            desired_ref="$(git -C "$worktree" rev-parse HEAD)"
        elif [[ -n "$j_version_ref" ]] \
                && git -C "$workspace" rev-parse -q --verify "${j_version_ref}^{commit}" >/dev/null 2>&1; then
            if [[ "$(git -C "$workspace" rev-parse HEAD 2>/dev/null)" != "$j_version_ref" ]]; then
                worktree="$(transverse.git.worktree_at "$workspace" "$j_version_ref")" || worktree=""
                [[ -n "$worktree" ]] && desired_tree="$worktree"
            fi
            desired_ref="$j_version_ref"
        fi
    fi

    # The hash is comparable to the recorded one only when it pins the same
    # artifact: rebuild the pinned ref from the governing tree's channel
    # registry and the recorded digest.
    local desired_hash="" pinned=""
    if [[ -n "$j_digest" ]]; then
        local channel registry
        channel="$(BRIK_CONFIG_FILE="${desired_tree}/${BRIK_DEFAULT_CONFIG}" \
            config.get ".deploy.environments.${environment}.accepts_channel" '' 2>/dev/null || printf '')"
        if [[ -n "$channel" ]]; then
            registry="$(BRIK_CONFIG_FILE="${desired_tree}/${BRIK_DEFAULT_CONFIG}" \
                config.get ".artifacts.channels.${channel}.registry" '' 2>/dev/null || printf '')"
            [[ -n "$registry" ]] && pinned="${registry}@${j_digest}"
        fi
    fi
    brik.use transverse.deployment_journal
    local -a _hash_args=(--workspace "$desired_tree" --environment "$environment")
    [[ -n "$pinned" ]] && _hash_args+=(--pinned "$pinned")
    if ! desired_hash="$(deployment_journal.definition_hash "${_hash_args[@]}")"; then
        _cli.status._cleanup
        brik_error "cannot hash the desired definition of '${environment}'"
        return "${BRIK_EXIT_EXTERNAL_FAIL}"
    fi
    _cli.status._cleanup

    # --- Live layer: what the target actually runs, read back now. -------
    brik.use deployments.readback
    local controller live
    controller="$(transverse.env.resolve_indirect "BRIK_DEPLOY_${upper_env}_CONTROLLER")"
    live="$(deploy.readback.live_digest --env "$environment" \
        --target "$target" --controller "$controller")"

    # --- Drift verdicts. ---------------------------------------------------
    local reconciled="false"
    [[ "$target" == "gitops" ]] && reconciled="true"

    local definition_drift="null" live_drift="null"
    if [[ -n "$j_hash" ]]; then
        definition_drift="false"
        [[ "$desired_hash" != "$j_hash" ]] && definition_drift="true"
    fi
    if [[ -n "$j_digest" && "$live" =~ ^sha256: ]]; then
        live_drift="false"
        [[ "$live" != "$j_digest" ]] && live_drift="true"
    fi

    if [[ "$json" == "true" ]]; then
        # KCOV_EXCL_START -- inline jq document body, not bash code
        jq -n \
            --arg environment "$environment" \
            --arg target "$target" \
            --argjson journal "${journal_event:-null}" \
            --arg journal_note "$journal_note" \
            --arg desired_ref "$desired_ref" \
            --arg desired_hash "$desired_hash" \
            --arg live "$live" \
            --argjson definition_drift "$definition_drift" \
            --argjson live_drift "$live_drift" \
            --argjson reconciled "$reconciled" '
            {
              environment: $environment,
              target: $target,
              journal: (if $journal == null and $journal_note != ""
                        then {note: $journal_note} else $journal end),
              desired: {ref: $desired_ref, definition_hash: $desired_hash},
              live: {digest: $live,
                     queryable: ($live | startswith("sha256:"))},
              drift: {definition: $definition_drift,
                      live: $live_drift,
                      corrected_by_reconciler: $reconciled}
            }'
        # KCOV_EXCL_STOP
        return "${BRIK_EXIT_OK}"
    fi

    brik_print "environment: ${environment} (target: ${target})"
    if [[ -n "$journal_event" ]]; then
        brik_print "journal:     ${j_version} @ ${j_digest} (${j_timestamp})"
    else
        brik_print "journal:     ${journal_note}"
    fi
    brik_print "desired:     ${desired_hash} (at ${desired_ref})"
    if [[ "$live" =~ ^sha256: ]]; then
        brik_print "live:        ${live}"
    else
        brik_print "live:        not queryable for this target (${live}) -- the journal is intent, not the live state"
    fi
    if [[ "$definition_drift" == "true" ]]; then
        brik_print "drift:       DEFINITION drift -- a redeploy would change '${environment}' (recorded ${j_hash})"
    fi
    if [[ "$live_drift" == "true" ]]; then
        if [[ "$reconciled" == "true" ]]; then
            brik_print "drift:       live differs from the journal (OutOfSync) -- corrected by the reconciler"
        else
            brik_print "drift:       LIVE drift detected, NOT corrected -- ${live} differs from the recorded ${j_digest}"
        fi
    fi
    if [[ "$definition_drift" == "false" && "$live_drift" != "true" ]]; then
        brik_print "drift:       none detected"
    fi
    return "${BRIK_EXIT_OK}"
}
