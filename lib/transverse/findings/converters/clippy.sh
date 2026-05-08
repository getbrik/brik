#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# @module transverse.findings.converters.clippy
# @requires jq
# @description clippy NDJSON -> SARIF 2.1.0 converter (chantier 20260508 P5).
#   `cargo clippy --message-format=json` emits NDJSON. Diagnostics carry
#   reason="compiler-message"; we keep only those whose code starts with
#   "clippy::" so dependency warnings and pure rustc diagnostics stay out
#   of the lint stage report.
#
#   Per-line shape (relevant fields):
#     {
#       "reason": "compiler-message",
#       "message": {
#         "level": "warning",
#         "message": "unneeded `return` statement",
#         "code": { "code": "clippy::needless_return" },
#         "spans": [
#           { "file_name": "src/main.rs",
#             "line_start": 5, "line_end": 5,
#             "column_start": 1, "column_end": 30,
#             "is_primary": true }
#         ]
#       }
#     }
#
#   Level mapping (clippy/cargo -> SARIF level + Brik bucket):
#     error      -> error    (high)
#     warning    -> warning  (medium)
#     note|help  -> note     (low)

# Guard against double-sourcing.
[[ -n "${_BRIK_MODULE_TRANSVERSE_FINDINGS_CONVERTERS_CLIPPY_LOADED:-}" ]] && return 0
_BRIK_MODULE_TRANSVERSE_FINDINGS_CONVERTERS_CLIPPY_LOADED=1

findings.converters.clippy.to_sarif() {
    if [[ $# -lt 2 ]]; then
        printf 'findings.converters.clippy.to_sarif: missing arguments (input output)\n' >&2
        return "${BRIK_EXIT_INVALID_INPUT:-2}"
    fi
    local input="$1" output="$2"

    if ! command -v jq >/dev/null 2>&1; then
        printf 'findings.converters.clippy.to_sarif: jq is required\n' >&2
        return "${BRIK_EXIT_MISSING_DEP:-3}"
    fi

    local tmp
    tmp="$(mktemp "${output}.XXXXXX")" || return "${BRIK_EXIT_IO_FAILURE:-6}"

    # KCOV_EXCL_START -- jq script body is not bash code.
    if ! jq -s '
        def level_map(s):
          if   s == "error"   then "error"
          elif s == "warning" then "warning"
          elif s == "note"    then "note"
          elif s == "help"    then "note"
          else "warning" end;

        def cvss_map(s):
          if   s == "error"   then "8.0"
          elif s == "warning" then "5.5"
          elif s == "note"    then "3.0"
          elif s == "help"    then "3.0"
          else "5.5" end;

        # Keep clippy diagnostics only. Dependency warnings and rustc
        # diagnostics carry codes outside the "clippy::" namespace; some
        # diagnostics ship with a null code -- those are conservatively
        # dropped to avoid surfacing internal cargo warnings as findings.
        def is_clippy($e):
          ($e.reason // "") == "compiler-message"
          and (($e.message.code // null) != null)
          and (($e.message.code.code // "") | startswith("clippy::"));

        def primary_span($m):
          ($m.spans // [])
          | map(select(.is_primary // false))
          | (if length == 0 then ($m.spans // []) else . end)
          | first // null;

        def result($e):
          $e.message as $m
          | primary_span($m) as $sp
          | {
              ruleId:  ($m.code.code // "clippy"),
              level:   level_map($m.level // "warning"),
              message: { text: ($m.message // "") },
              locations: (
                if $sp == null then []
                else [{
                  physicalLocation: {
                    artifactLocation: { uri: ($sp.file_name // "") },
                    region: {
                      startLine:   ($sp.line_start // 1),
                      endLine:     ($sp.line_end // ($sp.line_start // 1)),
                      startColumn: ($sp.column_start // 1),
                      endColumn:   ($sp.column_end // ($sp.column_start // 1))
                    }
                  }
                }] end
              ),
              properties: {
                "security-severity": cvss_map($m.level // "warning")
              }
            };

        ([.[] | select(is_clippy(.))] | map(result(.))) as $results
        | (
            ([.[] | select(is_clippy(.))] | group_by(.message.code.code))
            | map(
                .[0].message as $first
                | {
                    id:    ($first.code.code // "clippy"),
                    shortDescription: { text: ($first.code.code // "clippy") },
                    defaultConfiguration: { level: level_map($first.level // "warning") },
                    properties: { "security-severity": cvss_map($first.level // "warning") }
                  }
              )
          ) as $rules
        | {
            "$schema": "https://json.schemastore.org/sarif-2.1.0.json",
            version: "2.1.0",
            runs: [{
              tool: {
                driver: {
                  name: "clippy",
                  informationUri: "https://doc.rust-lang.org/clippy/",
                  rules: $rules
                }
              },
              results: $results
            }]
          }
    ' "$input" > "$tmp"; then
        rm -f "$tmp"
        printf 'findings.converters.clippy.to_sarif: jq filter failed\n' >&2
        return "${BRIK_EXIT_IO_FAILURE:-6}"
    fi
    # KCOV_EXCL_STOP

    mv "$tmp" "$output" || {
        rm -f "$tmp"
        printf 'findings.converters.clippy.to_sarif: cannot write %s\n' "$output" >&2
        return "${BRIK_EXIT_IO_FAILURE:-6}"
    }
    return 0
}
