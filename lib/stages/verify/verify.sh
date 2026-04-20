#!/usr/bin/env bash
# @module stages/verify
# @description Quality dispatcher for brik-lib. Runs quality checks.

# Guard against double-sourcing
[[ -n "${_BRIK_STAGES_VERIFY_LOADED:-}" ]] && return 0
_BRIK_STAGES_VERIFY_LOADED=1

# Run quality checks on a workspace.
# Usage: verify.run <workspace> [--checks <lint,format,type_check>]
verify.run() {
    local workspace="$1"
    shift
    local checks="lint"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --checks) checks="$2"; shift 2 ;;
            *) log.error "unknown option: $1"; return "$BRIK_EXIT_INVALID_INPUT" ;;
        esac
    done

    pipeline.require_dir "$workspace" || return "$BRIK_EXIT_IO_FAILURE"

    log.info "running verify checks: $checks"

    brik.use transverse.csv

    local failed=0 total=0 passed=0
    transverse.csv.foreach "$checks" _verify._run_one_check "$workspace" total passed failed

    log.info "verify summary: $passed/$total passed, $failed failed"

    if [[ "$failed" -gt 0 ]]; then
        return "$BRIK_EXIT_CHECK_FAILED"
    fi
    return 0
}

# Private: run a single verify check. Invoked once per CSV item by
# transverse.csv.foreach. Counter variables are passed by name (nameref) so
# mutation is explicit in the signature rather than implicit via dynamic scope.
# Args: $1 = check name (trimmed)
#       $2 = workspace
#       $3 = name of total counter (nameref)
#       $4 = name of passed counter (nameref)
#       $5 = name of failed counter (nameref)
_verify._run_one_check() {
    local check="$1"
    local workspace="$2"
    local -n _total=$3
    local -n _passed=$4
    local -n _failed=$5

    _total=$((_total + 1))

    brik.use "verify.${check}" || {
        log.warn "verify check module not found: $check (skipping)"
        return 0
    }

    local check_fn="verify.${check}.run"
    if ! declare -f "$check_fn" >/dev/null 2>&1; then
        log.warn "verify function not found: $check_fn (skipping)"
        return 0
    fi

    log.info "running verify check: $check"
    if "$check_fn" "$workspace"; then
        _passed=$((_passed + 1))
        log.info "verify check passed: $check"
    else
        _failed=$((_failed + 1))
        log.warn "verify check failed: $check"
    fi
    return 0
}
