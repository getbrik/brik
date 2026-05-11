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
    elif [[ -f "${cov_dir}/lcov.info" ]]; then
        # LCOV (c8/jest default): aggregate LF (lines found) and LH (lines
        # hit) across every record. Each per-file record terminates with
        # `end_of_record`; the totals are summed across the whole file.
        local total_lf total_lh
        total_lf=$(awk -F: '/^LF:/ { sum += $2 } END { print sum+0 }' "${cov_dir}/lcov.info")
        total_lh=$(awk -F: '/^LH:/ { sum += $2 } END { print sum+0 }' "${cov_dir}/lcov.info")
        if [[ "$total_lf" -gt 0 ]]; then
            pct=$(awk -v h="$total_lh" -v f="$total_lf" 'BEGIN { printf "%.2f", h / f * 100 }')
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
    local cov_dir="${1:-${BRIK_TEST_COVERAGE_DIR:-brik-artifacts/test/coverage}}"
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
    local cov_dir="${2:-${BRIK_TEST_COVERAGE_DIR:-brik-artifacts/test/coverage}}"

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

# ---------------------------------------------------------------------------
# Emit a SARIF document describing a coverage breach so the finding flows
# through the unified findings pipeline (apply_policy, fix_classifier,
# business.evaluate). The "test" stage rule in fix_classifier annotates
# coverage findings with fix_classification=has_fix, which means
# business.evaluate yields warning in snapshot and error in release.
#
# Behaviour:
#   empty/unset threshold -> rc=0, no file written (advisory mode)
#   non-numeric threshold -> rc=BRIK_EXIT_INVALID_INPUT (2), error logged
#   coverage >= threshold -> rc=0, SARIF with empty results[]
#   coverage <  threshold -> rc=0, SARIF with one result
#   no/malformed report   -> rc=0, SARIF with empty results[] (advisory)
#
# This function never gates the pipeline: business.evaluate does.
#
# Usage: brik.coverage.emit_sarif <threshold> [<cov_dir>] [<sarif_out>]
brik.coverage.emit_sarif() {
    local threshold="${1:-}"
    local cov_dir="${2:-${BRIK_TEST_COVERAGE_DIR:-brik-artifacts/test/coverage}}"
    local sarif_out="${3:-${BRIK_TEST_FINDINGS_OUTPUT_PATH:-brik-artifacts/test/coverage.sarif}}"

    if [[ -z "$threshold" ]]; then
        return 0
    fi

    if ! printf '%s' "$threshold" | grep -qE '^[0-9]+([.][0-9]+)?$'; then
        printf 'brik.coverage.emit_sarif: invalid threshold %q\n' "$threshold" >&2
        return "${BRIK_EXIT_INVALID_INPUT:-2}"
    fi

    if ! command -v jq >/dev/null 2>&1; then
        printf 'brik.coverage.emit_sarif: jq is required\n' >&2
        return "${BRIK_EXIT_MISSING_DEP:-3}"
    fi

    local out_dir
    out_dir="$(dirname "$sarif_out")"
    mkdir -p "$out_dir" 2>/dev/null || true

    local pct=""
    if [[ -f "${cov_dir}/coverage.xml" || -f "${cov_dir}/jacoco.xml" || -f "${cov_dir}/lcov.info" ]]; then
        pct="$(_brik.coverage._parse_pct "$cov_dir")"
    fi

    local below="0"
    if [[ -n "$pct" ]]; then
        below=$(awk -v a="$pct" -v r="$threshold" 'BEGIN { print (a < r) ? "1" : "0" }')
    fi

    if [[ "$below" == "1" ]]; then
        local msg
        msg=$(printf 'Coverage %s%% is below the configured threshold %s%%.' "$pct" "$threshold")
        jq -n \
            --arg pct "$pct" \
            --arg threshold "$threshold" \
            --arg msg "$msg" \
            '{
                "$schema": "https://json.schemastore.org/sarif-2.1.0.json",
                version: "2.1.0",
                runs: [{
                    tool: { driver: {
                        name: "brik-coverage",
                        rules: [{
                            id: "brik-coverage-below-threshold",
                            shortDescription: { text: "Coverage below configured threshold" },
                            fullDescription:  { text: "The measured line coverage is lower than quality.test.coverage_min." },
                            defaultConfiguration: { level: "error" }
                        }]
                    } },
                    results: [{
                        ruleId: "brik-coverage-below-threshold",
                        level: "error",
                        message: { text: $msg },
                        properties: {
                            measured_pct:  ($pct       | tonumber),
                            threshold_pct: ($threshold | tonumber)
                        }
                    }]
                }]
            }' > "$sarif_out"
    else
        # Above threshold, missing report, or malformed: emit an empty
        # SARIF so the per-stage findings pipeline still sees a valid
        # document and downstream apply_policy keeps working.
        jq -n \
            '{
                "$schema": "https://json.schemastore.org/sarif-2.1.0.json",
                version: "2.1.0",
                runs: [{
                    tool: { driver: { name: "brik-coverage" } },
                    results: []
                }]
            }' > "$sarif_out"
    fi
    return 0
}
