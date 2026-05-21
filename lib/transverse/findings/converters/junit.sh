#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# @module transverse.findings.converters.junit
# @requires yq, jq
# @description JUnit XML -> SARIF 2.1.0 converter (chantier 20260508 P5).
#   Emits one SARIF result per non-passing testcase:
#     - <failure> / <error> -> kind="fail",   level="error"
#     - <skipped>           -> kind="review", level="note"
#     - passing testcase    -> omitted (SARIF would inflate without value)
#
#   Reads the JUnit XML through `yq -p xml -o json` so we get a stable,
#   jq-friendly representation: attributes are prefixed with "+@" and
#   element text lives at "+content". Both <testsuites>/<testsuite> and
#   bare <testsuite> root shapes are handled. testcase nodes that arrive
#   as a single object (1 case) or an array (>1 cases) are normalized to
#   an array before processing.

# Guard against double-sourcing.
[[ -n "${_BRIK_MODULE_TRANSVERSE_FINDINGS_CONVERTERS_JUNIT_LOADED:-}" ]] && return 0
_BRIK_MODULE_TRANSVERSE_FINDINGS_CONVERTERS_JUNIT_LOADED=1

# Convert a JUnit XML report into SARIF 2.1.0.
# Args:
#   $1 input  -- path to the JUnit XML file.
#   $2 output -- target SARIF path (parent directory must exist; the
#                dispatcher takes care of that before we are called).
findings.converters.junit.to_sarif() {
    if [[ $# -lt 2 ]]; then
        printf 'findings.converters.junit.to_sarif: missing arguments (input output)\n' >&2
        return "$BRIK_EXIT_INVALID_INPUT"
    fi
    local input="$1" output="$2"

    if ! command -v yq >/dev/null 2>&1; then
        printf 'findings.converters.junit.to_sarif: yq is required\n' >&2
        return "$BRIK_EXIT_MISSING_DEP"
    fi
    if ! command -v jq >/dev/null 2>&1; then
        printf 'findings.converters.junit.to_sarif: jq is required\n' >&2
        return "$BRIK_EXIT_MISSING_DEP"
    fi

    local json
    json="$(yq -p xml -o json "$input" 2>/dev/null)" || {
        printf 'findings.converters.junit.to_sarif: yq failed to parse %s\n' "$input" >&2
        return "$BRIK_EXIT_CONFIG_ERROR"
    }

    local tmp
    tmp="$(mktemp "${output}.XXXXXX")" || return "$BRIK_EXIT_IO_FAILURE"

    # KCOV_EXCL_START -- jq script body is not bash code.
    if ! printf '%s' "$json" | jq '
        # Walk both shapes: <testsuites>/<testsuite> and bare <testsuite>.
        def suites:
          if   (.testsuites.testsuite // null) | type == "array" then .testsuites.testsuite
          elif (.testsuites.testsuite // null) | type == "object" then [.testsuites.testsuite]
          elif (.testsuite // null)            | type == "array" then .testsuite
          elif (.testsuite // null)            | type == "object" then [.testsuite]
          else [] end;

        # Normalize testcase to an array: yq inlines a single child as
        # an object and spreads multiple children into an array.
        def cases($s):
          ($s.testcase // []) as $tc
          | if   $tc | type == "array" then $tc
            elif $tc | type == "object" then [$tc]
            else [] end;

        # Resolve outcome: returns null for passing testcases (no SARIF
        # emission) or {kind, level, source, msg, content} otherwise.
        def outcome($tc):
          if   ($tc.failure // null) != null then
            { kind: "fail",   level: "error",
              source: "failure",
              msg: ($tc.failure["+@message"] // "test failed"),
              content: ($tc.failure["+content"] // "") }
          elif ($tc.error // null)   != null then
            { kind: "fail",   level: "error",
              source: "error",
              msg: ($tc.error["+@message"] // "test errored"),
              content: ($tc.error["+content"] // "") }
          elif ($tc.skipped // null) != null then
            { kind: "review", level: "note",
              source: "skipped",
              msg: ($tc.skipped["+@message"] // "test skipped"),
              content: ($tc.skipped["+content"] // "") }
          else null end;

        def rule_id($tc):
          ($tc["+@classname"] // "") as $c
          | ($tc["+@name"] // "") as $n
          | if $c == "" then $n else ($c + "." + $n) end;

        def result($tc):
          outcome($tc) as $o
          | if $o == null then empty
            else
              {
                ruleId: rule_id($tc),
                level:  $o.level,
                kind:   $o.kind,
                message: {
                  text: (
                    if $o.content == "" then $o.msg
                    else ($o.msg + "\n" + $o.content) end
                  )
                },
                properties: {
                  source:   $o.source,
                  testTime: ($tc["+@time"] // "0")
                }
              }
            end;

        ([suites[] | cases(.) | .[] | result(.)]) as $results
        | ($results | map(.ruleId) | unique
          | map({
              id: .,
              shortDescription: { text: . }
            })) as $rules
        | {
            "$schema": "https://json.schemastore.org/sarif-2.1.0.json",
            version: "2.1.0",
            runs: [{
              tool: {
                driver: {
                  name: "junit",
                  informationUri: "https://github.com/junit-team/junit5",
                  rules: $rules
                }
              },
              results: $results
            }]
          }
    ' > "$tmp"; then
        rm -f "$tmp"
        printf 'findings.converters.junit.to_sarif: jq filter failed\n' >&2
        return "$BRIK_EXIT_IO_FAILURE"
    fi
    # KCOV_EXCL_STOP

    mv "$tmp" "$output" || {
        rm -f "$tmp"
        printf 'findings.converters.junit.to_sarif: cannot write %s\n' "$output" >&2
        return "$BRIK_EXIT_IO_FAILURE"
    }
    return 0
}
