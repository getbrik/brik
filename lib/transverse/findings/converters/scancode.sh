#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# @module transverse.findings.converters.scancode
# @requires jq
# @description scancode-toolkit JSON -> SARIF 2.1.0 converter (chantier 20260508 P5).
#   scancode --json-pp emits a wrapper with files[]:
#     {
#       "headers": [...],
#       "files": [
#         {
#           "path": "src/foo.py",
#           "type": "file",
#           "license_detections": [
#             {
#               "license_expression": "gpl-3.0-only",
#               "matches": [
#                 { "score": 100, "start_line": 1, "end_line": 1,
#                   "license_expression": "gpl-3.0-only", "rule_identifier": "..." }
#               ]
#             }
#           ]
#         }
#       ]
#     }
#
#   License findings are informational by default (level=note). Org policy
#   in P3 turns deny-listed licenses into failing findings via the
#   policy.org.cve-allowlist mechanism on the post-policy SARIF.

# Guard against double-sourcing.
[[ -n "${_BRIK_MODULE_TRANSVERSE_FINDINGS_CONVERTERS_SCANCODE_LOADED:-}" ]] && return 0
_BRIK_MODULE_TRANSVERSE_FINDINGS_CONVERTERS_SCANCODE_LOADED=1

findings.converters.scancode.to_sarif() {
    if [[ $# -lt 2 ]]; then
        printf 'findings.converters.scancode.to_sarif: missing arguments (input output)\n' >&2
        return "${BRIK_EXIT_INVALID_INPUT:-2}"
    fi
    local input="$1" output="$2"

    if ! command -v jq >/dev/null 2>&1; then
        printf 'findings.converters.scancode.to_sarif: jq is required\n' >&2
        return "${BRIK_EXIT_MISSING_DEP:-3}"
    fi

    local tmp
    tmp="$(mktemp "${output}.XXXXXX")" || return "${BRIK_EXIT_IO_FAILURE:-6}"

    # KCOV_EXCL_START -- jq script body is not bash code.
    if ! jq '
        # Walk every (file, license_detection, match) triple. Each match
        # becomes one SARIF result so consumers can locate the license
        # text precisely. When a license_detection has zero matches we
        # still emit one result anchored at line 1 of the file.
        def expand:
          ((.files // []) | map(select(.type == "file"))) as $files
          | [
              $files[]
              | . as $f
              | (.license_detections // [])[]
              | . as $d
              | (($d.matches // []) | (if length == 0
                   then [{ start_line: 1, end_line: 1 }]
                   else . end))[]
              | {
                  ruleId:  ($d.license_expression // "license"),
                  level:   "note",
                  message: { text: ("Detected license: " + ($d.license_expression // "unknown")
                                   + " in " + ($f.path // "")) },
                  locations: [{
                    physicalLocation: {
                      artifactLocation: { uri: ($f.path // "") },
                      region: {
                        startLine: (.start_line // 1),
                        endLine:   (.end_line // (.start_line // 1))
                      }
                    }
                  }],
                  properties: {
                    "security-severity": "1.0",
                    license_expression: ($d.license_expression // ""),
                    score:              (.score // 0)
                  }
                }
            ];

        expand as $results
        | ($results | map(.ruleId) | unique
          | map({
              id: .,
              shortDescription: { text: . },
              defaultConfiguration: { level: "note" },
              properties: { "security-severity": "1.0" }
            })) as $rules
        | {
            "$schema": "https://json.schemastore.org/sarif-2.1.0.json",
            version: "2.1.0",
            runs: [{
              tool: {
                driver: {
                  name: "scancode",
                  informationUri: "https://github.com/aboutcode-org/scancode-toolkit",
                  rules: $rules
                }
              },
              results: $results
            }]
          }
    ' "$input" > "$tmp"; then
        rm -f "$tmp"
        printf 'findings.converters.scancode.to_sarif: jq filter failed\n' >&2
        return "${BRIK_EXIT_IO_FAILURE:-6}"
    fi
    # KCOV_EXCL_STOP

    mv "$tmp" "$output" || {
        rm -f "$tmp"
        printf 'findings.converters.scancode.to_sarif: cannot write %s\n' "$output" >&2
        return "${BRIK_EXIT_IO_FAILURE:-6}"
    }
    return 0
}
