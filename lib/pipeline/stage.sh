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
# Usage: _stage._finalize_fragment <stage_name> <exit_code> <stage_start_epoch>
_stage._finalize_fragment() {
    local stage_name="$1"
    local exit_code="$2"
    local stage_start_epoch="$3"

    local log_dir="${BRIK_LOG_DIR:-${BRIK_DEFAULT_LOG_DIR:-/tmp/brik/logs}}"
    local backend="${log_dir}/pipeline-report.json"
    [[ -f "$backend" ]] || return 0

    local stage_end_epoch duration_ms
    stage_end_epoch="$(date +%s)"
    duration_ms=$(( (stage_end_epoch - stage_start_epoch) * 1000 ))

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
    local stage_start_epoch
    stage_start_epoch="$(date +%s)"

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
        _stage._finalize_fragment "$stage_name" "$exit_code" "$stage_start_epoch" || true
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
    _stage._finalize_fragment "$stage_name" "$exit_code" "$stage_start_epoch" || true
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
