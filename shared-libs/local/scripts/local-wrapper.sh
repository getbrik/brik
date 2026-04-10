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
# If not inside a git repo, emits a warning and sets empty values.
_brik_local_setup_git_context() {
    if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
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
    BRIK_BRANCH="$(git branch --show-current 2>/dev/null || echo "")"
    export BRIK_TAG
    BRIK_TAG="$(git describe --tags --exact-match 2>/dev/null || echo "")"
    export BRIK_COMMIT_SHA
    BRIK_COMMIT_SHA="$(git rev-parse HEAD 2>/dev/null || echo "")"
    export BRIK_COMMIT_SHORT_SHA
    BRIK_COMMIT_SHORT_SHA="$(git rev-parse --short HEAD 2>/dev/null || echo "")"
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
# Usage: brik.local.run_pipeline [--continue-on-error] [--with-release]
#        [--with-package] [--with-deploy]
# Exit codes: 0=all stages passed, BRIK_EXIT_FAILURE=at least one stage failed, BRIK_EXIT_INVALID_INPUT=invalid flag
# shellcheck disable=SC2034
brik.local.run_pipeline() {
    local continue_on_error=false
    local with_release=false
    local with_package=false
    local with_deploy=false
    local stage="" stage_start=0 stage_end=0 rc=0

    # Parse flags
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --continue-on-error) continue_on_error=true; shift ;;
            --with-release)      with_release=true; shift ;;
            --with-package)      with_package=true; shift ;;
            --with-deploy)       with_deploy=true; shift ;;
            *)
                log.error "unknown pipeline flag: $1"
                return "$BRIK_EXIT_INVALID_INPUT"
                ;;
        esac
    done

    if $with_deploy; then
        log.warn "deploy stage enabled - be careful running deploy locally"
    fi

    # Fixed flow: stages to run and stages to skip
    # Default: init, build, lint, sast, scan, test
    # Opt-in: release, package, container-scan, deploy, notify
    local -a all_stages=(init release build lint sast scan test package container-scan deploy notify)

    # Track results: associative arrays for status and duration
    local -A stage_status=()
    local -A stage_duration=()
    local pipeline_start=0
    pipeline_start="$(date +%s)"
    local had_failure=false
    local pipeline_end=0
    local total_duration=0

    for stage in "${all_stages[@]}"; do
        # Determine if this stage should run or be skipped
        if _brik_local_should_skip_stage "$stage" "$with_release" "$with_package" "$with_deploy"; then
            stage_status[$stage]="SKIP"
            stage_duration[$stage]="0"
            continue
        fi

        # If a previous stage failed and we're not continuing on error, skip rest
        if $had_failure && ! $continue_on_error; then
            stage_status[$stage]="SKIP"
            stage_duration[$stage]="0"
            continue
        fi

        stage_start="$(date +%s)"

        brik.local.run_stage "$stage"
        rc=$?

        stage_end="$(date +%s)"
        stage_duration[$stage]=$(( stage_end - stage_start ))

        if [[ $rc -eq 0 ]]; then
            stage_status[$stage]="PASS"
        else
            stage_status[$stage]="FAIL"
            had_failure=true
        fi
    done

    pipeline_end="$(date +%s)"
    total_duration=$(( pipeline_end - pipeline_start ))

    # Print summary
    brik.local.print_summary all_stages stage_status stage_duration "$total_duration"

    if $had_failure; then
        return "$BRIK_EXIT_FAILURE"
    fi
    return 0
}

# Determine if a stage should be skipped based on flags.
# Returns 0 (true) if the stage should be skipped.
_brik_local_should_skip_stage() {
    local stage="$1"
    local with_release="$2"
    local with_package="$3"
    local with_deploy="$4"

    case "$stage" in
        release)        [[ "$with_release" != "true" ]] && return 0 ;;
        package)        [[ "$with_package" != "true" ]] && return 0 ;;
        container-scan) [[ "$with_package" != "true" ]] && return 0 ;;
        deploy)         [[ "$with_deploy" != "true" ]] && return 0 ;;
        notify)         [[ "$with_deploy" != "true" ]] && return 0 ;;
    esac
    return 1
}

# ---------------------------------------------------------------------------
# Pipeline summary
# ---------------------------------------------------------------------------

# Print a visual summary of the pipeline execution.
# Usage: brik.local.print_summary <stages_array_name> <status_array_name>
#        <duration_array_name> <total_duration>
brik.local.print_summary() {
    if [[ $# -lt 4 ]]; then
        echo "error: brik.local.print_summary requires 4 arguments" >&2
        return "$BRIK_EXIT_INVALID_INPUT"
    fi

    local -n __brik_ps_stages="$1"
    local -n __brik_ps_status="$2"
    local -n __brik_ps_duration="$3"
    local total_duration="$4"

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

    local passed=0 failed=0 skipped=0 ran=0
    local stage="" status="" duration_s="" color="" duration_str=""

    echo ""
    echo "${bold}--- Pipeline Summary ---${reset}"

    for stage in "${__brik_ps_stages[@]}"; do
        status="${__brik_ps_status[$stage]:-SKIP}"
        duration_s="${__brik_ps_duration[$stage]:-0}"

        color=""
        duration_str=""
        case "$status" in
            PASS)
                color="$green"
                duration_str="${duration_s}s"
                (( ++passed ))
                (( ++ran ))
                ;;
            FAIL)
                color="$red"
                duration_str="${duration_s}s"
                (( ++failed ))
                (( ++ran ))
                ;;
            SKIP)
                color="$gray"
                duration_str=""
                (( ++skipped ))
                ;;
        esac

        printf "  %-12s %s%-4s%s" "$stage" "$color" "$status" "$reset"
        if [[ -n "$duration_str" ]]; then
            printf "  %s" "$duration_str"
        fi
        echo ""
    done

    echo "${bold}------------------------${reset}"

    local result_color="$green"
    local result_label="PASS"
    if [[ $failed -gt 0 ]]; then
        result_color="$red"
        result_label="FAIL"
    fi

    echo "${bold}Result: ${result_color}${result_label}${reset} (${passed}/${ran} passed, ${skipped} skipped)"
    echo "${bold}Duration: ${total_duration}s${reset}"
    echo ""
}
