# L2 edge: Findings (x) verify stages (graph edge #11)
#
# The four verify consumers (lint, sast, scan, container-scan) share one
# findings pivot. This pins the two cross-stage consistency contracts:
#   - severity normalization maps every scanner's native severity onto the
#     same brik scale, regardless of which stage's tool produced it;
#   - fix-classification dispatches per consuming stage on the SAME native
#     finding (e.g. a grype fixState yields has_fix under container-scan but
#     not under the deps scan, which keys off fixes[]).

Describe "L2 findings x verify stages: shared severity + fix classification"
  Include "$BRIK_PIPELINE_LIB/logging.sh"
  Include "$BRIK_TRANSVERSE_LIB/severity.sh"
  Include "$BRIK_TRANSVERSE_LIB/fix_classifier.sh"

  Describe "severity normalization is one shared scale across the stages' tools"
    Parameters
      grype         Critical critical
      "osv-scanner" MODERATE medium
      semgrep       ERROR    high
      grype         Low      low
    End

    It "$1 '$2' normalizes to $3"
      When call severity.normalize "$1" "$2"
      The output should equal "$3"
    End
  End

  Describe "fix-classification dispatches per consuming stage on the same finding"
    SARIF="$BRIK_HOME/spec/fixtures/sarif/grype-fixstate.sarif"

    classes_for() {
      local stage="$1" tmp
      tmp="$(mktemp)"
      cp "$SARIF" "$tmp"
      fix_classifier.classify_sarif "$tmp" "$stage" >/dev/null 2>&1
      jq -r '[.runs[0].results[].properties.brikFixClassification] | unique | sort | join(",")' "$tmp"
      rm -f "$tmp"
    }

    It "container-scan derives has_fix from the grype fixState"
      has_fix_present() { classes_for container-scan | grep -q "has_fix"; }
      When call has_fix_present
      The status should be success
    End

    It "the deps scan does not (it keys off fixes[], absent here)"
      no_has_fix() { ! classes_for scan-deps | grep -q "has_fix"; }
      When call no_has_fix
      The status should be success
    End
  End
End
