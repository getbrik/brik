#shellcheck shell=bash
# Contract for lib/pipeline/business.sh
#
# business.evaluate is the central business filter: it transforms a stage's
# (technical status, side-band signals, pipeline context) into the typed
# business outcome (status, reason). It is a pure function: it reads its
# inputs from named flags, returns its result as JSON on stdout, and never
# touches the report backend or shell state.
#
# Matrix (10 rows, per docs/chantiers/20260511_pipeline-behavior-model.md):
#
#   tech.status | side-band                    | context  | business.status
#   ------------+------------------------------+----------+----------------
#   success     | none                         | *        | success
#   success     | findings.ignored.total > 0   | *        | warning
#   success     | findings.failing.no_fix > 0  | *        | warning
#   failed      | fix_class = has_fix          | snapshot | warning
#   failed      | fix_class = has_fix          | release  | error
#   failed      | fix_class = no_fix           | snapshot | warning
#   failed      | fix_class = no_fix           | release  | warning
#   failed      | fix_class = unknown          | snapshot | warning
#   failed      | fix_class = unknown          | release  | error
#   skipped (not-applicable) | *               | *        | success
#
# fix_class priority when multiple failing counters are non-zero:
#   has_fix > unknown > no_fix-only.
# Default fix_class when all three are zero (no failing classification
# metadata produced by the stage) is has_fix (conservative: treat as
# fixable, BLOCK in release).
#
# Inputs (all named flags):
#   --tech-status                 success|failed|skipped         required
#   --context                     snapshot|release               required
#   --findings-ignored            <integer>=0                    optional
#   --findings-failing-has-fix    <integer>=0                    optional
#   --findings-failing-no-fix     <integer>=0                    optional
#   --findings-failing-unknown    <integer>=0                    optional
#   --tech-kind                   <string>=""                    optional
#
# Output (stdout): JSON object {"status": ..., "reason": ...}
# Exit code: 0 on success, BRIK_EXIT_INVALID_INPUT (2) on malformed inputs.

Describe "lib/pipeline/business.sh"
  Include "$BRIK_PIPELINE_LIB/error.sh"
  Include "$BRIK_PIPELINE_LIB/logging.sh"
  Include "$BRIK_PIPELINE_LIB/business.sh"

  # ----------------------------------------------------------------------
  # Matrix coverage: 10 rows
  # ----------------------------------------------------------------------

  Describe "row 1: success without side-band"
    It "returns business.status=success"
      eval_status() {
        business.evaluate \
          --tech-status success \
          --context snapshot \
          | jq -r .status
      }
      When call eval_status
      The output should equal "success"
    End

    It "returns the same outcome under release context"
      eval_status() {
        business.evaluate \
          --tech-status success \
          --context release \
          | jq -r .status
      }
      When call eval_status
      The output should equal "success"
    End

    It "emits an empty reason"
      eval_reason() {
        business.evaluate \
          --tech-status success \
          --context snapshot \
          | jq -r .reason
      }
      When call eval_reason
      The output should equal ""
    End
  End

  Describe "row 2: success with findings.ignored > 0"
    It "elevates business.status to warning"
      eval_status() {
        business.evaluate \
          --tech-status success \
          --context snapshot \
          --findings-ignored 14 \
          | jq -r .status
      }
      When call eval_status
      The output should equal "warning"
    End

    It "remains a warning under release context (policy already accepted)"
      eval_status() {
        business.evaluate \
          --tech-status success \
          --context release \
          --findings-ignored 14 \
          | jq -r .status
      }
      When call eval_status
      The output should equal "warning"
    End

    It "emits the canonical reason 'findings accepted by policy'"
      eval_reason() {
        business.evaluate \
          --tech-status success \
          --context snapshot \
          --findings-ignored 14 \
          | jq -r .reason
      }
      When call eval_reason
      The output should include "accepted by policy"
    End

    It "stays at success when findings.ignored is exactly 0"
      eval_status() {
        business.evaluate \
          --tech-status success \
          --context snapshot \
          --findings-ignored 0 \
          | jq -r .status
      }
      When call eval_status
      The output should equal "success"
    End
  End

  Describe "row 3: success with findings.failing.no_fix > 0"
    It "elevates business.status to warning when only no_fix is non-zero"
      eval_status() {
        business.evaluate \
          --tech-status success \
          --context snapshot \
          --findings-failing-no-fix 3 \
          | jq -r .status
      }
      When call eval_status
      The output should equal "warning"
    End

    It "remains a warning under release context"
      eval_status() {
        business.evaluate \
          --tech-status success \
          --context release \
          --findings-failing-no-fix 3 \
          | jq -r .status
      }
      When call eval_status
      The output should equal "warning"
    End

    It "emits the canonical reason 'findings without upstream fix'"
      eval_reason() {
        business.evaluate \
          --tech-status success \
          --context snapshot \
          --findings-failing-no-fix 3 \
          | jq -r .reason
      }
      When call eval_reason
      The output should include "without upstream fix"
    End

    It "stays success when failing.no_fix is exactly 0"
      eval_status() {
        business.evaluate \
          --tech-status success \
          --context snapshot \
          --findings-failing-no-fix 0 \
          | jq -r .status
      }
      When call eval_status
      The output should equal "success"
    End
  End

  Describe "row 4: failed + fix_class=has_fix + snapshot"
    It "downgrades to warning in snapshot"
      eval_status() {
        business.evaluate \
          --tech-status failed \
          --context snapshot \
          --tech-kind check-failed \
          --findings-failing-has-fix 5 \
          | jq -r .status
      }
      When call eval_status
      The output should equal "warning"
    End

    It "emits reason that mentions kind and 'fix available'"
      eval_reason() {
        business.evaluate \
          --tech-status failed \
          --context snapshot \
          --tech-kind check-failed \
          --findings-failing-has-fix 5 \
          | jq -r .reason
      }
      When call eval_reason
      The output should include "check-failed"
      The output should include "fix available"
    End
  End

  Describe "row 5: failed + fix_class=has_fix + release"
    It "promotes to error in release"
      eval_status() {
        business.evaluate \
          --tech-status failed \
          --context release \
          --tech-kind check-failed \
          --findings-failing-has-fix 5 \
          | jq -r .status
      }
      When call eval_status
      The output should equal "error"
    End

    It "emits reason that mentions 'fix available, not applied'"
      eval_reason() {
        business.evaluate \
          --tech-status failed \
          --context release \
          --tech-kind check-failed \
          --findings-failing-has-fix 5 \
          | jq -r .reason
      }
      When call eval_reason
      The output should include "check-failed"
      The output should include "not applied"
    End
  End

  Describe "row 6: failed + fix_class=no_fix + snapshot"
    It "downgrades to warning in snapshot"
      eval_status() {
        business.evaluate \
          --tech-status failed \
          --context snapshot \
          --tech-kind check-failed \
          --findings-failing-no-fix 3 \
          | jq -r .status
      }
      When call eval_status
      The output should equal "warning"
    End

    It "emits reason that mentions 'no fix available'"
      eval_reason() {
        business.evaluate \
          --tech-status failed \
          --context snapshot \
          --tech-kind check-failed \
          --findings-failing-no-fix 3 \
          | jq -r .reason
      }
      When call eval_reason
      The output should include "no fix available"
    End
  End

  Describe "row 7: failed + fix_class=no_fix + release"
    It "stays at warning in release (no fix possible, entreprise decides)"
      eval_status() {
        business.evaluate \
          --tech-status failed \
          --context release \
          --tech-kind check-failed \
          --findings-failing-no-fix 3 \
          | jq -r .status
      }
      When call eval_status
      The output should equal "warning"
    End

    It "emits reason that mentions 'accepted' to make the trade-off explicit"
      eval_reason() {
        business.evaluate \
          --tech-status failed \
          --context release \
          --tech-kind check-failed \
          --findings-failing-no-fix 3 \
          | jq -r .reason
      }
      When call eval_reason
      The output should include "accepted"
    End
  End

  Describe "row 8: failed + fix_class=unknown + snapshot"
    It "downgrades to warning"
      eval_status() {
        business.evaluate \
          --tech-status failed \
          --context snapshot \
          --tech-kind check-failed \
          --findings-failing-unknown 2 \
          | jq -r .status
      }
      When call eval_status
      The output should equal "warning"
    End

    It "emits reason that mentions classification unknown"
      eval_reason() {
        business.evaluate \
          --tech-status failed \
          --context snapshot \
          --tech-kind check-failed \
          --findings-failing-unknown 2 \
          | jq -r .reason
      }
      When call eval_reason
      The output should include "classification unknown"
    End
  End

  Describe "row 9: failed + fix_class=unknown + release"
    It "promotes to error in release (strict default)"
      eval_status() {
        business.evaluate \
          --tech-status failed \
          --context release \
          --tech-kind check-failed \
          --findings-failing-unknown 2 \
          | jq -r .status
      }
      When call eval_status
      The output should equal "error"
    End

    It "emits reason that mentions 'strict'"
      eval_reason() {
        business.evaluate \
          --tech-status failed \
          --context release \
          --tech-kind check-failed \
          --findings-failing-unknown 2 \
          | jq -r .reason
      }
      When call eval_reason
      The output should include "strict"
    End
  End

  Describe "row 10: skipped (auto not-applicable)"
    It "returns success regardless of context"
      eval_status_snapshot() {
        business.evaluate \
          --tech-status skipped \
          --context snapshot \
          --tech-kind not-applicable \
          | jq -r .status
      }
      When call eval_status_snapshot
      The output should equal "success"
    End

    It "returns success in release context too"
      eval_status_release() {
        business.evaluate \
          --tech-status skipped \
          --context release \
          --tech-kind not-applicable \
          | jq -r .status
      }
      When call eval_status_release
      The output should equal "success"
    End

    It "emits a reason that mentions not-applicable"
      eval_reason() {
        business.evaluate \
          --tech-status skipped \
          --context snapshot \
          --tech-kind not-applicable \
          | jq -r .reason
      }
      When call eval_reason
      The output should include "not applicable"
    End
  End

  # ----------------------------------------------------------------------
  # fix_class priority when multiple failing counters are set
  # ----------------------------------------------------------------------

  Describe "fix_class priority"
    It "picks has_fix when has_fix > 0 and no_fix > 0 (release -> error)"
      eval_status() {
        business.evaluate \
          --tech-status failed \
          --context release \
          --tech-kind check-failed \
          --findings-failing-has-fix 2 \
          --findings-failing-no-fix 3 \
          | jq -r .status
      }
      When call eval_status
      The output should equal "error"
    End

    It "picks unknown over no_fix when has_fix=0 (release -> error)"
      eval_status() {
        business.evaluate \
          --tech-status failed \
          --context release \
          --tech-kind check-failed \
          --findings-failing-unknown 1 \
          --findings-failing-no-fix 5 \
          | jq -r .status
      }
      When call eval_status
      The output should equal "error"
    End

    It "defaults to has_fix when all three counters are zero (release -> error)"
      eval_status() {
        business.evaluate \
          --tech-status failed \
          --context release \
          --tech-kind check-failed \
          | jq -r .status
      }
      When call eval_status
      The output should equal "error"
    End

    It "defaults to has_fix when all three counters are zero (snapshot -> warning)"
      eval_status() {
        business.evaluate \
          --tech-status failed \
          --context snapshot \
          --tech-kind check-failed \
          | jq -r .status
      }
      When call eval_status
      The output should equal "warning"
    End
  End

  # ----------------------------------------------------------------------
  # JSON output shape
  # ----------------------------------------------------------------------

  Describe "JSON output shape"
    It "always emits a status field"
      eval_keys() {
        business.evaluate \
          --tech-status success \
          --context snapshot \
          | jq -r 'has("status")'
      }
      When call eval_keys
      The output should equal "true"
    End

    It "always emits a reason field"
      eval_keys() {
        business.evaluate \
          --tech-status success \
          --context snapshot \
          | jq -r 'has("reason")'
      }
      When call eval_keys
      The output should equal "true"
    End

    It "constrains status to {success, warning, error}"
      eval_status() {
        business.evaluate \
          --tech-status failed \
          --context release \
          --tech-kind failure \
          | jq -r '.status | test("^(success|warning|error)$")'
      }
      When call eval_status
      The output should equal "true"
    End

    It "produces valid JSON parseable by jq"
      eval_json() {
        business.evaluate \
          --tech-status success \
          --context snapshot \
          | jq -e . >/dev/null
      }
      When call eval_json
      The status should be success
    End
  End

  # ----------------------------------------------------------------------
  # Input validation
  # ----------------------------------------------------------------------

  Describe "input validation"
    It "rejects an invocation without --tech-status"
      When call business.evaluate --context snapshot
      The status should equal 2
      The error should include "tech-status"
    End

    It "rejects an unknown --tech-status value"
      When call business.evaluate --tech-status tolerated --context snapshot
      The status should equal 2
      The error should include "tech-status"
    End

    It "rejects an invocation without --context"
      When call business.evaluate --tech-status success
      The status should equal 2
      The error should include "context"
    End

    It "rejects an unknown --context value"
      When call business.evaluate --tech-status failed --context rehearsal
      The status should equal 2
      The error should include "context"
    End

    It "rejects a negative --findings-ignored"
      When call business.evaluate \
        --tech-status success \
        --context snapshot \
        --findings-ignored -3
      The status should equal 2
      The error should include "findings-ignored"
    End

    It "rejects a non-integer --findings-ignored"
      When call business.evaluate \
        --tech-status success \
        --context snapshot \
        --findings-ignored fourteen
      The status should equal 2
      The error should include "findings-ignored"
    End

    It "rejects a negative --findings-failing-has-fix"
      When call business.evaluate \
        --tech-status failed \
        --context release \
        --findings-failing-has-fix -1
      The status should equal 2
      The error should include "findings-failing-has-fix"
    End

    It "rejects a non-integer --findings-failing-no-fix"
      When call business.evaluate \
        --tech-status failed \
        --context release \
        --findings-failing-no-fix three
      The status should equal 2
      The error should include "findings-failing-no-fix"
    End

    It "rejects a negative --findings-failing-unknown"
      When call business.evaluate \
        --tech-status failed \
        --context release \
        --findings-failing-unknown -2
      The status should equal 2
      The error should include "findings-failing-unknown"
    End

    It "rejects an unknown flag"
      When call business.evaluate \
        --tech-status success \
        --context snapshot \
        --unknown-flag foo
      The status should equal 2
      The error should include "unknown"
    End
  End
End
