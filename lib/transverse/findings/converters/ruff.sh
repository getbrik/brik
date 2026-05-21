#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# @module transverse.findings.converters.ruff
# @requires jq
# @description ruff JSON -> SARIF 2.1.0 converter (chantier 20260508 P5).
#   ruff's --output-format=json emits a top-level array of findings:
#     [
#       {
#         "code": "E501",
#         "url": "https://docs.astral.sh/ruff/rules/line-too-long",
#         "message": "Line too long (132 > 100)",
#         "fix": null,
#         "location":     { "row": 12, "column": 1 },
#         "end_location": { "row": 12, "column": 132 },
#         "filename": "src/foo.py",
#         "noqa_row": 12
#       },
#       ...
#     ]
#
#   Native SARIF support is available since ruff 0.6.0. This converter
#   stays as a fallback for environments that consume the JSON shape
#   (older versions, custom CI wrappers, ...) per chantier P5 #15.

# Guard against double-sourcing.
[[ -n "${_BRIK_MODULE_TRANSVERSE_FINDINGS_CONVERTERS_RUFF_LOADED:-}" ]] && return 0
_BRIK_MODULE_TRANSVERSE_FINDINGS_CONVERTERS_RUFF_LOADED=1

# Convert a ruff JSON report into SARIF 2.1.0.
# Args:
#   $1 input  -- ruff JSON file (top-level array of finding objects).
#   $2 output -- target SARIF path.
findings.converters.ruff.to_sarif() {
    if [[ $# -lt 2 ]]; then
        printf 'findings.converters.ruff.to_sarif: missing arguments (input output)\n' >&2
        return "$BRIK_EXIT_INVALID_INPUT"
    fi
    local input="$1" output="$2"

    if ! command -v jq >/dev/null 2>&1; then
        printf 'findings.converters.ruff.to_sarif: jq is required\n' >&2
        return "$BRIK_EXIT_MISSING_DEP"
    fi

    local tmp
    tmp="$(mktemp "${output}.XXXXXX")" || return "$BRIK_EXIT_IO_FAILURE"

    # KCOV_EXCL_START -- jq script body is not bash code.
    if ! jq '
        # Tolerate empty input (no findings) and the rare case where a
        # caller wraps the array in {"results": [...]}.
        def findings:
          if   . | type == "array"  then .
          elif (.results // null) | type == "array" then .results
          else [] end;

        def result($f):
          {
            ruleId:  ($f.code // "ruff"),
            level:   "warning",
            message: { text: ($f.message // "") },
            locations: [{
              physicalLocation: {
                artifactLocation: { uri: ($f.filename // "") },
                region: {
                  startLine:   ($f.location.row // 1),
                  startColumn: ($f.location.column // 1),
                  endLine:     ($f.end_location.row // ($f.location.row // 1)),
                  endColumn:   ($f.end_location.column // ($f.location.column // 1))
                }
              }
            }],
            properties: {
              code: ($f.code // ""),
              url:  ($f.url // ""),
              fixAvailable: (($f.fix // null) != null)
            }
          };

        (findings | map(result(.))) as $results
        | ($results | map(.ruleId) | unique
          | map({
              id: .,
              shortDescription: { text: . },
              defaultConfiguration: { level: "warning" }
            })) as $rules
        | {
            "$schema": "https://json.schemastore.org/sarif-2.1.0.json",
            version: "2.1.0",
            runs: [{
              tool: {
                driver: {
                  name: "ruff",
                  informationUri: "https://docs.astral.sh/ruff/",
                  rules: $rules
                }
              },
              results: $results
            }]
          }
    ' "$input" > "$tmp"; then
        rm -f "$tmp"
        printf 'findings.converters.ruff.to_sarif: jq filter failed\n' >&2
        return "$BRIK_EXIT_IO_FAILURE"
    fi
    # KCOV_EXCL_STOP

    mv "$tmp" "$output" || {
        rm -f "$tmp"
        printf 'findings.converters.ruff.to_sarif: cannot write %s\n' "$output" >&2
        return "$BRIK_EXIT_IO_FAILURE"
    }
    return 0
}
