#shellcheck shell=bash
# Unit contract for the pure stage-lifecycle classifier.
#
# _report._classify_lifecycle is the single source of truth for the canonical
# per-stage cycle of life stamped onto stages[].lifecycle during aggregation
# and read by every renderer. This spec pins its full decision matrix so the
# historical divergence between the HTML, terminal, and notify-recap
# classifications cannot reappear.
#
# Signature:
#   _report._classify_lifecycle <tech_status> <business_status> \
#       <plan_decision> <has_fragment> <upstream_failed> <is_current_stage>
# Output: "<lifecycle>\t<reason>" on stdout.

Describe "_report._classify_lifecycle"
  Include "$BRIK_PIPELINE_LIB/report.sh"

  lifecycle_of() { _report._classify_lifecycle "$@" | cut -f1; }
  reason_of()    { _report._classify_lifecycle "$@" | cut -f2; }

  Describe "recorded fragment (has_fragment=true)"
    It "classifies a green run as success"
      When call lifecycle_of success success run true false false
      The output should equal "success"
    End

    It "classifies a technically-green but business-warning run as warning"
      When call lifecycle_of success warning run true false false
      The output should equal "warning"
    End

    It "classifies a failed run as failed (tech status is authoritative)"
      When call lifecycle_of failed error run true false false
      The output should equal "failed"
    End

    It "classifies a recorded skipped fragment as skipped"
      When call lifecycle_of skipped success skip true false false
      The output should equal "skipped"
    End

    It "treats business=error without a technical failure as warning (defensive)"
      When call lifecycle_of success error run true false false
      The output should equal "warning"
    End

    It "ignores is_current_stage when a fragment exists"
      When call lifecycle_of success success run true false true
      The output should equal "success"
    End
  End

  Describe "no fragment (has_fragment=false)"
    It "classifies the in-flight stage as running"
      When call lifecycle_of "" "" run false false true
      The output should equal "running"
    End

    It "gives running precedence over upstream_failed (council precedence rule)"
      When call lifecycle_of "" "" run false true true
      The output should equal "running"
    End

    It "classifies a planned-run stage blocked by an upstream failure as not_run"
      When call lifecycle_of "" "" run false true false
      The output should equal "not_run"
    End

    It "explains an upstream-blocked stage"
      When call reason_of "" "" run false true false
      The output should equal "blocked by upstream failure"
    End

    It "classifies a planned-run stage absent without upstream failure as not_run (not reached)"
      When call lifecycle_of "" "" run false false false
      The output should equal "not_run"
    End

    It "explains a not-reached stage distinctly from an upstream block"
      When call reason_of "" "" run false false false
      The output should equal "not reached"
    End

    It "classifies a planner-skipped stage as skipped even when an upstream failed"
      When call lifecycle_of "" "" skip false true false
      The output should equal "skipped"
    End

    It "classifies a stage absent from the plan as skipped (not in plan)"
      When call lifecycle_of "" "" unknown false false false
      The output should equal "skipped"
    End
  End
End
