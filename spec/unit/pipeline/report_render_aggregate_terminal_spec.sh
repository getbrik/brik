#shellcheck shell=bash
# Terminal recap rendered from aggregate-report.json (the CI aggregate shape).
# Phase 2 of the stage-lifecycle model: render_aggregate_terminal reads the
# canonical stages[].lifecycle stamped by aggregation, so a stage blocked by an
# upstream failure shows NOT-RUN (not SKIPPED) and the in-flight stage shows
# RUNNING. Falls back to tech.status/status for aggregates without lifecycle.

Describe "report.render_aggregate_terminal lifecycle"
  Include "$BRIK_PIPELINE_LIB/logging.sh"
  Include "$BRIK_PIPELINE_LIB/error.sh"
  Include "$BRIK_TRANSVERSE_LIB/render.sh"
  Include "$BRIK_PIPELINE_LIB/report.sh"

  setup_fixture() {
    LOG_DIR="$(mktemp -d)"
    REPORT_FILE="${LOG_DIR}/aggregate-report.json"
    export BRIK_STAGE_NAME="notify"
    # Aggregate as produced after lifecycle stamping: build success, scan
    # failed, package synthesized not_run (status skipped, no tech, lifecycle
    # carries the truth); notify is the in-flight stage, absent from stages[].
    jq -n '{
      schema_version: "1.1",
      pipeline: { id: "run-x", platform: "gitlab", business: { status: "error" },
                  started_at: "2026-06-02T14:00:00+0000", finished_at: "2026-06-02T14:01:00+0000", status: "failed" },
      stages: [
        { stage: "build",   status: "success", lifecycle: "success", tech: { status: "success" }, business: { status: "success" } },
        { stage: "scan",    status: "failed",  lifecycle: "failed",  tech: { status: "failed" },  business: { status: "error" } },
        { stage: "package", status: "skipped", lifecycle: "not_run", lifecycle_reason: "blocked by upstream failure", business: { status: "success" } }
      ],
      summary: { stages: { total: 3, passed: 1, failed: 1, skipped: 1 } }
    }' > "$REPORT_FILE"
    jq -n '{ schema_version: "v1", stages: (["build","scan","package","notify"] | map({ id: ., decision: "run", reason: "" })) }' \
      > "${LOG_DIR}/plan.json"
  }
  cleanup_fixture() { rm -rf "$LOG_DIR"; unset BRIK_STAGE_NAME; }
  Before 'setup_fixture'
  After 'cleanup_fixture'

  It "renders an upstream-blocked stage as NOT-RUN, not SKIPPED"
    render_it() { report.render_aggregate_terminal "$REPORT_FILE"; }
    When call render_it
    The output should include "NOT-RUN"
    The status should be success
  End

  It "renders the in-flight stage as RUNNING"
    render_it() { report.render_aggregate_terminal "$REPORT_FILE"; }
    When call render_it
    The output should include "RUNNING"
  End

  It "counts the blocked stage under a Not run line, separate from Skipped"
    not_run_line() { report.render_aggregate_terminal "$REPORT_FILE" | grep -iE "not.run"; }
    When call not_run_line
    The output should include "1"
  End
End
