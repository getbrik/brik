#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# @module transverse.findings
# @requires jq, transverse.sarif
# @description Unified findings management public API. Provides the
#   ingest -> apply policy -> aggregate -> merge pipeline that every
#   stage producing findings (lint, sast, scan/*, container_scan, ...)
#   plugs into. SARIF 2.1.0 is the pivot format; non-SARIF tools
#   converge through converters/ (P5).
#
#   P1 surface:
#     - findings.from_sarif    : validate a tool's SARIF report.
#     - findings.apply_policy  : passthrough copy (P2 will add presets;
#                                P3 will layer the org allowlist).
#     - findings.aggregate     : record business.findings + business.report
#                                in the pipeline backend (factored from
#                                the legacy _sast._record_business).
#     - findings.from_json     : stub -- per-tool converters land in P5.
#     - findings.expiring_soon : no-op until the org_policy loader (P3).
#     - findings.merge_pipeline: stub -- pipeline-level SARIF agg lands in P6.

# Guard against double-sourcing.
[[ -n "${_BRIK_MODULE_TRANSVERSE_FINDINGS_LOADED:-}" ]] && return 0
_BRIK_MODULE_TRANSVERSE_FINDINGS_LOADED=1

# Source the SARIF helpers when the host has not loaded them already.
# Keeping this defensive lets callers Include findings.sh in isolation
# (e.g. unit tests) without forcing them to know the dependency order.
if [[ -z "${_BRIK_TRANSVERSE_SARIF_LOADED:-}" ]]; then
    if [[ -f "${BASH_SOURCE[0]%/*}/sarif.sh" ]]; then
        # shellcheck source=sarif.sh
        . "${BASH_SOURCE[0]%/*}/sarif.sh"
    fi
fi

# Validate a tool's SARIF report. Entry point of the ingest stage of the
# pipeline; downstream callers (apply_policy, aggregate) assume the file
# has already been vetted.
#
# Args:
#   $1 stage     -- stage producing the report (e.g. sast, container_scan).
#   $2 sarif_path -- absolute or workspace-relative path to the SARIF file.
#
# Returns:
#   0                          on a structurally valid SARIF 2.1.0.
#   BRIK_EXIT_INVALID_INPUT(2) on missing or empty arguments.
#   BRIK_EXIT_IO_FAILURE(6)    when the file does not exist.
#   BRIK_EXIT_CONFIG_ERROR(7)  when the file is not a valid SARIF document.
#   BRIK_EXIT_MISSING_DEP(3)   when transverse.sarif is unavailable.
findings.from_sarif() {
    if [[ $# -lt 2 ]]; then
        printf 'findings.from_sarif: missing arguments (expected: stage sarif_path)\n' >&2
        return "${BRIK_EXIT_INVALID_INPUT:-2}"
    fi
    local stage="$1" sarif_path="$2"
    if [[ -z "$stage" ]]; then
        printf 'findings.from_sarif: stage must not be empty\n' >&2
        return "${BRIK_EXIT_INVALID_INPUT:-2}"
    fi
    if [[ ! -f "$sarif_path" ]]; then
        printf 'findings.from_sarif: SARIF file not found: %s\n' "$sarif_path" >&2
        return "${BRIK_EXIT_IO_FAILURE:-6}"
    fi
    if ! declare -f sarif.is_valid >/dev/null 2>&1; then
        printf 'findings.from_sarif: transverse.sarif module not loaded\n' >&2
        return "${BRIK_EXIT_MISSING_DEP:-3}"
    fi
    if ! sarif.is_valid "$sarif_path"; then
        printf 'findings.from_sarif: invalid SARIF document: %s\n' "$sarif_path" >&2
        return "${BRIK_EXIT_CONFIG_ERROR:-7}"
    fi
    return 0
}

# Apply the active built-in policy preset to a SARIF document. The preset
# is read from BRIK_QUALITY_FINDINGS_POLICY (default pragmatic); the
# severity floor is read from BRIK_SECURITY_SEVERITY_THRESHOLD (default
# high). P3 will layer the organization allowlist from BRIK_POLICY_URL on
# top of the preset output.
#
# Preset matrix (chantier 20260508 A2):
#   pragmatic  : ignore severity<floor (below-severity), then fixState=
#                not-fixed (no-upstream-fix), then fixState=wont-fix
#                (vendor-wont-fix); fail the rest.
#   strict     : ignore severity<floor; fail everything else (no-fix included).
#   permissive : effective floor is critical; ignore severity<critical
#                (below-severity), then not-fixed/wont-fix; fail only
#                critical with an upstream fix.
#
# In every preset, results that already carry a non-empty suppressions[]
# (tool-native allowlist, inline annotation, ...) pass through untouched
# so the SARIF natif owner keeps full control of pre-existing decisions.
#
# Annotations appended on policy-ignored results:
#   result.suppressions[+] = {
#     kind: "external",
#     justification: "Brik policy: <reason>",
#     properties: { brikSource: "policy.built-in.<reason>" }
#   }
# Reason is one of: below-severity, no-upstream-fix, vendor-wont-fix.
#
# Severity resolution mirrors transverse.sarif: prefers
# properties.security-severity (CVSS string) when present, else falls
# back to result.level. fixState defaults to "fixed" when absent so tools
# without grype-style fix metadata (semgrep, eslint, ...) never qualify
# for the no-fix tags.
#
# Args:
#   $1 sarif_in  -- input SARIF (typically the tool's native output).
#   $2 sarif_out -- output path (typically brik-artifacts/<stage>/findings.sarif).
findings.apply_policy() {
    if [[ $# -lt 2 ]]; then
        printf 'findings.apply_policy: missing arguments (expected: sarif_in sarif_out)\n' >&2
        return "${BRIK_EXIT_INVALID_INPUT:-2}"
    fi
    local sarif_in="$1" sarif_out="$2"
    if [[ ! -f "$sarif_in" ]]; then
        printf 'findings.apply_policy: input not found: %s\n' "$sarif_in" >&2
        return "${BRIK_EXIT_IO_FAILURE:-6}"
    fi

    local preset="${BRIK_QUALITY_FINDINGS_POLICY:-pragmatic}"
    case "$preset" in
        pragmatic|strict|permissive) ;;
        *)
            printf 'findings.apply_policy: unknown preset %s (expected pragmatic|strict|permissive)\n' "$preset" >&2
            return "${BRIK_EXIT_CONFIG_ERROR:-7}"
            ;;
    esac

    local floor_raw="${BRIK_SECURITY_SEVERITY_THRESHOLD:-high}"
    local floor="${floor_raw,,}"
    local floor_rank
    case "$floor" in
        info)     floor_rank=0 ;;
        low)      floor_rank=1 ;;
        medium)   floor_rank=2 ;;
        high)     floor_rank=3 ;;
        critical) floor_rank=4 ;;
        *)
            printf 'findings.apply_policy: unknown severity threshold %s (expected info|low|medium|high|critical)\n' "$floor_raw" >&2
            return "${BRIK_EXIT_CONFIG_ERROR:-7}"
            ;;
    esac

    local out_dir
    out_dir="$(dirname "$sarif_out")"
    mkdir -p "$out_dir" || {
        printf 'findings.apply_policy: cannot create output directory: %s\n' "$out_dir" >&2
        return "${BRIK_EXIT_IO_FAILURE:-6}"
    }

    if ! command -v jq >/dev/null 2>&1; then
        printf 'findings.apply_policy: jq not on PATH\n' >&2
        return "${BRIK_EXIT_MISSING_DEP:-3}"
    fi

    local tmp
    tmp="$(mktemp "${sarif_out}.XXXXXX")" || return "${BRIK_EXIT_IO_FAILURE:-6}"

    # KCOV_EXCL_START -- jq script body is not bash code
    jq --arg preset "$preset" --argjson floor_rank "$floor_rank" '
        def severity_rank(s):
          if   s == "critical" then 4
          elif s == "high"     then 3
          elif s == "medium"   then 2
          elif s == "low"      then 1
          else 0 end;

        def cvss_bucket(s):
          # tonumber? swallows non-numeric CVSS strings (truncated, garbage)
          # so an upstream-malformed properties.security-severity downgrades
          # to info instead of crashing the entire jq filter.
          ((s | tonumber?) // -1) as $v
          | if   $v >= 9.0 then "critical"
            elif $v >= 7.0 then "high"
            elif $v >= 4.0 then "medium"
            elif $v > 0    then "low"
            else "info" end;

        def level_bucket(lvl):
          if   lvl == "error"   then "high"
          elif lvl == "warning" then "medium"
          elif lvl == "note"    then "low"
          else "info" end;

        def severity_of_result($r):
          ($r.properties["security-severity"] // null) as $cvss
          | if   $cvss != null            then cvss_bucket($cvss)
            elif ($r.level // null) != null then level_bucket($r.level)
            else "info" end;

        # Classify a result. Returns a reason string when the policy ignores
        # the finding, or null when the finding stays failing (or is already
        # suppressed natively and must pass through).
        def classify($r):
          (($r.suppressions // []) | length) as $sup_len
          | if $sup_len > 0 then null
            else
              severity_of_result($r) as $sev
              | severity_rank($sev) as $rank
              | ($r.properties.fixState // "fixed") as $fix
              | if $preset == "strict" then
                  if $rank < $floor_rank then "below-severity" else null end
                elif $preset == "permissive" then
                  if   $rank < 4               then "below-severity"
                  elif $fix == "not-fixed"     then "no-upstream-fix"
                  elif $fix == "wont-fix"      then "vendor-wont-fix"
                  else null end
                else
                  if   $rank < $floor_rank then "below-severity"
                  elif $fix == "not-fixed"     then "no-upstream-fix"
                  elif $fix == "wont-fix"      then "vendor-wont-fix"
                  else null end
                end
            end;

        def annotate($r):
          classify($r) as $reason
          | if $reason == null then $r
            else $r + {
              suppressions: (
                ($r.suppressions // []) + [{
                  kind: "external",
                  justification: ("Brik policy: " + $reason),
                  properties: { brikSource: ("policy.built-in." + $reason) }
                }]
              )
            } end;

        .runs[0].results = ((.runs[0].results // []) | map(annotate(.)))
    ' "$sarif_in" > "$tmp" || {
        rm -f "$tmp"
        printf 'findings.apply_policy: jq processing failed for %s\n' "$sarif_in" >&2
        return "${BRIK_EXIT_IO_FAILURE:-6}"
    }
    # KCOV_EXCL_STOP

    mv "$tmp" "$sarif_out" || {
        rm -f "$tmp"
        printf 'findings.apply_policy: cannot write %s\n' "$sarif_out" >&2
        return "${BRIK_EXIT_IO_FAILURE:-6}"
    }
    return 0
}

# Record a stage's SARIF report into business.findings + business.report
# on the pipeline backend (aggregate-report.json). Idempotent: re-recording
# upserts the same stage entry.
#
# Recorded shape (L4 v1, preserved verbatim for backward compatibility with
# Jenkins Warnings NG and the GitLab Ultimate SARIF overlay; L4 v2 adds
# failing/ignored/expiring_soon on top of these in P2/P3):
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
        return "${BRIK_EXIT_INVALID_INPUT:-2}"
    fi
    local stage="$1" sarif_path="$2"
    if [[ -z "$stage" ]]; then
        printf 'findings.aggregate: stage must not be empty\n' >&2
        return "${BRIK_EXIT_INVALID_INPUT:-2}"
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

    # L4 v2 enrichment (chantier 20260508 P2): failing vs ignored split,
    # ignored breakdown by brikSource and by severity. Counts are derived
    # from result.suppressions[]: a result with at least one suppression
    # entry counts as ignored; the brikSource on the first entry decides
    # the source bucket (defaulting to tool_native for natively-suppressed
    # results that lack our properties.brikSource annotation).
    local v2_stats
    # KCOV_EXCL_START -- jq script body is not bash code
    v2_stats="$(jq -c '
        def cvss_bucket(s):
          # tonumber? swallows non-numeric CVSS strings (truncated, garbage)
          # so an upstream-malformed properties.security-severity downgrades
          # to info instead of crashing the entire jq filter.
          ((s | tonumber?) // -1) as $v
          | if   $v >= 9.0 then "critical"
            elif $v >= 7.0 then "high"
            elif $v >= 4.0 then "medium"
            elif $v > 0    then "low"
            else "info" end;

        def level_bucket(lvl):
          if   lvl == "error"   then "high"
          elif lvl == "warning" then "medium"
          elif lvl == "note"    then "low"
          else "info" end;

        def severity_of_result($r):
          ($r.properties["security-severity"] // null) as $cvss
          | if   $cvss != null            then cvss_bucket($cvss)
            elif ($r.level // null) != null then level_bucket($r.level)
            else "info" end;

        (.runs[0].results // []) as $results
        | ($results | map(select(((.suppressions // []) | length) == 0)) | length) as $failing
        | ($results | map(select(((.suppressions // []) | length) > 0))) as $ign
        | (
            $ign
            | map(.suppressions[0].properties.brikSource // "tool_native")
            | reduce .[] as $src ({}; .[$src] = (.[$src] // 0) + 1)
          ) as $by_source
        | (
            $ign
            | map(severity_of_result(.))
            | reduce .[] as $s ({"critical":0, "high":0, "medium":0, "low":0, "info":0};
                                .[$s] += 1)
          ) as $ign_by_sev
        | {
            failing: $failing,
            ignored: { total: ($ign | length), by_source: $by_source, by_severity: $ign_by_sev }
          }
    ' "$sarif_path" 2>/dev/null || printf '{"failing":0,"ignored":{"total":0,"by_source":{},"by_severity":{"critical":0,"high":0,"medium":0,"low":0,"info":0}}}')"
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

# Convert a non-SARIF tool output to SARIF via a named converter. Real
# implementations land per-tool in transverse/findings/converters/ during
# P5 (ruff, clippy, trufflehog, dockle, bandit, scancode, junit-xml). The
# stub keeps the public API addressable and fails loudly so callers know
# the conversion is not yet wired up.
findings.from_json() {
    printf 'findings.from_json: not implemented in P1 (scheduled for P5 converters phase)\n' >&2
    return "${BRIK_EXIT_FAILURE:-1}"
}

# Surface allowlist entries whose expires field falls within
# BRIK_FINDINGS_EXPIRING_SOON_DAYS (default 30). Real implementation
# depends on the org_policy loader (P3); P1 returns 0 so callers (init
# stage) can wire the call without needing to gate behind feature flags.
findings.expiring_soon() {
    return 0
}

# Merge per-stage findings.sarif documents into a single pipeline-level
# brik-artifacts/aggregate.sarif. Real implementation lands in P6 and
# powers the GitLab Ultimate overlay, Jenkins Warnings NG, and the
# generic GitLab non-Ultimate exporter (gl-sast-report.json).
findings.merge_pipeline() {
    printf 'findings.merge_pipeline: not implemented in P1 (scheduled for P6 pipeline aggregation phase)\n' >&2
    return "${BRIK_EXIT_FAILURE:-1}"
}
