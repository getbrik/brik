#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# @module stage
# @description Stage lifecycle orchestrator for the Brik runtime.
#
# stage.run is the central entry point for every stage in the fixed flow.
# It manages context, logging, hooks, execution, summary, and cleanup.
#
# stage.run MUST NOT:
#   - contain business logic
#   - call exit
#   - depend on set -e

# Guard against double-sourcing
[[ -n "${_BRIK_STAGE_LOADED:-}" ]] && return 0
_BRIK_STAGE_LOADED=1

# Source all runtime modules
_stage._load_runtime() {
    local runtime_dir="${BASH_SOURCE[0]%/*}"
    # shellcheck source=version-info.sh
    [[ -z "${_BRIK_VERSION_INFO_LOADED:-}" ]] && . "${runtime_dir}/version-info.sh"
    # shellcheck source=logging.sh
    [[ -z "${_BRIK_LOGGING_LOADED:-}" ]] && . "${runtime_dir}/logging.sh"
    # shellcheck source=error.sh
    [[ -z "${_BRIK_ERROR_LOADED:-}" ]] && . "${runtime_dir}/error.sh"
    # shellcheck source=tools.sh
    [[ -z "${_BRIK_TOOLS_LOADED:-}" ]] && . "${runtime_dir}/tools.sh"
    # shellcheck source=context.sh
    [[ -z "${_BRIK_CONTEXT_LOADED:-}" ]] && . "${runtime_dir}/context.sh"
    # shellcheck source=hooks.sh
    [[ -z "${_BRIK_HOOKS_LOADED:-}" ]] && . "${runtime_dir}/hooks.sh"
    # shellcheck source=summary.sh
    [[ -z "${_BRIK_SUMMARY_LOADED:-}" ]] && . "${runtime_dir}/summary.sh"
    # shellcheck source=bootstrap.sh
    [[ -z "${_BRIK_BOOTSTRAP_LOADED:-}" ]] && . "${runtime_dir}/bootstrap.sh"
    # shellcheck source=pipeline-env.sh
    [[ -z "${_BRIK_PIPELINE_ENV_LOADED:-}" ]] && . "${runtime_dir}/pipeline-env.sh"
    # shellcheck source=banner.sh
    [[ -z "${_BRIK_BANNER_LOADED:-}" ]] && . "${runtime_dir}/banner.sh"
    # shellcheck source=report.sh
    [[ -z "${_BRIK_REPORT_LOADED:-}" ]] && . "${runtime_dir}/report.sh"
}

_stage._load_runtime

# Print the current Unix time in milliseconds as a 13-digit integer.
# Uses bash 5+ EPOCHREALTIME (fork-free) when available; falls back to
# date +%s * 1000 (second precision, last resort) otherwise. bin/brik
# enforces bash 5+ so the fallback should be unreachable in practice.
_helpers.epoch_ms() {
    # EPOCHREALTIME format: "<seconds>.<microseconds>" (always 6 frac digits
    # on bash 5+). Concatenate seconds with the first 3 fraction digits
    # as plain text to avoid arithmetic interpretation of leading zeros
    # (e.g. "012" being read as octal by printf %d). The dot check guards
    # against an externally-set EPOCHREALTIME without the expected shape.
    if [[ "${EPOCHREALTIME:-}" == *.* ]]; then
        local s="${EPOCHREALTIME%.*}"
        local f="${EPOCHREALTIME#*.}000"
        printf '%s%s\n' "$s" "${f:0:3}"
    else
        printf '%s000\n' "$(date +%s)"
    fi
}

# Export the named variable to the first non-empty candidate iff the
# variable is currently unset or empty. Leaves the variable untouched
# (still unset) when no candidate matches, so consumers can distinguish
# absent-from-environment ("omit field") from empty-string.
# Usage: _helpers.set_if_unset <var_name> <candidate1> [<candidate2>...]
_helpers.set_if_unset() {
    local var="$1"; shift
    [[ -n "${!var:-}" ]] && return 0
    local cand
    for cand in "$@"; do
        if [[ -n "$cand" ]]; then
            export "$var=$cand"
            return 0
        fi
    done
    return 0
}

# Detect CI metadata from the runtime environment and export normalized
# BRIK_PIPELINE_*/BRIK_COMMIT_*/BRIK_TRIGGERED_BY variables. Pre-set BRIK_*
# wins, so wrappers can override before detection runs.
#
# Sources by platform:
#   GitLab : CI_PIPELINE_ID, CI_PIPELINE_URL, CI_COMMIT_SHA,
#            CI_COMMIT_SHORT_SHA, CI_COMMIT_REF_NAME, CI_COMMIT_BRANCH,
#            CI_COMMIT_TAG, GITLAB_USER_LOGIN, CI_PIPELINE_SOURCE
#   Jenkins: BUILD_TAG, BUILD_NUMBER, BUILD_URL, GIT_COMMIT,
#            GIT_BRANCH (origin/-stripped), GIT_TAG, BUILD_USER_ID,
#            BUILD_CAUSE
#
# Lives in stage.sh (rather than pipeline.sh) so stage.dispatch can call
# it on every stage entry, covering both pipeline.run (multi-stage) and
# the CI single-job path.
_pipeline.detect_metadata() {
    # TODO: extend with BRIK_PROJECT_NAME from CI_PROJECT_NAME (GitLab) /
    # JOB_NAME (Jenkins). Currently sourced from .project.name in brik.yml
    # only (lib/transverse/config.sh). Tracked under chantier
    # 20260502_pipeline-report-followups Phase B.3 audit.
    _helpers.set_if_unset BRIK_PIPELINE_ID    "${CI_PIPELINE_ID:-}"   "${BUILD_TAG:-}"  "${BUILD_NUMBER:-}"
    _helpers.set_if_unset BRIK_PIPELINE_URL   "${CI_PIPELINE_URL:-}"  "${BUILD_URL:-}"
    _helpers.set_if_unset BRIK_COMMIT_SHA     "${CI_COMMIT_SHA:-}"    "${GIT_COMMIT:-}"

    # short_sha derives from BRIK_COMMIT_SHA when no native short var is set.
    # The set_if_unset call above runs export in the current shell, so
    # BRIK_COMMIT_SHA is already populated here when CI_COMMIT_SHA or
    # GIT_COMMIT was non-empty. Do not reorder these blocks without
    # preserving that read-after-export contract.
    local _short_fallback=""
    [[ -n "${BRIK_COMMIT_SHA:-}" ]] && _short_fallback="${BRIK_COMMIT_SHA:0:8}"
    _helpers.set_if_unset BRIK_COMMIT_SHORT_SHA "${CI_COMMIT_SHORT_SHA:-}" "$_short_fallback"

    _helpers.set_if_unset BRIK_COMMIT_REF     "${CI_COMMIT_REF_NAME:-}"

    # Jenkins GIT_BRANCH commonly carries an "origin/" prefix; strip it for
    # consistency with the GitLab CI_COMMIT_BRANCH form.
    local _branch="${CI_COMMIT_BRANCH:-${GIT_BRANCH:-}}"
    _branch="${_branch#origin/}"
    _helpers.set_if_unset BRIK_COMMIT_BRANCH  "$_branch"

    _helpers.set_if_unset BRIK_COMMIT_TAG     "${CI_COMMIT_TAG:-}"    "${GIT_TAG:-}"   "${BRIK_TAG:-}"
    _helpers.set_if_unset BRIK_TRIGGERED_BY   "${GITLAB_USER_LOGIN:-}" "${BUILD_USER_ID:-}" "${CI_PIPELINE_SOURCE:-}" "${BUILD_CAUSE:-}"

    return 0
}

# Create a log file for a stage. Prints the path on stdout.
stage.create_log_file() {
    local stage_name="$1"
    local log_dir="${BRIK_LOG_DIR:-${BRIK_DEFAULT_LOG_DIR:-/tmp/brik/logs}}"
    mkdir -p "$log_dir" || {
        log.error "cannot create log directory: $log_dir"
        return "$BRIK_EXIT_IO_FAILURE"
    }
    local log_file
    log_file="$(mktemp "${log_dir}/${stage_name}-XXXXXX")" || {
        log.error "cannot create log file for stage: $stage_name"
        return "$BRIK_EXIT_IO_FAILURE"
    }
    mv "$log_file" "${log_file}.log" && log_file="${log_file}.log"
    printf '%s' "$log_file"
    return 0
}

# Execute a command while capturing all output to a log file.
# Preserves the command's exit status via PIPESTATUS.
stage.with_logging() {
    local log_file="$1"
    shift
    "$@" 2>&1 | tee -a "$log_file"
    return "${PIPESTATUS[0]}"
}

# Execute the stage logic function with proper scope.
stage.execute() {
    local stage_name="$1"
    local logic_function="$2"
    local context_file="$3"
    shift 3

    local previous_scope="${BRIK_LOG_SCOPE:-}"
    export BRIK_LOG_SCOPE="$stage_name"

    if ! declare -f "$logic_function" >/dev/null 2>&1; then
        log.error "logic function not defined: $logic_function"
        export BRIK_LOG_SCOPE="$previous_scope"
        return "$BRIK_EXIT_INVALID_INPUT"
    fi

    local result=0
    "$logic_function" "$context_file" "$@" || result=$?

    export BRIK_LOG_SCOPE="$previous_scope"
    return "$result"
}

# Cleanup after stage execution.
stage.cleanup() {
    local context_file="$1"
    local log_file="$2"
    # best-effort: cleanup hook must not abort the stage
    hook.on_cleanup "${BRIK_LOG_SCOPE:-brik}" "$context_file" "$log_file" || true
    log.debug "stage cleanup complete"
    return 0
}

# Skip the current stage with a user-visible warning. Used when a stage
# is desactivable by config and the user has chosen to disable it
# outside a release context. Records tech.status=skipped, tech.warning=true,
# tech.warning_reason on the report backend so report.aggregate_fragments
# can surface the entry under summary.warnings. Returns
# BRIK_EXIT_SKIP_WITH_WARNING (99) so the platform wrapper can map it to
# allow_failure (GitLab) or unstable() (Jenkins).
#
# Usage: stage.skip_with_warning <stage_name> <reason>
stage.skip_with_warning() {
    if [[ $# -ne 2 ]]; then
        error.raise "$BRIK_EXIT_INVALID_INPUT" \
            "stage.skip_with_warning expects 2 arguments: stage reason (got $#)"
        return "$?"
    fi
    local stage_name="$1"
    local reason="$2"
    if [[ -z "$stage_name" || -z "$reason" ]]; then
        error.raise "$BRIK_EXIT_INVALID_INPUT" \
            "stage.skip_with_warning: stage and reason must not be empty"
        return "$?"
    fi

    log.warn "stage '${stage_name}' skipped with warning: ${reason}"
    report.record "$stage_name" "tech" "status"         "skipped" 2>/dev/null || true
    report.record "$stage_name" "tech" "warning"        "true"    2>/dev/null || true
    report.record "$stage_name" "tech" "warning_reason" "$reason" 2>/dev/null || true

    return "$BRIK_EXIT_SKIP_WITH_WARNING"
}

# Record the stage's terminal tech.* fields into the pipeline-report backend
# and emit the per-stage fragment for CI artifact aggregation. Idempotent
# when called repeatedly (report.record upserts).
#
# Behavior:
#   - No-op when the backend pipeline-report.json is absent (legacy callers
#     that bypass pipeline.run / stage.dispatch).
#   - Records tech.duration_ms, tech.exit_code, and tech.status (when not
#     already set by the stage itself, e.g. config-skip pattern).
#   - Calls report.write_fragment unless BRIK_DISABLE_REPORT_FRAGMENTS=1.
#   - Fragment write failures are non-fatal (log.warn) and never override
#     the stage exit code.
#
# Usage: _stage._finalize_fragment <stage_name> <exit_code> <stage_start_ms>
_stage._finalize_fragment() {
    local stage_name="$1"
    local exit_code="$2"
    local stage_start_ms="$3"

    local log_dir="${BRIK_LOG_DIR:-${BRIK_DEFAULT_LOG_DIR:-/tmp/brik/logs}}"
    local backend="${log_dir}/pipeline-report.json"
    [[ -f "$backend" ]] || return 0

    local stage_end_ms duration_ms
    stage_end_ms="$(_helpers.epoch_ms)"
    duration_ms=$(( stage_end_ms - stage_start_ms ))

    report.record "$stage_name" "tech" "duration_ms" "$duration_ms" 2>/dev/null || true
    report.record "$stage_name" "tech" "exit_code" "$exit_code" 2>/dev/null || true
    if ! report.has_status "$stage_name"; then
        if [[ "$exit_code" -eq 0 ]]; then
            report.record "$stage_name" "tech" "status" "success" 2>/dev/null || true
        else
            report.record "$stage_name" "tech" "status" "failed" 2>/dev/null || true
        fi
    fi

    [[ "${BRIK_DISABLE_REPORT_FRAGMENTS:-}" == "1" ]] && return 0
    report.write_fragment "$stage_name" 2>/dev/null || \
        log.warn "fragment write failed for stage ${stage_name} (non-fatal)"
    return 0
}

# Main entry point for stage execution.
# Usage: stage.run <stage_name> <logic_function> [args...]
stage.run() {
    local stage_name="$1"
    local logic_function="$2"
    shift 2
    local -a args=("$@")

    local context_file=""
    local log_file=""
    local exit_code=0
    local stage_start_ms
    stage_start_ms="$(_helpers.epoch_ms)"

    banner.stage "$stage_name"
    log.info "starting stage: $stage_name"

    # Create execution context
    context_file="$(context.create "$stage_name")" || return "$BRIK_EXIT_INVALID_ENV"
    log_file="$(stage.create_log_file "$stage_name")" || return "$BRIK_EXIT_IO_FAILURE"
    _context._set "$context_file" "BRIK_LOG_FILE" "$log_file" || return "$BRIK_EXIT_IO_FAILURE"

    # Pre-stage hook (can abort)
    hook.pre_stage "$stage_name" "$context_file" "$log_file" || {
        exit_code=$?
        log.warn "pre-stage hook failed with code $exit_code, aborting stage"
        # best-effort: finalization must not mask the pre-stage hook error
        summary.build "$stage_name" "$context_file" "$log_file" "$exit_code" || true
        _stage._finalize_fragment "$stage_name" "$exit_code" "$stage_start_ms" || true
        stage.cleanup "$context_file" "$log_file" || true
        return "$exit_code"
    }

    # Execute stage logic with logging
    stage.with_logging "$log_file" \
        stage.execute "$stage_name" "$logic_function" "$context_file" "${args[@]}"
    exit_code=$?

    # best-effort: finalization below must not override the stage exit code
    _context._set "$context_file" "BRIK_FINISHED_AT" "$(date +"%Y-%m-%dT%H:%M:%S%z")" || true

    if [[ $exit_code -eq 0 ]]; then
        # Check if the stage recorded a "skipped" status in the pipeline
        # report (config-skip pattern, e.g. quality.lint.enabled=false).
        # Falls back silently to "completed successfully" if the report is
        # absent or jq is unavailable (stage run standalone outside pipeline).
        local _report_path _stage_status=""
        _report_path="${BRIK_LOG_DIR:-${BRIK_DEFAULT_LOG_DIR:-/tmp/brik/logs}}/pipeline-report.json"
        if [[ -f "$_report_path" ]] && command -v jq >/dev/null 2>&1; then
            _stage_status="$(jq -r --arg s "$stage_name" \
                '.stages[] | select(.name == $s) | .tech.status // empty' \
                "$_report_path" 2>/dev/null)" || _stage_status=""
        fi
        case "$_stage_status" in
            disabled)
                log.info "stage $stage_name skipped (disabled)"
                ;;
            not-applicable)
                log.info "stage $stage_name skipped (not configured)"
                ;;
            skipped)
                log.info "stage $stage_name skipped (no config detected)"
                ;;
            *)
                log.info "stage $stage_name completed successfully"
                ;;
        esac
        hook.on_success "$stage_name" "$context_file" "$log_file" || true
    else
        log.error "stage $stage_name failed with exit code $exit_code"
        hook.on_failure "$stage_name" "$context_file" "$log_file" "$exit_code" || true
    fi

    hook.post_stage "$stage_name" "$context_file" "$log_file" "$exit_code" || true

    summary.build "$stage_name" "$context_file" "$log_file" "$exit_code" || true
    _stage._finalize_fragment "$stage_name" "$exit_code" "$stage_start_ms" || true
    stage.cleanup "$context_file" "$log_file" || true

    return "$exit_code"
}

# Map a stage name (kebab-case) to its business-logic function (stages.<snake>),
# show the Brik banner once before the first stage, load cross-stage pipeline
# env, and dispatch to stage.run. This is the business-logic dispatcher shared
# by the lib-level pipeline.run orchestrator and the wrapper-level
# brik.wrapper.run_stage entry point.
#
# Precondition: wrapper setup has exported BRIK_WORKSPACE and BRIK_CONFIG_FILE.
# Backward-compat aliases quality->lint and security->scan are deprecated.
# Usage: stage.dispatch <stage_name>
# Returns: stage.run exit code, or BRIK_EXIT_INVALID_INPUT for empty/unknown stage.
stage.dispatch() {
    local stage_name="$1"

    if [[ -z "$stage_name" ]]; then
        log.error "stage name is required"
        return "$BRIK_EXIT_INVALID_INPUT"
    fi

    # Normalize CI metadata (BRIK_PIPELINE_*/BRIK_COMMIT_*/BRIK_TRIGGERED_BY)
    # before any stage logic runs so report.aggregate_fragments and any other
    # consumer reads from a single, populated source. Idempotent (pre-set
    # BRIK_* wins) so repeated dispatches in the same shell are safe.
    _pipeline.detect_metadata

    # Show the Brik logo once, before the first stage.
    if [[ "$stage_name" == "init" ]]; then
        banner.brik "${BRIK_VERSION:-}"
    fi

    # Load cross-stage variables from previous stages.
    pipeline.env.load

    # Ensure the pipeline report exists so stages can report.record. When
    # invoked via pipeline.run, report.init was already called; in the
    # single-stage path (brik.wrapper.run_stage) we lazily initialize here.
    local _report_path="${BRIK_LOG_DIR:-${BRIK_DEFAULT_LOG_DIR:-/tmp/brik/logs}}/pipeline-report.json"
    [[ -f "$_report_path" ]] || report.init >/dev/null 2>&1 || true

    local logic_function=""
    case "$stage_name" in
        init)            logic_function="stages.init" ;;
        release)         logic_function="stages.release" ;;
        build)           logic_function="stages.build" ;;
        lint)            logic_function="stages.lint" ;;
        sast)            logic_function="stages.sast" ;;
        scan)            logic_function="stages.scan" ;;
        test)            logic_function="stages.test" ;;
        package)         logic_function="stages.package" ;;
        container-scan)  logic_function="stages.container_scan" ;;
        deploy)          logic_function="stages.deploy" ;;
        notify)          logic_function="stages.notify" ;;
        # Backward-compat aliases (deprecated)
        quality)         logic_function="stages.lint" ;;
        security)        logic_function="stages.scan" ;;
        *)
            log.error "unknown stage: $stage_name"
            log.error "valid stages: init, release, build, lint, sast, scan, test, package, container-scan, deploy, notify"
            return "$BRIK_EXIT_INVALID_INPUT"
            ;;
    esac

    stage.run "$stage_name" "$logic_function" "${BRIK_WORKSPACE}" "${BRIK_CONFIG_FILE}"
}
