# L2 edge: Stages -> Execution (graph edge #6)
#
# The execution runtime (stage.run) instruments every stage: it captures the
# logic function's exit code, writes a <stage>-summary.json, and records the
# tech.status into the aggregate report. This pins that a REAL stage.run
# produces BOTH artifacts consistently (summary + aggregate) in one pass --
# unit specs assert each in isolation or stub stage.run; here the full
# instrumentation runs. Stage ordering is covered by the unit pipeline spec.

Describe "L2 stages -> execution: stage.run instruments a real stage"
  Include "$BRIK_HOME/lib/pipeline/stage.sh"
  Include "$BRIK_HOME/lib/pipeline/loader.sh"
  Include "$BRIK_HOME/lib/pipeline/report.sh"

  setup_exec() {
    export BRIK_PROJECT_DIR="/nonexistent"
    export BRIK_WORKSPACE
    BRIK_WORKSPACE="$(mktemp -d)"
    export BRIK_RUN_ID="stages-x-exec-fixture"
    report.init >/dev/null 2>&1 || true
  }
  cleanup_exec() {
    rm -rf "$BRIK_WORKSPACE"
    unset BRIK_RUN_ID BRIK_WORKSPACE
  }
  Before 'setup_exec'
  After 'cleanup_exec'

  agg_status() {
    jq -r --arg s "$1" '.stages[] | select(.stage == $s) | .tech.status' \
      "$BRIK_LOG_DIR/aggregate-report.json"
  }

  Describe "a passing stage"
    pass_logic() { return 0; }

    It "writes a SUCCESS summary and records tech.status=success"
      run_pass() {
        stage.run greenstage pass_logic >/dev/null 2>&1
        jq -e '.status == "SUCCESS"' "$BRIK_LOG_DIR/greenstage-summary.json" >/dev/null || return 1
        agg_status greenstage
      }
      When call run_pass
      The output should equal "success"
    End
  End

  Describe "a failing stage"
    fail_logic() { return 5; }

    It "propagates exit 5, marks FAILED, and records tech.status=failed"
      run_fail() {
        stage.run redstage fail_logic >/dev/null 2>&1
        local rc=$?
        [ "$rc" -eq 5 ] || return 1
        jq -e '.status == "FAILED"' "$BRIK_LOG_DIR/redstage-summary.json" >/dev/null || return 1
        agg_status redstage
      }
      When call run_fail
      The output should equal "failed"
    End
  End
End
