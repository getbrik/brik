Describe "_notify._emit_recap_table includes business per stage"
  Include "$BRIK_PIPELINE_LIB/logging.sh"
  Include "$BRIK_PIPELINE_LIB/tools.sh"
  Include "$BRIK_TRANSVERSE_LIB/env.sh"
  Include "$BRIK_TRANSVERSE_LIB/format.sh"
  Include "$BRIK_STAGES_LIB/notify.sh"

  brik.use() { :; }

  setup_dirs() {
    RC_LOG_DIR="$(mktemp -d)"
    export BRIK_LOG_DIR="$RC_LOG_DIR"
  }
  cleanup_dirs() {
    rm -rf "$RC_LOG_DIR"
    unset BRIK_LOG_DIR
  }

  write_aggregate_two_stages() {
    cat > "${RC_LOG_DIR}/aggregate-report.json" <<'JSON'
{
  "schema_version": "1.0",
  "pipeline": { "id": "p1", "platform": "gitlab", "project": "demo",
                "context": "snapshot", "started_at": "2026-04-21T14:00:00+0000",
                "finished_at": "2026-04-21T14:00:01+0000", "status": "success",
                "business": { "status": "warning" } },
  "stages": [
    { "stage": "build", "status": "success", "duration_ms": 1200,
      "tech": { "status": "success", "exit_code": "0" },
      "business": { "status": "success", "reason": "" },
      "runner": { "platform": "gitlab" } },
    { "stage": "lint", "status": "success", "duration_ms": 900,
      "tech": { "status": "success", "exit_code": "0" },
      "business": { "status": "warning", "reason": "1 findings ignored by policy" },
      "runner": { "platform": "gitlab" } }
  ],
  "summary": {
    "stages": { "total": 2, "passed": 2, "failed": 0, "skipped": 0 },
    "business": { "success_count": 1, "warning_count": 1, "error_count": 0 }
  }
}
JSON
  }

  Describe "recap table"
    Before 'setup_dirs'
    After 'cleanup_dirs'

    It "renders a Business header column"
      do_recap() {
        write_aggregate_two_stages
        _notify._emit_recap_table "${RC_LOG_DIR}/aggregate-report.json"
      }
      When call do_recap
      The stderr should include "Business"
    End

    It "renders the business status of each stage row"
      do_recap() {
        write_aggregate_two_stages
        _notify._emit_recap_table "${RC_LOG_DIR}/aggregate-report.json"
      }
      When call do_recap
      The stderr should include "warning"
      The stderr should include "success"
      The stderr should include "build"
      The stderr should include "lint"
    End
  End
End
