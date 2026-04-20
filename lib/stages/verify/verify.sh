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

    local failed=0 total=0 passed=0
    local IFS=','
    local check
    for check in $checks; do
        total=$((total + 1))
        # Trim whitespace
        check="$(printf '%s' "$check" | tr -d '[:space:]')"

        brik.use "verify.${check}" || {
            log.warn "verify check module not found: $check (skipping)"
            continue
        }

        local check_fn="verify.${check}.run"
        if ! declare -f "$check_fn" >/dev/null 2>&1; then
            log.warn "verify function not found: $check_fn (skipping)"
            continue
        fi

        log.info "running verify check: $check"
        if "$check_fn" "$workspace"; then
            passed=$((passed + 1))
            log.info "verify check passed: $check"
        else
            failed=$((failed + 1))
            log.warn "verify check failed: $check"
        fi
    done

    log.info "verify summary: $passed/$total passed, $failed failed"

    if [[ "$failed" -gt 0 ]]; then
        return "$BRIK_EXIT_CHECK_FAILED"
    fi
    return 0
}
