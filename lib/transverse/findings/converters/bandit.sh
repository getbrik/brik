#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# @module transverse.findings.converters.bandit
# @requires jq
# @description bandit JSON -> SARIF 2.1.0 converter.
#   bandit -f json emits a wrapper object:
#     {
#       "errors": [],
#       "metrics": {...},
#       "results": [
#         {
#           "code": "...",
#           "col_offset": 8, "end_col_offset": 12,
#           "filename": "./src/auth.py",
#           "issue_confidence": "MEDIUM",
#           "issue_cwe": { "id": 259, "link": "https://cwe.mitre.org/..." },
#           "issue_severity": "LOW",
#           "issue_text": "Possible hardcoded password: 'admin'",
#           "line_number": 5, "line_range": [5],
#           "more_info": "https://bandit.readthedocs.io/...",
#           "test_id": "B105",
#           "test_name": "hardcoded_password_string"
#         }
#       ]
#     }
#
#   Severity mapping (bandit -> SARIF level + Brik bucket):
#     HIGH   -> error    (Brik high)
#     MEDIUM -> warning  (Brik medium)
#     LOW    -> note     (Brik low)
#
#   CWE ids land in rule.properties.tags as "CWE-<id>" so the existing
#   sarif.extract_cwe pipeline picks them up unchanged.

# Guard against double-sourcing.
[[ -n "${_BRIK_MODULE_TRANSVERSE_FINDINGS_CONVERTERS_BANDIT_LOADED:-}" ]] && return 0
_BRIK_MODULE_TRANSVERSE_FINDINGS_CONVERTERS_BANDIT_LOADED=1

# Convert a bandit JSON report into SARIF 2.1.0.
# Args:
#   $1 input  -- bandit JSON file ({errors, metrics, results: [...]}).
#   $2 output -- target SARIF path.
findings.converters.bandit.to_sarif() {
    if [[ $# -lt 2 ]]; then
        printf 'findings.converters.bandit.to_sarif: missing arguments (input output)\n' >&2
        return "$BRIK_EXIT_INVALID_INPUT"
    fi
    local input="$1" output="$2"

    if ! command -v jq >/dev/null 2>&1; then
        printf 'findings.converters.bandit.to_sarif: jq is required\n' >&2
        return "$BRIK_EXIT_MISSING_DEP"
    fi

    local tmp
    tmp="$(mktemp "${output}.XXXXXX")" || return "$BRIK_EXIT_IO_FAILURE"

    # KCOV_EXCL_START -- jq script body is not bash code.
    if ! jq '
        def severity_to_level(s):
          (s // "" | ascii_upcase) as $u
          | if   $u == "HIGH"   then "error"
            elif $u == "MEDIUM" then "warning"
            elif $u == "LOW"    then "note"
            else "warning" end;

        # Approximate CVSS so the L4 v2 pipeline (severity_of_result in
        # findings.sh) can bucket bandit findings without a separate
        # severity ladder. Values fall in the middle of each Brik band.
        def severity_to_cvss(s):
          (s // "" | ascii_upcase) as $u
          | if   $u == "HIGH"   then "8.0"
            elif $u == "MEDIUM" then "5.5"
            elif $u == "LOW"    then "3.0"
            else "5.5" end;

        def cwe_tag($r):
          ($r.issue_cwe.id // null) as $id
          | if $id == null then [] else ["CWE-" + ($id | tostring)] end;

        def result($r):
          {
            ruleId:  ($r.test_id // "bandit"),
            level:   severity_to_level($r.issue_severity),
            message: { text: ($r.issue_text // "") },
            locations: [{
              physicalLocation: {
                artifactLocation: { uri: ($r.filename // "") },
                region: {
                  startLine:   ($r.line_number // 1),
                  startColumn: (($r.col_offset // 0) + 1),
                  endColumn:   (($r.end_col_offset // ($r.col_offset // 0)) + 1)
                }
              }
            }],
            properties: {
              "security-severity": severity_to_cvss($r.issue_severity),
              confidence:          ($r.issue_confidence // ""),
              testName:            ($r.test_name // ""),
              moreInfo:            ($r.more_info // "")
            }
          };

        ((.results // []) | map(result(.))) as $results
        | (
            (.results // [])
            | group_by(.test_id // "bandit")
            | map(
                .[0] as $first
                | {
                    id: ($first.test_id // "bandit"),
                    name: ($first.test_name // ""),
                    shortDescription: { text: ($first.test_name // ($first.test_id // "bandit")) },
                    helpUri: ($first.more_info // ""),
                    defaultConfiguration: { level: severity_to_level($first.issue_severity) },
                    properties: {
                      "security-severity": severity_to_cvss($first.issue_severity),
                      tags: cwe_tag($first)
                    }
                  }
              )
          ) as $rules
        | {
            "$schema": "https://json.schemastore.org/sarif-2.1.0.json",
            version: "2.1.0",
            runs: [{
              tool: {
                driver: {
                  name: "bandit",
                  informationUri: "https://bandit.readthedocs.io/",
                  rules: $rules
                }
              },
              results: $results
            }]
          }
    ' "$input" > "$tmp"; then
        rm -f "$tmp"
        printf 'findings.converters.bandit.to_sarif: jq filter failed\n' >&2
        return "$BRIK_EXIT_IO_FAILURE"
    fi
    # KCOV_EXCL_STOP

    mv "$tmp" "$output" || {
        rm -f "$tmp"
        printf 'findings.converters.bandit.to_sarif: cannot write %s\n' "$output" >&2
        return "$BRIK_EXIT_IO_FAILURE"
    }
    return 0
}
