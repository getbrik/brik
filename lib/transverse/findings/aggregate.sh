#!/usr/bin/env bash
# @module transverse.findings.aggregate
# @requires jq, transverse.sarif
# @description Aggregate stage of the findings pipeline: record a stage's
#   SARIF counts into the pipeline backend (aggregate) and merge per-stage
#   SARIF documents into a single pipeline-level aggregate.sarif
#   (merge_pipeline). Split out of lib/transverse/findings.sh; loaded by
#   the findings.sh facade.
#
# Depends on facade-provided globals / runtime functions:
#   _BRIK_JQ_SEVERITY_DEFS    (transverse/sarif.sh)
#   _FINDINGS_JQ_RESULT_DEFS  (findings.sh facade)
#   sarif.count_total / sarif.count_by_severity / sarif.extract_cwe (sarif.sh)
#   report.record_object      (pipeline/report.sh, resolved at runtime)

[[ -n "${_BRIK_MODULE_TRANSVERSE_FINDINGS_AGGREGATE_LOADED:-}" ]] && return 0
_BRIK_MODULE_TRANSVERSE_FINDINGS_AGGREGATE_LOADED=1

# shellcheck source=../sarif.sh
[[ -z "${_BRIK_TRANSVERSE_SARIF_LOADED:-}" ]] && [[ -f "${BASH_SOURCE[0]%/*}/../sarif.sh" ]] && . "${BASH_SOURCE[0]%/*}/../sarif.sh"

# Record a stage's SARIF report into business.findings + business.report
# on the pipeline backend (aggregate-report.json). Idempotent: re-recording
# upserts the same stage entry.
#
# Recorded shape (L4 v1, preserved verbatim for backward compatibility with
# Jenkins Warnings NG and the GitLab Ultimate SARIF overlay; L4 v2 adds
# failing/ignored/expiring_soon on top of these):
#
#   business.findings = { total: int,
#                         by_severity: { critical, high, medium, low, info },
#                         cwe: [ "CWE-NN", ... ] }
#   business.report   = { format: "sarif", path: <relative-to-workspace> }
#
# Silent no-op when the SARIF is missing, jq is unavailable, or the SARIF
# helpers have not been loaded -- mirrors the legacy _sast._record_business
# behaviour to keep the integration trivially safe across stages.
#
# Args:
#   $1 stage      -- stage name recorded in the backend (sast, scan, ...).
#   $2 sarif_path -- absolute or BRIK_WORKSPACE-relative path. When the
#                    path is nested under BRIK_WORKSPACE, the recorded
#                    business.report.path is rewritten to the relative form
#                    so CI surfaces resolve it against the working tree.
findings.aggregate() {
    if [[ $# -lt 2 ]]; then
        printf 'findings.aggregate: missing arguments (expected: stage sarif_path)\n' >&2
        return "$BRIK_EXIT_INVALID_INPUT"
    fi
    local stage="$1" sarif_path="$2"
    if [[ -z "$stage" ]]; then
        printf 'findings.aggregate: stage must not be empty\n' >&2
        return "$BRIK_EXIT_INVALID_INPUT"
    fi

    [[ -f "$sarif_path" ]] || return 0
    command -v jq >/dev/null 2>&1 || return 0
    declare -f sarif.count_total >/dev/null 2>&1 || return 0
    declare -f report.record_object >/dev/null 2>&1 || return 0

    local total by_severity cwe
    total="$(sarif.count_total "$sarif_path" 2>/dev/null || printf '0')"
    by_severity="$(sarif.count_by_severity "$sarif_path" 2>/dev/null \
        || printf '{"critical":0,"high":0,"medium":0,"low":0,"info":0}')"
    cwe="$(sarif.extract_cwe "$sarif_path" 2>/dev/null || printf '[]')"

    # L4 v2 enrichment: failing vs ignored split,
    # ignored breakdown by brikSource and by severity. Counts are derived
    # from result.suppressions[]: a result with at least one suppression
    # entry counts as ignored; the brikSource on the first entry decides
    # the source bucket (defaulting to tool_native for natively-suppressed
    # results that lack our properties.brikSource annotation).
    local v2_stats
    # KCOV_EXCL_START -- jq script body is not bash code
    v2_stats="$(jq -c "${_BRIK_JQ_SEVERITY_DEFS}${_FINDINGS_JQ_RESULT_DEFS}"'
        # cvss_bucket / level_bucket come from ${_BRIK_JQ_SEVERITY_DEFS} and
        # rule_for / severity_of_result from ${_FINDINGS_JQ_RESULT_DEFS}
        # (both at the top of findings.sh), prepended to this program above.
        . as $sarif
        | (.runs[0].results // []) as $results
        | ($results | map(select(((.suppressions // []) | length) == 0))) as $fail
        | ($fail | length) as $failing_total
        # SC19: when fix_classifier annotates brikToolBlocking (lint/format
        # only today), count only the tool-blocking subset in has_fix /
        # no_fix. Other stages leave brikToolBlocking absent, in which
        # case we default to true (legacy semantic: every failing entry
        # counts).
        # Note: jq `// true` would treat an explicit `false` value as
        # missing and fall through to true. Compare against != false so
        # absent/null/true all keep their entries (legacy semantic).
        | ($fail | map(select((.properties.brikToolBlocking != false) and
                              ((.properties.brikFixClassification // "unknown") == "has_fix"))) | length) as $failing_has_fix
        | ($fail | map(select((.properties.brikToolBlocking != false) and
                              ((.properties.brikFixClassification // "unknown") == "no_fix")))  | length) as $failing_no_fix
        | ($results | map(select(((.suppressions // []) | length) > 0))) as $ign
        | (
            $ign
            | map(.suppressions[0].properties.brikSource // "tool_native")
            | reduce .[] as $src ({}; .[$src] = (.[$src] // 0) + 1)
          ) as $by_source
        | (
            $ign
            | map(severity_of_result(.; $sarif))
            | reduce .[] as $s ({"critical":0, "high":0, "medium":0, "low":0, "info":0};
                                .[$s] += 1)
          ) as $ign_by_sev
        | {
            failing: { total: $failing_total, has_fix: $failing_has_fix, no_fix: $failing_no_fix },
            ignored: { total: ($ign | length), by_source: $by_source, by_severity: $ign_by_sev }
          }
    ' "$sarif_path" 2>/dev/null || printf '{"failing":{"total":0,"has_fix":0,"no_fix":0},"ignored":{"total":0,"by_source":{},"by_severity":{"critical":0,"high":0,"medium":0,"low":0,"info":0}}}')"
    # KCOV_EXCL_STOP

    local findings_obj
    findings_obj="$(jq -nc \
        --argjson total       "$total" \
        --argjson by_severity "$by_severity" \
        --argjson cwe         "$cwe" \
        --argjson v2          "$v2_stats" \
        '{total: $total, by_severity: $by_severity, cwe: $cwe} + $v2')"
    report.record_object "$stage" "business" "findings" "$findings_obj" 2>/dev/null || true

    local rel_path="$sarif_path"
    if [[ -n "${BRIK_WORKSPACE:-}" && "$sarif_path" == "${BRIK_WORKSPACE}/"* ]]; then
        rel_path="${sarif_path#"${BRIK_WORKSPACE}/"}"
    fi
    # Strip a leading ./ so callers that constructed sarif_path as
    # "${BRIK_WORKSPACE:-.}/<rel>" with BRIK_WORKSPACE unset still record
    # the same workspace-relative form as the legacy _sast._record_business.
    rel_path="${rel_path#./}"
    local report_obj
    report_obj="$(jq -nc --arg path "$rel_path" '{format: "sarif", path: $path}')"
    report.record_object "$stage" "business" "report" "$report_obj" 2>/dev/null || true
}

# Merge per-stage SARIF documents into a single pipeline-level
# brik-artifacts/aggregate.sarif. Walks every
# subdirectory of brik-artifacts/ and picks one source SARIF per stage:
#
#   1. findings.sarif (post-policy, preferred) -- the document the policy
#      gate already annotated, so the aggregate inherits the suppressions.
#   2. otherwise the first <tool>.sarif we find -- raw tool output, used
#      when the stage runs in pre-aggregation compatibility mode.
#
# Both cases preserve runs[] verbatim so consumers (Jenkins Warnings NG,
# GitLab Ultimate overlay, gl-sast-report exporter) keep identifying the
# source tool via tool.driver.name.
#
# When no source SARIF exists, an empty but well-formed aggregate is
# written so CI artifact uploads never warn about a missing file.
#
# Args:
#   $1 workspace (optional) -- defaults to BRIK_WORKSPACE then ".".
findings.merge_pipeline() {
    local workspace="${1:-${BRIK_WORKSPACE:-.}}"
    local artifacts="${workspace}/brik-artifacts"
    local out="${artifacts}/aggregate.sarif"

    if ! command -v jq >/dev/null 2>&1; then
        printf 'findings.merge_pipeline: jq is required\n' >&2
        return "$BRIK_EXIT_MISSING_DEP"
    fi
    if [[ ! -d "$artifacts" ]]; then
        printf 'findings.merge_pipeline: no brik-artifacts directory: %s\n' "$artifacts" >&2
        return "$BRIK_EXIT_IO_FAILURE"
    fi

    local sarif_files=()
    local stage_dir s
    for stage_dir in "$artifacts"/*/; do
        [[ -d "$stage_dir" ]] || continue
        # Skip the aggregate's own directory layout markers.
        if [[ -f "${stage_dir}findings.sarif" ]]; then
            sarif_files+=("${stage_dir}findings.sarif")
            continue
        fi
        for s in "$stage_dir"*.sarif; do
            [[ -f "$s" ]] || continue
            # Skip aggregate.sarif if a previous run wrote it inside a stage
            # subdir by mistake; the canonical aggregate lives one level up.
            [[ "$(basename "$s")" == "aggregate.sarif" ]] && continue
            sarif_files+=("$s")
            break
        done
    done

    mkdir -p "$artifacts" || {
        printf 'findings.merge_pipeline: cannot create %s\n' "$artifacts" >&2
        return "$BRIK_EXIT_IO_FAILURE"
    }

    local tmp
    tmp="$(mktemp "${out}.XXXXXX")" || return "$BRIK_EXIT_IO_FAILURE"

    if [[ ${#sarif_files[@]} -eq 0 ]]; then
        # Atomic empty-aggregate write so a disk-full / read-only mount
        # surfaces as IO_FAILURE instead of silently producing a missing
        # file (jq exits 0 even when its stdout redirect fails).
        # KCOV_EXCL_START -- inline jq script body, not bash code
        if ! jq -n '{
            "$schema": "https://json.schemastore.org/sarif-2.1.0.json",
            version: "2.1.0",
            runs: []
        }' > "$tmp"; then
            rm -f "$tmp"
            printf 'findings.merge_pipeline: jq init failed\n' >&2
            return "$BRIK_EXIT_IO_FAILURE"
        fi
        # KCOV_EXCL_STOP
        mv "$tmp" "$out" || {
            rm -f "$tmp"
            printf 'findings.merge_pipeline: cannot write %s\n' "$out" >&2
            return "$BRIK_EXIT_IO_FAILURE"
        }
        return 0
    fi

    # Slurp every source SARIF, then concatenate their runs[] entries.
    # Multiple runs[] per file (rare but valid SARIF) are preserved.
    # KCOV_EXCL_START -- inline jq script body, not bash code
    if ! jq -s '
        {
            "$schema": "https://json.schemastore.org/sarif-2.1.0.json",
            version: "2.1.0",
            runs: [ .[] | (.runs // [])[] ]
        }
    ' "${sarif_files[@]}" > "$tmp"; then
        rm -f "$tmp"
        printf 'findings.merge_pipeline: jq merge failed\n' >&2
        return "$BRIK_EXIT_IO_FAILURE"
    fi
    # KCOV_EXCL_STOP

    mv "$tmp" "$out" || {
        rm -f "$tmp"
        printf 'findings.merge_pipeline: cannot write %s\n' "$out" >&2
        return "$BRIK_EXIT_IO_FAILURE"
    }
    return 0
}
