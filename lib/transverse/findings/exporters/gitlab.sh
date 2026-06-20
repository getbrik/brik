#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# @module transverse.findings.exporters.gitlab
# @requires jq
# @description SARIF -> GitLab gl-sast-report.json exporter.
#   Converts the pipeline-level aggregate SARIF (or any SARIF document) into
#   the gl-sast-report.json v15 schema consumed by non-Ultimate GitLab MR
#   widgets. Ultimate instances surface SARIF directly via the SARIF overlay
#   so this exporter is only needed where Ultimate is unavailable.
#
#   Mapping summary:
#     - One vulnerability per (run, result) pair.
#     - severity:    derived from rule.properties.security-severity (CVSS)
#                    when present, else from result.level.
#     - cve:         when ruleId matches CVE-XXXX-N.. it lands in .cve.
#     - identifiers: CWE entries from rule.properties.tags ("CWE-NN") plus a
#                    catch-all { type: "<tool>_rule_id", value: ruleId }.
#     - location:    artifactLocation.uri + region.start_line/end_line.
#     - id:          partialFingerprints.primaryLocationLineHash (when set)
#                    else stable hash of (tool|ruleId|file|line) so successive
#                    runs produce the same id for the same finding.

# Guard against double-sourcing.
[[ -n "${_BRIK_MODULE_TRANSVERSE_FINDINGS_EXPORTERS_GITLAB_LOADED:-}" ]] && return 0
_BRIK_MODULE_TRANSVERSE_FINDINGS_EXPORTERS_GITLAB_LOADED=1

# Convert a SARIF document into a GitLab gl-sast-report.json.
# Args:
#   $1 input  -- SARIF 2.1.0 path (typically brik-artifacts/aggregate.sarif).
#   $2 output -- target gl-sast-report.json path.
findings.exporters.gitlab.from_sarif() {
    if [[ $# -lt 2 ]]; then
        printf 'findings.exporters.gitlab.from_sarif: missing arguments (input output)\n' >&2
        return "$BRIK_EXIT_INVALID_INPUT"
    fi
    local input="$1" output="$2"

    if ! command -v jq >/dev/null 2>&1; then
        printf 'findings.exporters.gitlab.from_sarif: jq is required\n' >&2
        return "$BRIK_EXIT_MISSING_DEP"
    fi
    if [[ ! -f "$input" ]]; then
        printf 'findings.exporters.gitlab.from_sarif: input not found: %s\n' "$input" >&2
        return "$BRIK_EXIT_IO_FAILURE"
    fi

    local out_dir
    out_dir="$(dirname "$output")"
    mkdir -p "$out_dir" || {
        printf 'findings.exporters.gitlab.from_sarif: cannot create %s\n' "$out_dir" >&2
        return "$BRIK_EXIT_IO_FAILURE"
    }

    local now
    now="$(date -u +"%Y-%m-%dT%H:%M:%S")"
    local brik_version="${BRIK_VERSION:-0.0.0}"

    local tmp
    tmp="$(mktemp "${output}.XXXXXX")" || return "$BRIK_EXIT_IO_FAILURE"

    # KCOV_EXCL_START -- jq script body is not bash code.
    if ! jq --arg now "$now" --arg brik_version "$brik_version" '
        def cvss_to_sev(s):
          ((s | tonumber?) // -1) as $v
          | if   $v >= 9.0 then "Critical"
            elif $v >= 7.0 then "High"
            elif $v >= 4.0 then "Medium"
            elif $v > 0    then "Low"
            elif $v == 0   then "Info"
            else "Unknown" end;

        def level_to_sev(lvl):
          if   lvl == "error"   then "High"
          elif lvl == "warning" then "Medium"
          elif lvl == "note"    then "Low"
          elif lvl == "none"    then "Info"
          else "Unknown" end;

        # Build a per-run rules-by-id index so we can resolve severity and
        # CWE tags out of tool.driver.rules when the result is sparse
        # (grype 0.111+ behaviour).
        def rules_index($run):
          ($run.tool.driver.rules // [])
          | map({key: (.id // ""), value: .})
          | from_entries;

        def rule_for($r; $idx):
          ($r.ruleId // "") as $rid
          | if $rid == "" then null else ($idx[$rid] // null) end;

        def severity_of($r; $idx):
          rule_for($r; $idx) as $rule
          | (
              ($r.properties["security-severity"]
               // ($rule.properties["security-severity"] // null))
            ) as $cvss
          | if   $cvss != null            then cvss_to_sev($cvss)
            elif ($r.level // null) != null then level_to_sev($r.level)
            elif ($rule.defaultConfiguration.level // null) != null
                                            then level_to_sev($rule.defaultConfiguration.level)
            else "Unknown" end;

        def cwe_identifiers($rule):
          (($rule.properties.tags // []) // [])
          | map(select(type == "string" and (. | test("^CWE-[0-9]+$"))))
          | map({
              type:  "cwe",
              name:  .,
              value: (. | sub("^CWE-"; "")),
              url:   ("https://cwe.mitre.org/data/definitions/" + (. | sub("^CWE-"; "")) + ".html")
            });

        def primary_location($r):
          ($r.locations // [])[0]?
          | (.physicalLocation // null) as $pl
          | if $pl == null then null
            else
              {
                file:       ($pl.artifactLocation.uri // ""),
                start_line: ($pl.region.startLine // null),
                end_line:   ($pl.region.endLine   // ($pl.region.startLine // null))
              }
            end;

        def is_cve($rid):
          ($rid // "") | test("^CVE-[0-9]{4}-[0-9]+");

        def vuln_id($r; $tool):
          ($r.partialFingerprints.primaryLocationLineHash // "") as $fp
          | if $fp != "" then $fp
            else
              ($r.locations[0].physicalLocation.artifactLocation.uri // "") as $f
              | ($r.locations[0].physicalLocation.region.startLine    // 0)  as $l
              | ($tool + "|" + ($r.ruleId // "rule") + "|" + $f + "|" + ($l|tostring))
            end;

        # Walk every (run, result) pair; skip results with non-empty
        # suppressions[] so the gl-sast-report only carries failing
        # findings (ignored entries land elsewhere via the SARIF overlay).
        [
          .runs[]?
          | rules_index(.) as $idx
          | (.tool.driver.name // "brik") as $tool
          | (.results // [])[]
          | select(((.suppressions // []) | length) == 0)
          | . as $r
          | rule_for($r; $idx) as $rule
          | {
              id:   vuln_id($r; $tool),
              name: ($rule.shortDescription.text // $r.ruleId // "Finding"),
              description: ($r.message.text // ""),
              severity:    severity_of($r; $idx),
              cve:         (if is_cve($r.ruleId) then $r.ruleId else null end),
              location:    primary_location($r),
              identifiers: (
                cwe_identifiers($rule // {})
                + [{
                    type:  ($tool + "_rule_id"),
                    name:  ($r.ruleId // ""),
                    value: ($r.ruleId // "")
                  }]
              )
            }
          | with_entries(select(.value != null))
        ] as $vulns
        | {
            version: "15.0.0",
            scan: {
              scanner: {
                id: "brik",
                name: "Brik",
                vendor: { name: "Brik" },
                version: $brik_version
              },
              type: "sast",
              start_time: $now,
              end_time:   $now,
              status:     "success"
            },
            vulnerabilities: $vulns
          }
    ' "$input" > "$tmp"; then
        rm -f "$tmp"
        printf 'findings.exporters.gitlab.from_sarif: jq filter failed\n' >&2
        return "$BRIK_EXIT_IO_FAILURE"
    fi
    # KCOV_EXCL_STOP

    mv "$tmp" "$output" || {
        rm -f "$tmp"
        printf 'findings.exporters.gitlab.from_sarif: cannot write %s\n' "$output" >&2
        return "$BRIK_EXIT_IO_FAILURE"
    }
    return 0
}
