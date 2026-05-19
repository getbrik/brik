#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# @module pipeline
# @description Main pipeline orchestrator for the Brik fixed flow.
#
# pipeline.run iterates the fixed stage order
#   init -> release -> build -> lint -> sast -> scan -> test
#        -> package -> container-scan -> deploy -> notify
# and dispatches each stage through stage.dispatch (lib/pipeline/stage.sh).
# Reports per-stage status, exit_code, and duration to the pipeline report
# (lib/pipeline/report.sh). Opt-in flags gate release / package+container-scan
# / deploy+notify. Fail-fast by default, --continue-on-error overrides.

# Guard against double-sourcing
[[ -n "${_BRIK_PIPELINE_LOADED:-}" ]] && return 0
_BRIK_PIPELINE_LOADED=1

# Source dependencies
# shellcheck source=logging.sh
[[ -z "${_BRIK_LOGGING_LOADED:-}" ]] && . "${BASH_SOURCE[0]%/*}/logging.sh"
# shellcheck source=error.sh
[[ -z "${_BRIK_ERROR_LOADED:-}" ]] && . "${BASH_SOURCE[0]%/*}/error.sh"
# shellcheck source=stage.sh
[[ -z "${_BRIK_STAGE_LOADED:-}" ]] && . "${BASH_SOURCE[0]%/*}/stage.sh"
# shellcheck source=report.sh
[[ -z "${_BRIK_REPORT_LOADED:-}" ]] && . "${BASH_SOURCE[0]%/*}/report.sh"
# shellcheck source=../registry/registry.sh
[[ -z "${_BRIK_REGISTRY_LOADED:-}" ]] && . "${BASH_SOURCE[0]%/*}/../registry/registry.sh"
# shellcheck source=../planning/plan_reader.sh
[[ -z "${_BRIK_PLANNING_PLAN_READER_LOADED:-}" ]] && . "${BASH_SOURCE[0]%/*}/../planning/plan_reader.sh"

# Resolve the pipeline context from BRIK_COMMIT_TAG.
# Empty/unset tag => "snapshot"; any non-empty tag => "release".
# Pre-release tags (v1.2.3-rc1) are treated as release; refining this
# is intentionally out of scope (no regex parsing).
_pipeline._resolve_context() {
    if [[ -n "${BRIK_COMMIT_TAG:-}" ]]; then
        printf '%s' "release"
    else
        printf '%s' "snapshot"
    fi
}

# Resolve continue_on_error policy.
# Precedence (highest first):
#   1. BRIK_CONTINUE_ON_ERROR=0|1 (explicit operator override)
#   2. CLI --continue-on-error flag (legacy back-compat, equivalent to "1")
#   3. Context default: snapshot => true, release => false
# Usage: _pipeline._resolve_continue_on_error <context> <cli_flag>
_pipeline._resolve_continue_on_error() {
    local context="$1"
    local cli_flag="${2:-false}"

    if [[ -n "${BRIK_CONTINUE_ON_ERROR:-}" ]]; then
        case "$BRIK_CONTINUE_ON_ERROR" in
            1|true|yes) printf '%s' "true";  return 0 ;;
            0|false|no) printf '%s' "false"; return 0 ;;
        esac
    fi

    if [[ "$cli_flag" == "true" ]]; then
        printf '%s' "true"
        return 0
    fi

    if [[ "$context" == "release" ]]; then
        printf '%s' "false"
    else
        printf '%s' "true"
    fi
}

# Compute summary.business + pipeline.business.status on the local
# backend. Reads each stage's business.status (defaulting to "success"
# when absent), counts buckets, picks the worst (error > warning >
# success), and writes both into the backend.
_pipeline._compute_business_summary() {
    local backend
    backend="$(_report._backend_path)"
    [[ -f "$backend" ]] || return 0
    command -v jq >/dev/null 2>&1 || return 0

    local tmp
    tmp="$(mktemp "${backend}.XXXXXX")" || return 0
    if jq '
            ( .stages // [] | map(.business.status // "success") ) as $bs
            | { success_count: ($bs | map(select(. == "success")) | length),
                warning_count: ($bs | map(select(. == "warning")) | length),
                error_count:   ($bs | map(select(. == "error"))   | length) } as $summary
            | ( if   ($summary.error_count   // 0) > 0 then "error"
                elif ($summary.warning_count // 0) > 0 then "warning"
                else "success" end ) as $worst
            | .summary  = ((.summary // {}) + { business: $summary })
            | .pipeline = ((.pipeline // {}) + { business: { status: $worst } })
        ' "$backend" > "$tmp" 2>/dev/null; then
        mv "$tmp" "$backend" || rm -f "$tmp"
    else
        rm -f "$tmp"
    fi
}

# Stamp pipeline.context onto the local backend so consumers (HTML/MD
# renderers, CI aggregators) can read the resolved context the same way
# regardless of execution mode. The flat pipeline_id field is left intact
# for back-compat.
_pipeline._stamp_context() {
    local context="$1"
    local backend
    backend="$(_report._backend_path)"
    [[ -f "$backend" ]] || return 0
    command -v jq >/dev/null 2>&1 || return 0

    local tmp
    tmp="$(mktemp "${backend}.XXXXXX")" || return 0
    if jq --arg ctx "$context" \
            '. + { pipeline: ((.pipeline // {}) + { context: $ctx }) }' \
            "$backend" > "$tmp" 2>/dev/null; then
        mv "$tmp" "$backend" || rm -f "$tmp"
    else
        rm -f "$tmp"
    fi
}

# Stamp pipeline.tech.dry_run=true onto the local backend when the run was
# launched with BRIK_DRY_RUN=true. This is the pipeline-level marker that
# the MD/HTML renderers use to print a top-of-report DRY-RUN banner so the
# operator cannot miss that destructive actions were skipped. No-op when
# BRIK_DRY_RUN is unset/false, which keeps the field absent (rather than
# present-and-false) on regular runs.
_pipeline._stamp_dry_run() {
    [[ "${BRIK_DRY_RUN:-}" == "true" ]] || return 0
    local backend
    backend="$(_report._backend_path)"
    [[ -f "$backend" ]] || return 0
    command -v jq >/dev/null 2>&1 || return 0

    local tmp
    tmp="$(mktemp "${backend}.XXXXXX")" || return 0
    if jq '. + { pipeline: ((.pipeline // {})
                            + { tech: ((.pipeline.tech // {})
                                        + { dry_run: true }) }) }' \
            "$backend" > "$tmp" 2>/dev/null; then
        mv "$tmp" "$backend" || rm -f "$tmp"
    else
        rm -f "$tmp"
    fi
}

# Decide whether a stage should be skipped based on opt-in flags.
# Returns 0 (true) if the stage should be skipped, 1 otherwise.
#
# The gate.mode + gate.opt_in_flag mapping comes from the registry stage
# manifest (D.3 of the architecture refactor chantier). Blocking stages
# always run; opt_in stages skip unless the CLI flag named in
# spec.gate.opt_in_flag was provided. The mapping from a flag string
# (e.g. "--with-release") to the local boolean stays a CLI-input concern.
#
# Usage: _pipeline._should_skip <stage> <with_release> <with_package> <with_deploy>
_pipeline._should_skip() {
    local stage="$1"
    local with_release="$2"
    local with_package="$3"
    local with_deploy="$4"

    local mode=""
    if declare -f registry.stage.gate_mode >/dev/null 2>&1; then
        mode="$(registry.stage.gate_mode "$stage" 2>/dev/null || true)"
    fi
    [[ "$mode" == "opt_in" ]] || return 1

    local flag=""
    if declare -f registry.stage.gate_opt_in_flag >/dev/null 2>&1; then
        flag="$(registry.stage.gate_opt_in_flag "$stage" 2>/dev/null || true)"
    fi
    case "$flag" in
        --with-release) [[ "$with_release" != "true" ]] && return 0 ;;
        --with-package) [[ "$with_package" != "true" ]] && return 0 ;;
        --with-deploy)  [[ "$with_deploy"  != "true" ]] && return 0 ;;
        "")             return 1 ;;
        *)              [[ "${!flag:-}"    != "true" ]] && return 0 ;;
    esac
    return 1
}

# Run the full fixed-flow pipeline.
# Precondition: wrapper setup has exported BRIK_HOME, BRIK_WORKSPACE,
# BRIK_CONFIG_FILE, BRIK_LOG_DIR. Called from a wrapper (brik.local,
# brik.gitlab, brik.jenkins) or directly after manual setup.
#
# Usage: pipeline.run [--continue-on-error] [--with-release]
#                    [--with-package] [--with-deploy]
# Returns: 0 when every executed stage passed,
#          BRIK_EXIT_FAILURE when at least one executed stage failed,
#          BRIK_EXIT_INVALID_INPUT on unknown flag.
pipeline.run() {
    local cli_continue_on_error=false
    local with_release=false
    local with_package=false
    local with_deploy=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --continue-on-error) cli_continue_on_error=true; shift ;;
            --with-release)      with_release=true; shift ;;
            --with-package)      with_package=true; shift ;;
            --with-deploy)       with_deploy=true; shift ;;
            *)
                error.raise "$BRIK_EXIT_INVALID_INPUT" "pipeline.run: unknown flag '$1'"
                return "$?"
                ;;
        esac
    done

    if $with_deploy; then
        log.warn "deploy stage enabled - review target environment before running"
    fi

    if [[ "${BRIK_DRY_RUN:-}" == "true" ]]; then
        log.warn "============================================================"
        log.warn "DRY-RUN MODE: BRIK_DRY_RUN=true"
        log.warn "Destructive actions will be skipped:"
        log.warn "  - release: no tag will be pushed"
        log.warn "  - package: no registry publish"
        log.warn "  - deploy: no compose up / k8s apply / helm upgrade / argocd sync / rsync"
        log.warn "  - notify: webhooks suppressed when honoured by the channel"
        log.warn "============================================================"
    fi

    local pipeline_context
    pipeline_context="$(_pipeline._resolve_context)"
    local continue_on_error_str
    continue_on_error_str="$(_pipeline._resolve_continue_on_error \
        "$pipeline_context" "$cli_continue_on_error")"
    local continue_on_error
    if [[ "$continue_on_error_str" == "true" ]]; then
        continue_on_error=true
    else
        continue_on_error=false
    fi
    log.info "pipeline context: ${pipeline_context} (continue_on_error=${continue_on_error_str})"

    report.init || return "$?"
    _pipeline._stamp_context "$pipeline_context"
    _pipeline._stamp_dry_run

    # Local mode treats per-stage fragments as a CI-only mechanism: pipeline.run
    # produces the canonical aggregate-report.{md,json} directly via report.render
    # below. Emitting fragments here would populate ${BRIK_WORKSPACE}/brik-artifacts/
    # and trigger _notify._is_ci_aggregation_mode in stages.notify, which would
    # overwrite the canonical report with an aggregate that lacks pipeline.id /
    # url / commit metadata. Disable fragment emission for the duration of this
    # function. The :- default lets an explicit caller override stay in effect
    # (set BRIK_DISABLE_REPORT_FRAGMENTS=0 to opt back in for debugging).
    export BRIK_DISABLE_REPORT_FRAGMENTS="${BRIK_DISABLE_REPORT_FRAGMENTS:-1}"

    # Stage sequence comes from the registry. It is the source of truth for
    # stage order: ids are topologically sorted by spec.placement.{slot, after,
    # before} at compile time. Adding a builtin stage means publishing a
    # manifest, no change here. If the registry is absent or empty, fail
    # fast: a stale snapshot of the stage list embedded in this file would
    # silently drift from the manifests and bypass extension stages.
    if ! declare -f registry.stage.list >/dev/null 2>&1; then
        log.error "pipeline.run: registry.stage.list is not loaded"
        return "$BRIK_EXIT_CONFIG_ERROR"
    fi
    local -a stages=()
    mapfile -t stages < <(registry.stage.list 2>/dev/null || true)
    if [[ ${#stages[@]} -eq 0 ]]; then
        log.error "pipeline.run: registry.stage.list returned no stages"
        return "$BRIK_EXIT_CONFIG_ERROR"
    fi
    local had_failure=false
    local stage stage_start_ms stage_end_ms duration_ms rc

    for stage in "${stages[@]}"; do
        # Plan-driven gatekeeper (D.4 of the architecture refactor chantier).
        # When a plan.json exists and pipeline.plan.should_run returns false,
        # the stage is recorded as a not-applicable skip BEFORE we touch
        # stage.dispatch. The dispatcher stays a pure name->function mapper
        # (SRP); the orchestrator owns the run/skip decision. No-op when no
        # plan file is present (backward-compat with v0.5.x).
        if declare -f pipeline.plan.should_run >/dev/null 2>&1 \
           && ! pipeline.plan.should_run "$stage"; then
            local _plan_reason=""
            _plan_reason="$(pipeline.plan.reason "$stage" 2>/dev/null || true)"
            report.record "$stage" "tech" "status" "skipped" || true
            report.record "$stage" "tech" "kind" "not-applicable" || true
            [[ -n "$_plan_reason" ]] && \
                report.record "$stage" "business" "reason" "$_plan_reason" || true
            continue
        fi

        if _pipeline._should_skip "$stage" "$with_release" "$with_package" "$with_deploy"; then
            report.record "$stage" "tech" "status" "skipped" || true
            continue
        fi
        if $had_failure && ! $continue_on_error; then
            report.record "$stage" "tech" "status" "skipped" || true
            continue
        fi

        stage_start_ms="$(_helpers.epoch_ms)"
        stage.dispatch "$stage"
        rc=$?
        stage_end_ms="$(_helpers.epoch_ms)"
        duration_ms=$(( stage_end_ms - stage_start_ms ))

        report.record "$stage" "tech" "duration_ms" "$duration_ms" || true
        report.record "$stage" "tech" "exit_code" "$rc" || true

        # Respect a status the stage set itself (e.g. config-skip where the
        # stage records status=skipped before returning 0). Only deduce
        # status from rc when the stage did not already record one.
        if ! report.has_status "$stage"; then
            if [[ $rc -eq 0 ]]; then
                report.record "$stage" "tech" "status" "success" || true
            else
                report.record "$stage" "tech" "status" "failed" || true
            fi
        fi

        if [[ $rc -ne 0 ]]; then
            had_failure=true
        fi
    done

    _pipeline._compute_business_summary

    report.render || true

    # Archive the report into a workspace-relative dir so GitLab/Jenkins can
    # pick it up as a build artifact (declared in shared-libs templates).
    # Runs unconditionally (notify stage is opt-in, we cannot rely on it).
    _pipeline._archive_report || true

    # Gatekeeper: the pipeline return code reflects the business outcome
    # rather than the raw tech outcome. Snapshot context with a failing
    # stage maps to business=warning => rc=0; release context with a
    # failing stage maps to business=error => BRIK_EXIT_FAILURE.
    local _backend _worst="success"
    _backend="$(_report._backend_path)"
    if [[ -f "$_backend" ]] && command -v jq >/dev/null 2>&1; then
        local _bs
        _bs="$(jq -r '.pipeline.business.status // empty' "$_backend" 2>/dev/null)"
        case "$_bs" in
            success|warning|error) _worst="$_bs" ;;
        esac
    fi
    if [[ "$_worst" == "error" ]]; then
        return "$BRIK_EXIT_FAILURE"
    fi
    return 0
}

# Copy aggregate-report.{md,json} to a workspace-relative directory so CI
# systems (GitLab via CI_PROJECT_DIR, Jenkins via WORKSPACE) can archive it.
# No-op when no workspace root resolves (standalone local run outside CI).
_pipeline._archive_report() {
    local _log_dir
    _log_dir="$(_brik.log_dir._resolve)"
    local _report_md="${_log_dir}/aggregate-report.md"
    local _report_json="${_log_dir}/aggregate-report.json"

    local _artifacts_root="${CI_PROJECT_DIR:-${WORKSPACE:-${BRIK_WORKSPACE:-}}}"
    [[ -n "$_artifacts_root" && -d "$_artifacts_root" ]] || return 0

    local _artifacts_dir="${_artifacts_root}/brik-artifacts"
    mkdir -p "$_artifacts_dir" 2>/dev/null || return 0

    [[ -f "$_report_md" ]] && cp "$_report_md" "$_artifacts_dir/" 2>/dev/null || true
    [[ -f "$_report_json" ]] && cp "$_report_json" "$_artifacts_dir/" 2>/dev/null || true

    if [[ -f "${_artifacts_dir}/aggregate-report.md" ]]; then
        log.info "pipeline report archived: ${_artifacts_dir}/aggregate-report.{md,json}"
    fi
}
