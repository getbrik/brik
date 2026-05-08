#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# @module transverse.findings.converters.dockle
# @requires jq
# @description dockle JSON -> SARIF 2.1.0 converter (chantier 20260508 P5).
#   dockle -f json emits a wrapper object:
#     {
#       "summary": { "fatal": 0, "warn": 1, "info": 0, "skip": 0, "pass": 11 },
#       "details": [
#         {
#           "code":  "CIS-DI-0001",
#           "title": "Create a user for the container",
#           "level": "WARN",
#           "alerts": ["Last user should not be root"]
#         }
#       ]
#     }
#
#   Level mapping (dockle -> SARIF level + Brik bucket):
#     FATAL -> error    (high)
#     WARN  -> warning  (medium)
#     INFO  -> note     (low)
#     SKIP  -> note     (low)
#     PASS  -> omitted  (no SARIF result)

# Guard against double-sourcing.
[[ -n "${_BRIK_MODULE_TRANSVERSE_FINDINGS_CONVERTERS_DOCKLE_LOADED:-}" ]] && return 0
_BRIK_MODULE_TRANSVERSE_FINDINGS_CONVERTERS_DOCKLE_LOADED=1

findings.converters.dockle.to_sarif() {
    if [[ $# -lt 2 ]]; then
        printf 'findings.converters.dockle.to_sarif: missing arguments (input output)\n' >&2
        return "${BRIK_EXIT_INVALID_INPUT:-2}"
    fi
    local input="$1" output="$2"

    if ! command -v jq >/dev/null 2>&1; then
        printf 'findings.converters.dockle.to_sarif: jq is required\n' >&2
        return "${BRIK_EXIT_MISSING_DEP:-3}"
    fi

    local tmp
    tmp="$(mktemp "${output}.XXXXXX")" || return "${BRIK_EXIT_IO_FAILURE:-6}"

    # KCOV_EXCL_START -- jq script body is not bash code.
    if ! jq '
        def level_map(s):
          (s // "" | ascii_upcase) as $u
          | if   $u == "FATAL" then "error"
            elif $u == "WARN"  then "warning"
            elif $u == "INFO"  then "note"
            elif $u == "SKIP"  then "note"
            else null end;

        def cvss_map(s):
          (s // "" | ascii_upcase) as $u
          | if   $u == "FATAL" then "8.0"
            elif $u == "WARN"  then "5.5"
            elif $u == "INFO"  then "3.0"
            elif $u == "SKIP"  then "3.0"
            else "3.0" end;

        # Each alert string becomes its own SARIF result so consumers can
        # surface them individually rather than collapsing into a list.
        def expand_details:
          (.details // [])
          | map(
              . as $d
              | level_map($d.level) as $lvl
              | if $lvl == null then empty else
                  (($d.alerts // []) | (if length == 0 then [""] else . end))
                  | map({
                      ruleId:  ($d.code // "dockle"),
                      level:   $lvl,
                      message: { text: (if . == "" then ($d.title // "dockle finding") else . end) },
                      properties: {
                        "security-severity": cvss_map($d.level),
                        title: ($d.title // "")
                      }
                    })
                end
            )
          | add // [];

        expand_details as $results
        | (
            (.details // [])
            | map(select(level_map(.level) != null))
            | group_by(.code // "dockle")
            | map(
                .[0] as $first
                | {
                    id:    ($first.code // "dockle"),
                    name:  ($first.code // "dockle"),
                    shortDescription: { text: ($first.title // ($first.code // "dockle")) },
                    defaultConfiguration: { level: level_map($first.level) },
                    properties: { "security-severity": cvss_map($first.level) }
                  }
              )
          ) as $rules
        | {
            "$schema": "https://json.schemastore.org/sarif-2.1.0.json",
            version: "2.1.0",
            runs: [{
              tool: {
                driver: {
                  name: "dockle",
                  informationUri: "https://github.com/goodwithtech/dockle",
                  rules: $rules
                }
              },
              results: $results
            }]
          }
    ' "$input" > "$tmp"; then
        rm -f "$tmp"
        printf 'findings.converters.dockle.to_sarif: jq filter failed\n' >&2
        return "${BRIK_EXIT_IO_FAILURE:-6}"
    fi
    # KCOV_EXCL_STOP

    mv "$tmp" "$output" || {
        rm -f "$tmp"
        printf 'findings.converters.dockle.to_sarif: cannot write %s\n' "$output" >&2
        return "${BRIK_EXIT_IO_FAILURE:-6}"
    }
    return 0
}
