#!/usr/bin/env bash
# @module quality
# @description Quality dispatcher for brik-lib. Runs quality checks.

# Guard against double-sourcing
[[ -n "${_BRIK_CORE_QUALITY_LOADED:-}" ]] && return 0
_BRIK_CORE_QUALITY_LOADED=1

# Run quality checks on a workspace.
# Usage: quality.run <workspace> [--checks <lint,sast,deps,coverage,license,container>]
quality.run() {
    local workspace="$1"
    shift
    local checks="lint"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --checks) checks="$2"; shift 2 ;;
            *) log.error "unknown option: $1"; return 2 ;;
        esac
    done

    runtime.require_dir "$workspace" || return 6

    log.info "running quality checks: $checks"

    local failed=0 total=0 passed=0
    local IFS=','
    local check
    for check in $checks; do
        total=$((total + 1))
        # Trim whitespace
        check="$(printf '%s' "$check" | tr -d '[:space:]')"

        brik.use "quality.${check}" || {
            log.warn "quality check module not found: $check (skipping)"
            continue
        }

        local check_fn="quality.${check}.run"
        if ! declare -f "$check_fn" >/dev/null 2>&1; then
            log.warn "quality function not found: $check_fn (skipping)"
            continue
        fi

        log.info "running quality check: $check"
        if "$check_fn" "$workspace"; then
            passed=$((passed + 1))
            log.info "quality check passed: $check"
        else
            failed=$((failed + 1))
            log.warn "quality check failed: $check"
        fi
    done

    log.info "quality summary: $passed/$total passed, $failed failed"

    if [[ "$failed" -gt 0 ]]; then
        return 10
    fi
    return 0
}
