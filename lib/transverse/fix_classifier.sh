#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# @module transverse.fix_classifier
# @requires jq
# @description Annotate SARIF results with their fix-exists classification.
#
# Each result gains a properties.brikFixClassification field with one of
# three values:
#   - has_fix : an upstream fix exists and can be applied
#   - no_fix  : no upstream fix known (no-upstream-fix, vendor-wont-fix)
#   - unknown : classification not determinable; conservative default
#               (treated as has_fix by business.evaluate, i.e. BLOCK in
#               release context)
#
# Heuristics dispatched by stage name (master pipeline-behavior-model
# sub-chantier 13):
#   - container-scan : grype properties.fixState
#                      fixed     -> has_fix
#                      not-fixed -> no_fix
#                      wont-fix  -> no_fix
#                      unknown   -> unknown
#                      absent    -> unknown
#   - sast           : semgrep properties.fixState == "fixed"
#                      OR rule.help.text matches "Fix Version"
#                      -> has_fix
#                      else -> no_fix
#   - scan/deps/scan-deps : result.fixes[] non-empty -> has_fix
#                           else -> no_fix
#   - secret/scan-secret  : always has_fix (rotation possible)
#   - lint/format         : always has_fix (linter findings fixable)
#   - test                : always has_fix
#   - any other stage     : unknown

# Guard against double-sourcing
[[ -n "${_BRIK_FIX_CLASSIFIER_LOADED:-}" ]] && return 0
_BRIK_FIX_CLASSIFIER_LOADED=1

# shellcheck source=../pipeline/logging.sh
[[ -z "${_BRIK_LOGGING_LOADED:-}" ]] && . "${BASH_SOURCE[0]%/*}/../pipeline/logging.sh"
# shellcheck source=../pipeline/error.sh
[[ -z "${_BRIK_ERROR_LOADED:-}" ]] && . "${BASH_SOURCE[0]%/*}/../pipeline/error.sh"

# jq filter that walks runs[].results[] and adds properties.brikFixClassification.
# Reads the stage name from --arg stage. Looks up rule.help.text via
# runs[].tool.driver.rules[] when the heuristic needs it (sast).
#
# Kept as a heredoc-readable string inside the function to avoid global
# state. Bash variable names cannot contain dots, so the filter cannot
# live in a "_fix_classifier._jq_filter" global; an in-function local
# string is both simpler and safer.

# Annotate a SARIF file in place with brikFixClassification per result.
#
# Usage: fix_classifier.classify_sarif <sarif_path> <stage_name>
#
# Errors:
#   BRIK_EXIT_INVALID_INPUT : stage_name empty
#   BRIK_EXIT_IO_FAILURE    : file not found
#   BRIK_EXIT_MISSING_DEP   : jq not available
#   BRIK_EXIT_FAILURE       : jq processing failed
fix_classifier.classify_sarif() {
    local sarif_path="$1"
    local stage="${2:-}"

    if [[ -z "$stage" ]]; then
        error.raise "$BRIK_EXIT_INVALID_INPUT" \
            "fix_classifier.classify_sarif: stage name is required"
        return "$?"
    fi
    if [[ ! -f "$sarif_path" ]]; then
        error.raise "$BRIK_EXIT_IO_FAILURE" \
            "fix_classifier.classify_sarif: file not found: $sarif_path"
        return "$?"
    fi
    if ! command -v jq >/dev/null 2>&1; then
        error.raise "$BRIK_EXIT_MISSING_DEP" \
            "fix_classifier.classify_sarif: jq is required"
        return "$?"
    fi

    local tmp
    tmp="$(mktemp "${sarif_path}.XXXXXX")" || return "$BRIK_EXIT_IO_FAILURE"

    # KCOV_EXCL_START -- jq filter body is not bash code
    local filter='
def rule_help($rid; $rules):
  ($rules | map(select(.id == $rid)) | first | (.help.text // ""));

def classify($r; $rules; $stage):
  if $stage == "container-scan" then
    if   ($r.properties.fixState // "") == "fixed"     then "has_fix"
    elif ($r.properties.fixState // "") == "not-fixed" then "no_fix"
    elif ($r.properties.fixState // "") == "wont-fix"  then "no_fix"
    elif ($r.properties.fixState // "") == "unknown"   then "unknown"
    else "unknown" end
  elif $stage == "sast" then
    if ($r.properties.fixState // "") == "fixed" then "has_fix"
    elif (rule_help($r.ruleId // ""; $rules) | test("Fix Version")) then "has_fix"
    else "no_fix" end
  elif ($stage == "scan-deps" or $stage == "deps" or $stage == "scan") then
    if (($r.fixes // []) | length) > 0 then "has_fix"
    else "no_fix" end
  elif ($stage == "secret" or $stage == "scan-secret") then
    "has_fix"
  elif ($stage == "lint" or $stage == "format") then
    "has_fix"
  elif $stage == "test" then
    "has_fix"
  else
    "unknown"
  end;

# SC19: per-result tool-blocking decision based on tool name + severity
# input. Only meaningful for lint/format stages where tool-native
# warning vs error is the gating signal. Other stages let the legacy
# semantic stand (every failing result counts).
def tool_blocking($r; $tool):
  ($tool // "" | ascii_downcase) as $t
  | if $t == "ruff" then
      (($r.ruleId // "" | ascii_downcase) as $rid
       | if   ($rid | test("^[wi][0-9]"))   then false
         elif ($rid | test("^[ef][0-9]"))   then true
         else (($r.level // "" | ascii_downcase) == "error") end)
    elif ($t | test("eslint")) then
      (($r.level // "" | ascii_downcase) == "error")
    elif ($t == "checkstyle" or $t == "dotnet-format") then
      (($r.level // "" | ascii_downcase) == "error")
    else
      (($r.level // "" | ascii_downcase) == "error")
    end;

.runs |= map(
  . as $run
  | ($run.tool.driver.rules // []) as $rules
  | ($run.tool.driver.name // "") as $tool_name
  | $run | .results = ([($run.results // [])[] |
      . as $r
      | (
          { brikFixClassification: classify($r; $rules; $stage) }
          + ( if ($stage == "lint" or $stage == "format")
              then { brikToolBlocking: tool_blocking($r; $tool_name) }
              else {}
              end )
        ) as $brik_props
      | . + { properties: ((.properties // {}) + $brik_props) }
    ])
)'
    # KCOV_EXCL_STOP

    if jq --arg stage "$stage" "$filter" "$sarif_path" > "$tmp" 2>/dev/null; then
        mv "$tmp" "$sarif_path"
        return 0
    fi
    rm -f "$tmp"
    error.raise "$BRIK_EXIT_FAILURE" \
        "fix_classifier.classify_sarif: jq processing failed on $sarif_path"
    return "$?"
}
