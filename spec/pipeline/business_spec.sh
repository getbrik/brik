#shellcheck shell=bash
# Contract for lib/pipeline/business.sh
#
# business.evaluate is the central business filter: it transforms a stage's
# (technical status, side-band signals, pipeline context) into the typed
# business outcome (status, reason). It is a pure function: it reads its
# inputs from named flags, returns its result as JSON on stdout, and never
# touches the report backend or shell state.
#
# Matrix (5 lines):
#   tech.status | side-band              | context  | business.status
#   ------------+------------------------+----------+----------------
#   success     | none                   | *        | success
#   success     | findings.ignored > 0   | *        | warning
#   failed      | *                      | snapshot | warning
#   failed      | *                      | release  | error
#   skipped     | *                      | *        | success
#
# Inputs (all named flags):
#   --tech-status      success|failed|skipped         required
#   --context          snapshot|release               required
#   --findings-ignored <integer>                      optional, default 0
#   --tech-kind        <string>                       optional, default ""
#
# Output (stdout): JSON object {"status": ..., "reason": ...}
# Exit code: 0 on success, BRIK_EXIT_INVALID_INPUT on malformed inputs.

Describe "lib/pipeline/business.sh"
  Include "$BRIK_PIPELINE_LIB/error.sh"
  Include "$BRIK_PIPELINE_LIB/logging.sh"
  Include "$BRIK_PIPELINE_LIB/business.sh"

  # ----------------------------------------------------------------------
  # Matrix coverage: 5 rows, each producing a deterministic (status, reason)
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

    It "emits a reason that mentions the ignored count"
      eval_reason() {
        business.evaluate \
          --tech-status success \
          --context snapshot \
          --findings-ignored 14 \
          | jq -r .reason
      }
      When call eval_reason
      The output should include "14"
      The output should include "ignored"
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

  Describe "row 3: failed under snapshot context"
    It "downgrades to warning"
      eval_status() {
        business.evaluate \
          --tech-status failed \
          --context snapshot \
          --tech-kind timeout \
          | jq -r .status
      }
      When call eval_status
      The output should equal "warning"
    End

    It "emits a reason that includes the technical kind"
      eval_reason() {
        business.evaluate \
          --tech-status failed \
          --context snapshot \
          --tech-kind timeout \
          | jq -r .reason
      }
      When call eval_reason
      The output should include "timeout"
    End
  End

  Describe "row 4: failed under release context"
    It "is promoted to error"
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

    It "emits a reason that includes the technical kind"
      eval_reason() {
        business.evaluate \
          --tech-status failed \
          --context release \
          --tech-kind check-failed \
          | jq -r .reason
      }
      When call eval_reason
      The output should include "check-failed"
    End
  End

  Describe "row 5: skipped (auto not-applicable)"
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
