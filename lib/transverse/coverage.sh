#!/usr/bin/env bash
# @module transverse/coverage
# @description Helper that reads a standardized coverage report file and
# emits a single-line summary that downstream CI templates can parse with
# a single regex. Used by stages.test when reports.enabled=true.

# Guard against double-sourcing
[[ -n "${_BRIK_TRANSVERSE_COVERAGE_LOADED:-}" ]] && return 0
_BRIK_TRANSVERSE_COVERAGE_LOADED=1

# ---------------------------------------------------------------------------
# Private: parse coverage percentage from report files in <cov_dir>.
# Reads in order of preference:
#   - ${cov_dir}/coverage.xml  (Cobertura: <coverage line-rate="..."/>)
#   - ${cov_dir}/jacoco.xml    (Jacoco: aggregated <counter type="LINE"/>)
#
# Prints the percentage string (e.g. "85.42") on stdout, or nothing if the
# report cannot be parsed. Always returns 0.
#
# Usage: _brik.coverage._parse_pct <cov_dir>
_brik.coverage._parse_pct() {
    local cov_dir="$1"
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
        printf '%s' "$pct"
    fi
    return 0
}

# ---------------------------------------------------------------------------
# Private: parse branch coverage percentage from report files in <cov_dir>.
# Mirrors _parse_pct but reads branch-rate / BRANCH counter instead.
#
#   - ${cov_dir}/coverage.xml  (Cobertura: <coverage branch-rate="..."/>)
#   - ${cov_dir}/jacoco.xml    (Jacoco: aggregated <counter type="BRANCH"/>)
#
# Prints the percentage string (e.g. "72.00") on stdout, or nothing when
# the metric is absent or unparseable. Always returns 0.
#
# Usage: _brik.coverage._parse_branch_pct <cov_dir>
_brik.coverage._parse_branch_pct() {
    local cov_dir="$1"
    local pct=""

    if [[ -f "${cov_dir}/coverage.xml" ]]; then
        local rate
        rate=$(grep -oE 'branch-rate="[0-9.]+"' "${cov_dir}/coverage.xml" | head -1 | sed -E 's/branch-rate="([0-9.]+)"/\1/')
        if [[ -n "$rate" ]]; then
            pct=$(awk -v r="$rate" 'BEGIN { printf "%.2f", r * 100 }')
        fi
    elif [[ -f "${cov_dir}/jacoco.xml" ]]; then
        local last_counter missed covered
        last_counter=$(grep -oE '<counter type="BRANCH"[^/]*/>' "${cov_dir}/jacoco.xml" | tail -1)
        missed=$(printf '%s' "$last_counter" | grep -oE 'missed="[0-9]+"' | sed -E 's/missed="([0-9]+)"/\1/')
        covered=$(printf '%s' "$last_counter" | grep -oE 'covered="[0-9]+"' | sed -E 's/covered="([0-9]+)"/\1/')
        if [[ -n "$missed" && -n "$covered" && $((missed + covered)) -gt 0 ]]; then
            pct=$(awk -v m="$missed" -v c="$covered" 'BEGIN { printf "%.2f", c / (c + m) * 100 }')
        fi
    fi

    if [[ -n "$pct" ]]; then
        printf '%s' "$pct"
    fi
    return 0
}

# ---------------------------------------------------------------------------
# Print "[brik] coverage: XX.XX%" parsed from the standard report files.
# Output: one line on stdout when a value is found; nothing otherwise.
# Always returns 0 -- this is informational, never a gate.
#
# Usage: brik.coverage.summary [<cov_dir>]
brik.coverage.summary() {
    local cov_dir="${1:-${BRIK_TEST_COVERAGE_DIR:-coverage}}"
    local pct
    pct=$(_brik.coverage._parse_pct "$cov_dir")

    if [[ -n "$pct" ]]; then
        printf '[brik] coverage: %s%%\n' "$pct"
    fi
    return 0
}

# ---------------------------------------------------------------------------
# Enforce a minimum coverage threshold. Returns non-zero when measured
# coverage falls below the threshold, allowing the Test stage to fail.
#
# Behaviour:
#   empty/unset threshold -> return 0 silently (advisory mode)
#   non-numeric threshold -> log.error + return BRIK_EXIT_INVALID_INPUT (2)
#   no report file        -> log.warn  + return 0 (missing data must not block)
#   malformed XML         -> log.warn  + return 0 (advisory)
#   coverage >= threshold -> log.info  + return 0
#   coverage < threshold  -> log.error + return BRIK_EXIT_CHECK_FAILED (10)
#
# Threshold accepts integer (80) or decimal (80.5) values.
#
# Usage: brik.coverage.gate <threshold> [<cov_dir>]
brik.coverage.gate() {
    local threshold="${1:-}"
    local cov_dir="${2:-${BRIK_TEST_COVERAGE_DIR:-coverage}}"

    # Advisory mode: no threshold configured.
    if [[ -z "$threshold" ]]; then
        return 0
    fi

    # Validate: threshold must be a non-negative number (integer or decimal).
    if ! printf '%s' "$threshold" | grep -qE '^[0-9]+([.][0-9]+)?$'; then
        log.error "coverage gate: invalid threshold '${threshold}' (must be a non-negative number)"
        return "${BRIK_EXIT_INVALID_INPUT}"
    fi

    # Check report files exist.
    if [[ ! -f "${cov_dir}/coverage.xml" && ! -f "${cov_dir}/jacoco.xml" ]]; then
        log.warn "coverage gate skipped: no coverage report at ${cov_dir}"
        return 0
    fi

    # Parse percentage.
    local pct
    pct=$(_brik.coverage._parse_pct "$cov_dir")

    if [[ -z "$pct" ]]; then
        log.warn "coverage gate skipped: could not parse coverage report at ${cov_dir}"
        return 0
    fi

    # Compare with awk to handle decimal arithmetic correctly.
    local passed
    passed=$(awk -v actual="$pct" -v required="$threshold" \
        'BEGIN { print (actual >= required) ? "1" : "0" }')

    if [[ "$passed" == "1" ]]; then
        log.info "coverage ${pct}% >= threshold ${threshold}%"
        return 0
    else
        log.error "coverage ${pct}% is below threshold ${threshold}%"
        return "${BRIK_EXIT_CHECK_FAILED}"
    fi
}
