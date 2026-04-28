#!/usr/bin/env bash
# @module transverse/coverage
# @description Helper that reads a standardized coverage report file and
# emits a single-line summary that downstream CI templates can parse with
# a single regex. Used by stages.test when reports.enabled=true.

# Guard against double-sourcing
[[ -n "${_BRIK_TRANSVERSE_COVERAGE_LOADED:-}" ]] && return 0
_BRIK_TRANSVERSE_COVERAGE_LOADED=1

# Print "[brik] coverage: XX.XX%" parsed from the standard report files.
# Reads in order of preference:
#   - ${cov_dir}/coverage.xml  (Cobertura: <coverage line-rate="..."/>)
#   - ${cov_dir}/jacoco.xml    (Jacoco: aggregated <counter type="LINE"/>)
#
# Output: one line on stdout when a value is found; nothing otherwise.
# Always returns 0 -- this is informational, never a gate.
#
# Usage: brik.coverage.summary [<cov_dir>]
brik.coverage.summary() {
    local cov_dir="${1:-${BRIK_TEST_COVERAGE_DIR:-coverage}}"
    local pct=""

    if [[ -f "${cov_dir}/coverage.xml" ]]; then
        # Cobertura: <coverage line-rate="0.8542" .../> on the root element.
        local rate
        rate=$(grep -oE 'line-rate="[0-9.]+"' "${cov_dir}/coverage.xml" | head -1 | sed -E 's/line-rate="([0-9.]+)"/\1/')
        if [[ -n "$rate" ]]; then
            pct=$(awk -v r="$rate" 'BEGIN { printf "%.2f", r * 100 }')
        fi
    elif [[ -f "${cov_dir}/jacoco.xml" ]]; then
        # Jacoco emits per-method/class/package/report counters, in that
        # order. The last <counter type="LINE"/> in the file is the
        # report-level aggregate.
        local last_counter missed covered
        last_counter=$(grep -oE '<counter type="LINE"[^/]*/>' "${cov_dir}/jacoco.xml" | tail -1)
        missed=$(printf '%s' "$last_counter" | grep -oE 'missed="[0-9]+"' | sed -E 's/missed="([0-9]+)"/\1/')
        covered=$(printf '%s' "$last_counter" | grep -oE 'covered="[0-9]+"' | sed -E 's/covered="([0-9]+)"/\1/')
        if [[ -n "$missed" && -n "$covered" && $((missed + covered)) -gt 0 ]]; then
            pct=$(awk -v m="$missed" -v c="$covered" 'BEGIN { printf "%.2f", c / (c + m) * 100 }')
        fi
    fi

    if [[ -n "$pct" ]]; then
        printf '[brik] coverage: %s%%\n' "$pct"
    fi
    return 0
}
