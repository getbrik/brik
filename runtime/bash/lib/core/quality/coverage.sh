#!/usr/bin/env bash
# @module quality.coverage
# @requires yq
# @description Check test coverage against a threshold (Cobertura XML via yq).

# Guard against double-sourcing
[[ -n "${_BRIK_CORE_QUALITY_COVERAGE_LOADED:-}" ]] && return 0
_BRIK_CORE_QUALITY_COVERAGE_LOADED=1

# Check coverage threshold.
# Usage: quality.coverage.run <workspace> [--threshold <percent>] [--report <path>]
quality.coverage.run() {
    local workspace="$1"
    shift
    local threshold="0" report=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --threshold) threshold="$2"; shift 2 ;;
            --report) report="$2"; shift 2 ;;
            *) log.error "unknown option: $1"; return 2 ;;
        esac
    done

    runtime.require_dir "$workspace" || return 6

    # Auto-detect coverage report if not specified
    if [[ -z "$report" ]]; then
        local candidate
        for candidate in \
            "${workspace}/coverage/cobertura-coverage.xml" \
            "${workspace}/coverage.xml" \
            "${workspace}/target/site/cobertura/coverage.xml" \
            "${workspace}/build/reports/cobertura/coverage.xml"; do
            if [[ -f "$candidate" ]]; then
                report="$candidate"
                break
            fi
        done
    fi

    if [[ -z "$report" || ! -f "$report" ]]; then
        log.warn "no coverage report found - skipping threshold check"
        return 0
    fi

    runtime.require_tool yq || return 3

    # Extract line-rate from Cobertura XML using yq
    # Cobertura XML has <coverage line-rate="0.85" ...>
    local line_rate
    line_rate="$(yq -p xml -o json '.coverage.+@line-rate' "$report" 2>/dev/null)" || {
        log.error "failed to parse coverage report: $report"
        return 5
    }

    # Strip quotes from yq output
    line_rate="${line_rate//\"/}"

    if [[ -z "$line_rate" || "$line_rate" == "null" ]]; then
        log.error "no line-rate attribute found in coverage report"
        return 5
    fi

    # Convert rate (0.0-1.0) to percentage using awk (more portable than bc)
    local percent
    percent="$(awk "BEGIN { printf \"%.0f\", $line_rate * 100 }" 2>/dev/null)" || {
        log.error "failed to compute coverage percentage"
        return 5
    }

    log.info "coverage: ${percent}% (threshold: ${threshold}%)"

    if [[ "$percent" -lt "$threshold" ]]; then
        log.error "coverage ${percent}% is below threshold ${threshold}%"
        return 10
    fi

    log.info "coverage check passed"
    return 0
}
