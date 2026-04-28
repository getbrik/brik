#!/usr/bin/env bash
# @module local-wrapper
# @description Bridges local CLI execution to the Brik runtime (stage.run).
#
# This is a thin adapter that:
# 1. Sets up the local environment (BRIK_* from git)
# 2. Delegates common bootstrap and dispatch to base-wrapper.sh
# 3. Orchestrates the full pipeline: Init -> Release -> Build -> Lint||SAST||Scan||Test -> Package -> Container Scan -> Deploy -> Notify
#
# Usage from brik CLI:
#   source "${BRIK_HOME}/shared-libs/local/scripts/local-wrapper.sh"
#   brik.local.setup
#   brik.local.run_stage <stage_name>
#   brik.local.run_pipeline [flags]

# Guard against double-sourcing
[[ -n "${_BRIK_LOCAL_WRAPPER_LOADED:-}" ]] && return 0
_BRIK_LOCAL_WRAPPER_LOADED=1

# Source shared wrapper logic
_BRIK_WRAPPER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "${_BRIK_WRAPPER_DIR}/../../common/scripts/base-wrapper.sh"

# ---------------------------------------------------------------------------
# Bootstrap: setup BRIK_HOME, source runtime, load stages
# ---------------------------------------------------------------------------

# Setup the Brik runtime environment for local execution.
# Populates BRIK_* variables from the local Git repository.
# Must be called once before any brik.local.run_stage calls.
# Exit codes: 0=success, BRIK_EXIT_INVALID_ENV=environment error, BRIK_EXIT_CONFIG_ERROR=config error
brik.local.setup() {
    brik.wrapper.validate_home "${BRIK_HOME:-}" || return $?

    export BRIK_PROJECT_DIR="${BRIK_PROJECT_DIR:-$(pwd)}"
    export BRIK_PLATFORM="local"

    brik.wrapper.set_standard_env
    # Source runtime before git context so log.warn is available
    brik.wrapper.bootstrap || return $?

    # Platform variable normalization from local Git (after runtime for log.warn)
    _brik_local_setup_git_context

    brik.wrapper.load_config || return $?

    log.info "brik local setup complete (BRIK_HOME=$BRIK_HOME)"
    return 0
}

# Populate BRIK_* variables from the local Git repository.
# Resolves the git context against BRIK_PROJECT_DIR (set by the CLI from
# --workspace) so the host shell's cwd cannot leak in when brik runs
# against a project located elsewhere. Falls back to cwd when
# BRIK_PROJECT_DIR is unset (legacy callers and direct unit tests).
# If not inside a git repo, emits a warning and sets empty values.
_brik_local_setup_git_context() {
    local _project_dir="${BRIK_PROJECT_DIR:-$(pwd)}"

    if ! git -C "$_project_dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        if declare -f log.warn >/dev/null 2>&1; then
            log.warn "not inside a git repository - git context variables will be empty"
        else
            echo "warning: not inside a git repository - git context variables will be empty" >&2
        fi
        export BRIK_BRANCH=""
        export BRIK_TAG=""
        export BRIK_COMMIT_SHA=""
        export BRIK_COMMIT_SHORT_SHA=""
        export BRIK_COMMIT_REF=""
        export BRIK_PIPELINE_SOURCE="local"
        export BRIK_MERGE_REQUEST_ID=""
        return 0
    fi

    export BRIK_BRANCH
    BRIK_BRANCH="$(git -C "$_project_dir" branch --show-current 2>/dev/null || echo "")"
    export BRIK_TAG
    BRIK_TAG="$(git -C "$_project_dir" describe --tags --exact-match 2>/dev/null || echo "")"
    export BRIK_COMMIT_SHA
    BRIK_COMMIT_SHA="$(git -C "$_project_dir" rev-parse HEAD 2>/dev/null || echo "")"
    export BRIK_COMMIT_SHORT_SHA
    BRIK_COMMIT_SHORT_SHA="$(git -C "$_project_dir" rev-parse --short HEAD 2>/dev/null || echo "")"
    export BRIK_COMMIT_REF="${BRIK_BRANCH:-${BRIK_TAG:-}}"
    export BRIK_PIPELINE_SOURCE="local"
    export BRIK_MERGE_REQUEST_ID=""
}

# ---------------------------------------------------------------------------
# Stage dispatcher
# ---------------------------------------------------------------------------

# Run a stage by name. Dispatches to portable stages.* functions via stage.run.
# Usage: brik.local.run_stage <stage_name>
# Exit codes: 0=success, BRIK_EXIT_INVALID_INPUT=invalid argument, BRIK_EXIT_INVALID_ENV=setup not called
brik.local.run_stage() {
    brik.wrapper.run_stage "$@"
}

# ---------------------------------------------------------------------------
# Pipeline orchestration
# ---------------------------------------------------------------------------

# Run the full fixed-flow pipeline locally.
#
# Thin delegator (per spec 6.15): wrapper setup has already been done by
# brik.local.setup. We call pipeline.run in the lib layer, then render a
# terminal-friendly summary from the produced pipeline-report.json.
#
# Usage: brik.local.run_pipeline [--continue-on-error] [--with-release]
#        [--with-package] [--with-deploy]
# Exit codes: pipeline.run's exit code
#   (0 all passed, BRIK_EXIT_FAILURE any failed, BRIK_EXIT_INVALID_INPUT bad flag).
brik.local.run_pipeline() {
    local rc=0
    pipeline.run "$@"
    rc=$?
    brik.local.print_summary || true
    return "$rc"
}

# ---------------------------------------------------------------------------
# Pipeline summary
# ---------------------------------------------------------------------------

# Render a human-readable pipeline summary on stdout from the pipeline report
# JSON. Matches the legacy table layout (stage | status | duration) and
# counts line ("X/Y passed, Z skipped"). Status labels: PASS (tech.status ==
# success), FAIL (failed), SKIP (skipped).
# Usage: brik.local.print_summary [<report_json_path>]
# Default path: $BRIK_LOG_DIR/pipeline-report.json.
brik.local.print_summary() {
    local report_path="${1:-${BRIK_LOG_DIR:-${BRIK_DEFAULT_LOG_DIR:-/tmp/brik/logs}}/pipeline-report.json}"

    if [[ ! -f "$report_path" ]]; then
        log.warn "pipeline report not found: $report_path"
        return "$BRIK_EXIT_IO_FAILURE"
    fi
    if ! command -v jq >/dev/null 2>&1; then
        log.warn "jq not available, skipping summary"
        return 0
    fi

    # Detect color support
    local use_color=false
    if [[ -t 1 ]] && [[ "${TERM:-}" != "dumb" ]]; then
        use_color=true
    fi

    local green="" red="" gray="" bold="" reset=""
    if $use_color; then
        green=$'\033[32m'
        red=$'\033[31m'
        gray=$'\033[90m'
        bold=$'\033[1m'
        reset=$'\033[0m'
    fi

    # Extract per-stage rows as TAB-separated: name<TAB>status<TAB>duration_ms
    local rows
    rows="$(jq -r '.stages[] | [.name, (.tech.status // "skipped"), (.tech.duration_ms // "0")] | @tsv' "$report_path")" || {
        log.warn "failed to parse pipeline report: $report_path"
        return "$BRIK_EXIT_FAILURE"
    }

    local passed=0 failed=0 skipped=0 ran=0 total_duration_ms=0
    local name status_raw duration_ms label color duration_str

    echo ""
    echo "${bold}--- Pipeline Summary ---${reset}"

    while IFS=$'\t' read -r name status_raw duration_ms; do
        [[ -z "$name" ]] && continue
        case "$status_raw" in
            success)
                label="PASS"; color="$green"
                (( ++passed )); (( ++ran ))
                duration_str="${duration_ms}ms"
                total_duration_ms=$(( total_duration_ms + duration_ms ))
                ;;
            failed)
                label="FAIL"; color="$red"
                (( ++failed )); (( ++ran ))
                duration_str="${duration_ms}ms"
                total_duration_ms=$(( total_duration_ms + duration_ms ))
                ;;
            *)
                label="SKIP"; color="$gray"
                (( ++skipped ))
                duration_str=""
                ;;
        esac
        printf "  %-14s %s%-4s%s" "$name" "$color" "$label" "$reset"
        [[ -n "$duration_str" ]] && printf "  %s" "$duration_str"
        echo ""
    done <<< "$rows"

    echo "${bold}------------------------${reset}"

    local result_color="$green"
    local result_label="PASS"
    if [[ $failed -gt 0 ]]; then
        result_color="$red"
        result_label="FAIL"
    fi

    echo "${bold}Result: ${result_color}${result_label}${reset} (${passed}/${ran} passed, ${skipped} skipped)"
    echo "${bold}Duration: $(( total_duration_ms / 1000 ))s${reset}"
    echo ""
}
