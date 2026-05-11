#shellcheck shell=bash
# Contract for lib/transverse/fix_classifier.sh
#
# The fix classifier annotates each SARIF result with a
# properties.brikFixClassification field that takes one of three values:
#   - has_fix : an upstream fix exists and can be applied (CVE patched,
#               tool installable, config writable, code fixable)
#   - no_fix  : no upstream fix is known (no-upstream-fix, vendor-wont-fix)
#   - unknown : impossible to determine; treated as has_fix downstream
#               (conservative default: BLOCK in release)
#
# Per-stage heuristics (per docs/chantiers/20260511_pipeline-behavior-model.md
# sub-chantier 13):
#   - container-scan (grype) : properties.fixState
#                              fixed     -> has_fix
#                              not-fixed -> no_fix
#                              wont-fix  -> no_fix
#                              unknown   -> unknown
#                              absent    -> unknown
#   - sast (semgrep)        : properties.fixState == "fixed"
#                              OR rule.help.text matches "Fix Version"
#                              -> has_fix
#                              else -> no_fix
#   - scan, deps, scan-deps : result.fixes[] non-empty -> has_fix
#                              else -> no_fix
#   - secret, scan-secret   : always has_fix (rotation possible)
#   - lint, format          : always has_fix (linter findings fixable in code)
#   - test                  : always has_fix
#   - any other stage       : unknown
#
# The public API is fix_classifier.classify_sarif which annotates a SARIF
# file in place.

Describe "lib/transverse/fix_classifier.sh"
  FIXTURES="$BRIK_HOME/spec/fixtures/sarif"

  setup_workdir() {
    WORKDIR="$(mktemp -d)"
  }
  cleanup_workdir() {
    rm -rf "$WORKDIR"
  }

  classify_into_tmp() {
    local fixture="$1" stage="$2"
    local tmp="$WORKDIR/${stage}.sarif"
    cp "$FIXTURES/$fixture" "$tmp"
    fix_classifier.classify_sarif "$tmp" "$stage" >/dev/null
    printf '%s' "$tmp"
  }

  Include "$BRIK_HOME/lib/pipeline/error.sh"
  Include "$BRIK_HOME/lib/pipeline/logging.sh"
  Include "$BRIK_HOME/lib/transverse/fix_classifier.sh"

  Before 'setup_workdir'
  After 'cleanup_workdir'

  Describe "container-scan (grype) channel"
    It "maps fixState=fixed to has_fix"
      do_classify() {
        local tmp; tmp=$(classify_into_tmp grype-fixstate.sarif container-scan)
        jq -r '.runs[0].results[] | select(.properties.fixState=="fixed") | .properties.brikFixClassification' "$tmp" | sort -u
      }
      When call do_classify
      The output should equal "has_fix"
    End

    It "maps fixState=not-fixed to no_fix"
      do_classify() {
        local tmp; tmp=$(classify_into_tmp grype-fixstate.sarif container-scan)
        jq -r '.runs[0].results[] | select(.properties.fixState=="not-fixed") | .properties.brikFixClassification' "$tmp" | sort -u
      }
      When call do_classify
      The output should equal "no_fix"
    End

    It "ensures every result carries brikFixClassification"
      do_classify() {
        local tmp; tmp=$(classify_into_tmp grype-fixstate.sarif container-scan)
        jq -r '[.runs[0].results[] | .properties.brikFixClassification // "absent"] | unique | join(",")' "$tmp"
      }
      When call do_classify
      The output should not include "absent"
    End
  End

  Describe "sast (semgrep) channel"
    It "classifies semgrep findings without a Fix Version hint as no_fix"
      do_classify() {
        local tmp; tmp=$(classify_into_tmp semgrep.sarif sast)
        jq -r '.runs[0].results[0].properties.brikFixClassification' "$tmp"
      }
      When call do_classify
      The output should equal "no_fix"
    End

    It "annotates every semgrep result"
      do_classify() {
        local tmp; tmp=$(classify_into_tmp semgrep.sarif sast)
        jq -r '[.runs[0].results[] | (.properties.brikFixClassification // "absent")] | unique | length'  "$tmp"
      }
      When call do_classify
      The output should equal "1"
    End
  End

  Describe "scan-deps (osv-scanner) channel"
    It "classifies osv-scanner results without fixes[] as no_fix"
      do_classify() {
        local tmp; tmp=$(classify_into_tmp osv-scanner.sarif scan-deps)
        jq -r '.runs[0].results[0].properties.brikFixClassification' "$tmp"
      }
      When call do_classify
      The output should equal "no_fix"
    End
  End

  Describe "secret (gitleaks) channel"
    It "always classifies gitleaks findings as has_fix"
      do_classify() {
        local tmp; tmp=$(classify_into_tmp gitleaks.sarif secret)
        jq -r '[.runs[0].results[] | .properties.brikFixClassification] | unique | join(",")' "$tmp"
      }
      When call do_classify
      The output should equal "has_fix"
    End
  End

  Describe "lint (eslint, ruff) channel"
    It "classifies eslint findings as has_fix"
      do_classify() {
        local tmp; tmp=$(classify_into_tmp eslint.sarif lint)
        jq -r '[.runs[0].results[] | .properties.brikFixClassification] | unique | join(",")' "$tmp"
      }
      When call do_classify
      The output should equal "has_fix"
    End

    It "classifies ruff findings as has_fix"
      do_classify() {
        local tmp; tmp=$(classify_into_tmp ruff.sarif lint)
        jq -r '[.runs[0].results[] | .properties.brikFixClassification] | unique | join(",")' "$tmp"
      }
      When call do_classify
      The output should equal "has_fix"
    End
  End

  Describe "unknown stage"
    It "classifies as unknown when the stage name is not recognized"
      do_classify() {
        local tmp; tmp=$(classify_into_tmp eslint.sarif weird-stage)
        jq -r '[.runs[0].results[] | .properties.brikFixClassification] | unique | join(",")' "$tmp"
      }
      When call do_classify
      The output should equal "unknown"
    End
  End

  Describe "structural preservation"
    It "preserves the SARIF schema version"
      do_classify() {
        local tmp; tmp=$(classify_into_tmp grype-fixstate.sarif container-scan)
        jq -r '."$schema" // ""' "$tmp"
      }
      When call do_classify
      The output should include "sarif"
    End

    It "preserves the original ruleId on each result"
      do_classify() {
        local tmp; tmp=$(classify_into_tmp grype-fixstate.sarif container-scan)
        local before; before=$(jq -r '[.runs[0].results[].ruleId] | sort | join(",")' "$FIXTURES/grype-fixstate.sarif")
        local after;  after=$(jq -r '[.runs[0].results[].ruleId] | sort | join(",")' "$tmp")
        if [[ "$before" == "$after" ]]; then printf 'preserved'; else printf 'mismatch'; fi
      }
      When call do_classify
      The output should equal "preserved"
    End

    It "merges into existing properties rather than overwriting"
      do_classify() {
        local tmp; tmp=$(classify_into_tmp grype-fixstate.sarif container-scan)
        jq -r '.runs[0].results[0].properties | (has("fixState") and has("brikFixClassification"))' "$tmp"
      }
      When call do_classify
      The output should equal "true"
    End
  End

  Describe "edge cases"
    It "handles a SARIF with empty results[] without erroring"
      do_classify() {
        local tmp; tmp=$(classify_into_tmp eslint-empty.sarif lint)
        jq -r '.runs[0].results | length' "$tmp"
      }
      When call do_classify
      The output should equal "0"
    End

    It "leaves the file unchanged when the path does not exist"
      When call fix_classifier.classify_sarif "$WORKDIR/nonexistent.sarif" lint
      The status should not equal 0
      The error should include "file not found"
    End

    It "rejects an empty stage name with BRIK_EXIT_INVALID_INPUT"
      do_run() {
        local tmp="$WORKDIR/empty-stage.sarif"
        cp "$FIXTURES/eslint.sarif" "$tmp"
        fix_classifier.classify_sarif "$tmp" ""
      }
      When call do_run
      The status should equal 2
      The error should include "stage name is required"
    End
  End
End
