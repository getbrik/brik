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

# Decide whether a stage should be skipped based on opt-in flags.
# Returns 0 (true) if the stage should be skipped, 1 otherwise.
# Usage: _pipeline._should_skip <stage> <with_release> <with_package> <with_deploy>
_pipeline._should_skip() {
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
    local continue_on_error=false
    local with_release=false
    local with_package=false
    local with_deploy=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --continue-on-error) continue_on_error=true; shift ;;
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

    report.init || return "$?"

    local -a stages=(init release build lint sast scan test package container-scan deploy notify)
    local had_failure=false
    local stage stage_start stage_end duration_ms rc

    for stage in "${stages[@]}"; do
        if _pipeline._should_skip "$stage" "$with_release" "$with_package" "$with_deploy"; then
            report.record "$stage" "tech" "status" "skipped" || true
            continue
        fi
        if $had_failure && ! $continue_on_error; then
            report.record "$stage" "tech" "status" "skipped" || true
            continue
        fi

        stage_start="$(date +%s)"
        stage.dispatch "$stage"
        rc=$?
        stage_end="$(date +%s)"
        duration_ms=$(( (stage_end - stage_start) * 1000 ))

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

        [[ $rc -ne 0 ]] && had_failure=true
    done

    report.render || true

    if $had_failure; then
        return "$BRIK_EXIT_FAILURE"
    fi
    return 0
}
