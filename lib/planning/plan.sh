#!/usr/bin/env bash
# @module planning/plan
# @description Stage-selection logic for the Brik planner. Pure compute:
#   reads the registry + changed files, decides run|skip per stage with a
#   short reason code, and emits the result on stdout. Serialization to
#   plan.json is delegated to lib/planning/plan_writer.sh (SRP).

# Guard against double-sourcing.
[[ -n "${_BRIK_PLANNING_PLAN_LOADED:-}" ]] && return 0
_BRIK_PLANNING_PLAN_LOADED=1

# shellcheck source=../registry/registry.sh
. "${BASH_SOURCE[0]%/*}/../registry/registry.sh"
# shellcheck source=impact.sh
. "${BASH_SOURCE[0]%/*}/impact.sh"
# shellcheck source=../transverse/changes.sh
. "${BASH_SOURCE[0]%/*}/../transverse/changes.sh"
# shellcheck source=../transverse/release.sh
. "${BASH_SOURCE[0]%/*}/../transverse/release.sh"
# shellcheck source=../transverse/infra.sh
. "${BASH_SOURCE[0]%/*}/../transverse/infra.sh"

# Echo the canonical stage order (registry topological sort).
plan.stages.ordered() {
    registry.stage.list
}

# Emit DAG edges (after/before resolved into directed edges from parent
# to child) one per line, tab-separated "from\tto". Edges are sorted
# lexicographically to keep plan.json byte-reproducible.
#
# Usage: plan.dag.edges
plan.dag.edges() {
    local stage parent successor
    {
        while IFS= read -r stage; do
            while IFS= read -r parent; do
                [[ -z "$parent" ]] && continue
                printf '%s\t%s\n' "$parent" "$stage"
            done < <(registry.stage.after "$stage" 2>/dev/null)
            while IFS= read -r successor; do
                [[ -z "$successor" ]] && continue
                printf '%s\t%s\n' "$stage" "$successor"
            done < <(registry.stage.before "$stage" 2>/dev/null)
        done < <(registry.stage.list)
    } | LC_ALL=C sort -u
}

# Decide run|skip for a single stage.
# Emits "decision<TAB>reason" on stdout. Side-effect-free.
#
# Args:
#   $1 stage_id
#   $2 mode      (safe|balanced)
#   $3 context   (snapshot|release)
#   $4 with_release  (true|false)
#   $5 with_package  (true|false)
#   $6 with_deploy   (true|false)
#   $7 stack_id      (may be empty)
#   $8 changes_file  (NUL-separated changed paths; may be empty when source=none)
#
# Reason codes:
#   context-mismatch     gate.contexts does not include the active context
#   opt-in-flag-missing  gate.mode=opt_in, required flag not provided
#   no-impact            balanced + globs declared + no changed file matched
#   context-match        safe: gate matched, no impact filter applied
#   impacted             balanced: at least one glob matched
#   no-diff              cold start (changes source=none), conservative run
#   no-impact-declared   stage neither declares changes nor inherits from stack
plan.decide() {
    local stage_id="$1" mode="$2" context="$3"
    local with_release="$4" with_package="$5" with_deploy="$6"
    local stack_id="$7" changes_file="$8"

    local contexts gate_mode flag
    contexts="$(registry.stage.gate_contexts "$stage_id" 2>/dev/null | tr '\n' ' ' | sed -e 's/^ *//' -e 's/ *$//')"
    if [[ -n "$contexts" ]] && ! grep -qw -- "$context" <<<"$contexts"; then
        printf 'skip\tcontext-mismatch\n'
        return 0
    fi

    gate_mode="$(registry.stage.gate_mode "$stage_id" 2>/dev/null || true)"
    if [[ "$gate_mode" == "opt_in" ]]; then
        flag="$(registry.stage.gate_opt_in_flag "$stage_id" 2>/dev/null || true)"
        case "$flag" in
            --with-release) [[ "$with_release" != "true" ]] && { printf 'skip\topt-in-flag-missing\n'; return 0; } ;;
            --with-package) [[ "$with_package" != "true" ]] && { printf 'skip\topt-in-flag-missing\n'; return 0; } ;;
            --with-deploy)  [[ "$with_deploy"  != "true" ]] && { printf 'skip\topt-in-flag-missing\n'; return 0; } ;;
            "")             : ;;
            *)              printf 'skip\topt-in-flag-missing\n'; return 0 ;;
        esac
    fi

    if [[ "$mode" == "safe" ]]; then
        printf 'run\tcontext-match\n'
        return 0
    fi

    if [[ -z "$changes_file" || ! -s "$changes_file" ]]; then
        printf 'run\tno-diff\n'
        return 0
    fi

    local -a patterns=()
    mapfile -t patterns < <(impact.stage_patterns "$stage_id" "$stack_id")
    if [[ ${#patterns[@]} -eq 0 ]]; then
        printf 'run\tno-impact-declared\n'
        return 0
    fi

    if impact.stage_is_impacted "$stage_id" "$stack_id" "$changes_file"; then
        printf 'run\timpacted\n'
    else
        printf 'skip\tno-impact\n'
    fi
}

# End-to-end planning.
# Reads:
#   --workspace <dir>      optional, default $BRIK_WORKSPACE or PWD
#   --mode <m>             safe|balanced|aggressive (aggressive => error)
#   --with-release|--with-package|--with-deploy as opt-in flags
# Emits on stdout: header lines starting with "#" (workspace, mode,
# context, stack, changes source/from/to) followed by one TAB-separated
# record per stage in topological order:
#   <id>\t<decision>\t<reason>\t<gate_mode>\t<runner_class>\t<function>\t<matched_globs_comma>
# Plan_writer.sh consumes this stream to produce plan.json.
plan.compute() {
    local workspace="${BRIK_WORKSPACE:-$PWD}"
    local mode="safe"
    local with_release=false with_package=false with_deploy=false
    local plan_type="ci" deploy_version="" deploy_environment=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --workspace) workspace="$2"; shift 2 ;;
            --mode)      mode="$2"; shift 2 ;;
            --type)      plan_type="$2"; shift 2 ;;
            --version)   deploy_version="$2"; shift 2 ;;
            --environment) deploy_environment="$2"; shift 2 ;;
            --with-release) with_release=true; shift ;;
            --with-package) with_package=true; shift ;;
            --with-deploy)  with_deploy=true; shift ;;
            *) printf '[plan] unknown argument: %s\n' "$1" >&2
               return "$BRIK_EXIT_INVALID_INPUT" ;;
        esac
    done

    case "$plan_type" in
        ci|deploy) : ;;
        *) printf '[plan] invalid --type: %s (expected ci|deploy)\n' "$plan_type" >&2
           return "$BRIK_EXIT_INVALID_INPUT" ;;
    esac

    # The deploy plan-kind is a subset of the fixed flow: only these stages
    # run; every CI stage is force-skipped. promote self-skips at runtime
    # when not configured. Padded with spaces for whole-word matching.
    local _deploy_subset=" promote deploy notify "
    if [[ "$plan_type" == "deploy" ]]; then
        # A deploy run is explicit (mode 2): the deploy stage must run, so the
        # --with-deploy opt-in is implied rather than required at the UI.
        with_deploy=true
    fi

    case "$mode" in
        safe|balanced) : ;;
        aggressive)
            printf '[brik] error: pipeline.selection.mode=aggressive is not implemented in this\n' >&2
            printf 'version. Use mode=balanced for per-file impact, or mode=safe for context-only\n' >&2
            printf 'selection. The aggressive mode (per-subproject impact graph) is scheduled for\n' >&2
            printf 'v0.7+. Track at docs/chantiers/20260518_refonte/analysis/monorepo-plan.md\n' >&2
            return "$BRIK_EXIT_INVALID_INPUT"
            ;;
        *)  printf '[plan] invalid mode: %s (expected safe|balanced|aggressive)\n' "$mode" >&2
            return "$BRIK_EXIT_INVALID_INPUT" ;;
    esac

    # CI context comes from the commit tag. A deploy run is parameterized by
    # an explicit --version, so it resolves to the release context whenever a
    # version is supplied (the artifact being deployed is a released one).
    local context="snapshot"
    if [[ "$plan_type" == "deploy" ]]; then
        [[ -n "$deploy_version" ]] && context="release"
    else
        [[ -n "${BRIK_COMMIT_TAG:-}" ]] && context="release"
    fi

    # The infrastructure referential is mandatory: the plan pins the
    # environment declaration it was derived against, so an unconfigured
    # referential fails the derivation closed instead of producing a plan
    # that silently ignores the platform's declared endpoints.
    local _infra_root _infra_fingerprint
    _infra_root="$(infra.root)" || return "$?"
    _infra_fingerprint="$(infra.fingerprint "$_infra_root")" || return "$?"

    local stack_id=""
    stack_id="$(registry.stack.detect "$workspace" 2>/dev/null || true)"

    local changes_file
    changes_file="$(mktemp -t brik-plan-changes.XXXXXX)"
    changes.diff "$workspace" >"$changes_file" 2>/dev/null || true
    local source="${BRIK_CHANGES_SOURCE:-none}"
    local from="" to=""
    if [[ "$source" != "none" ]]; then
        local meta; meta="$(changes.metadata "$workspace")"
        IFS=$'\t' read -r _ from to <<<"$meta"
    fi

    # Release state. The same compute that stages.init uses
    # for the dotenv; emitted here so plan_writer can stamp them into the
    # plan.json release block. BRIK_CONFIG_FILE may be unset when the
    # planner runs outside of a workspace (e.g. `brik plan --workspace`
    # against a bare repo); release.compute_* degrade to safe defaults
    # ("none", "0.0.0", "0") in that case.
    local _release_profile _release_version _is_candidate
    BRIK_CONFIG_FILE="${BRIK_CONFIG_FILE:-$workspace/brik.yml}" \
        _release_profile="$(release.compute_profile)"
    BRIK_CONFIG_FILE="${BRIK_CONFIG_FILE:-$workspace/brik.yml}" \
    BRIK_WORKSPACE="$workspace" \
        _release_version="$(release.compute_version)"
    _is_candidate="$(release.compute_is_candidate)"

    printf '# workspace=%s\n' "$workspace"
    printf '# mode=%s\n' "$mode"
    printf '# context=%s\n' "$context"
    printf '# stack=%s\n' "${stack_id:-}"
    printf '# changes_source=%s\n' "$source"
    printf '# changes_from=%s\n' "$from"
    printf '# changes_to=%s\n' "$to"
    # Emit one `# changes_file=<path>` per modified file so plan_writer
    # can stamp changes.files into plan.json. The diff is NUL-separated
    # for safety; we convert to line-oriented streaming here. Brik
    # workspaces are source repositories where path newlines do not
    # occur in practice, so tr '\0' '\n' is sufficient.
    if [[ -s "$changes_file" ]]; then
        while IFS= read -r _changes_file_path; do
            [[ -z "$_changes_file_path" ]] && continue
            printf '# changes_file=%s\n' "$_changes_file_path"
        done < <(tr '\0' '\n' < "$changes_file")
    fi
    printf '# release_profile=%s\n' "$_release_profile"
    printf '# release_version=%s\n' "$_release_version"
    printf '# is_candidate=%s\n' "$_is_candidate"
    printf '# infra_fingerprint=%s\n' "$_infra_fingerprint"
    # plan_type is always emitted; the writer only surfaces planType/deploy in
    # plan.json when it is "deploy", so ci plans stay byte-identical.
    printf '# plan_type=%s\n' "$plan_type"
    printf '# deploy_version=%s\n' "$deploy_version"
    printf '# deploy_environment=%s\n' "$deploy_environment"

    local stage decision reason gate_mode runner_class fn matched
    while IFS= read -r stage; do
        local result
        if [[ "$plan_type" == "deploy" && "$_deploy_subset" != *" $stage "* ]]; then
            # CI stage in a deploy plan: force skip so `brik plan gate <ci>`
            # returns skip (an absent stage would default to run).
            result=$'skip\tnot-in-deploy-plan'
        else
            result="$(plan.decide \
                "$stage" "$mode" "$context" \
                "$with_release" "$with_package" "$with_deploy" \
                "$stack_id" "$changes_file")"
        fi
        IFS=$'\t' read -r decision reason <<<"$result"

        gate_mode="$(registry.stage.gate_mode "$stage" 2>/dev/null || true)"
        runner_class="$(registry.stage.runner_class "$stage" 2>/dev/null || true)"
        fn="$(registry.stage.function "$stage" 2>/dev/null || true)"

        matched=""
        if [[ "$mode" == "balanced" && "$decision" == "run" && "$reason" == "impacted" ]]; then
            matched="$(impact.stage_matched_globs "$stage" "$stack_id" "$changes_file" \
                       | paste -sd, -)"
        fi

        printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
            "$stage" "$decision" "$reason" "$gate_mode" "$runner_class" "$fn" "$matched"
    done < <(plan.stages.ordered)

    rm -f "$changes_file"
}
