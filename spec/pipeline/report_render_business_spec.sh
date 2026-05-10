Describe "report renderers expose business outcome"
  Include "$BRIK_PIPELINE_LIB/report.sh"
  Include "$BRIK_PIPELINE_LIB/report_html.sh"

  setup_dirs() {
    RB_LOG_DIR="$(mktemp -d)"
    export BRIK_LOG_DIR="$RB_LOG_DIR"
  }
  cleanup_dirs() {
    rm -rf "$RB_LOG_DIR"
    unset BRIK_LOG_DIR
  }

  write_aggregate() {
    local pbs="$1" sc="$2" wc="$3" ec="$4"
    jq -n \
      --arg pbs "$pbs" \
      --argjson sc "$sc" --argjson wc "$wc" --argjson ec "$ec" \
      '{
        schema_version: "1.0",
        pipeline: { id: "p1", platform: "gitlab", project: "demo",
                    context: "snapshot", started_at: "2026-04-21T14:00:00+0000",
                    finished_at: "2026-04-21T14:00:01+0000", status: "success",
                    business: { status: $pbs } },
        stages: [
          { stage: "build", status: "success", duration_ms: 1200,
            tech: { status: "success", exit_code: "0" },
            business: { status: "success", reason: "" }, runner: { platform: "gitlab" } },
          { stage: "lint",  status: "success", duration_ms:  900,
            tech: { status: "success", exit_code: "0" },
            business: { status: "warning", reason: "1 findings ignored by policy" }, runner: { platform: "gitlab" } }
        ],
        summary: {
          stages:   { total: 2, passed: 2, failed: 0, skipped: 0 },
          business: { success_count: $sc, warning_count: $wc, error_count: $ec }
        }
      }' > "${RB_LOG_DIR}/aggregate-report.json"
  }

  Describe "aggregate-report.html"
    Before 'setup_dirs'
    After 'cleanup_dirs'

    It "renders a Business outcome heading"
      do_render() {
        write_aggregate "warning" 1 1 0
        _report._render_html "${RB_LOG_DIR}/aggregate-report.json"
      }
      When call do_render
      The status should be success
      The output should include "Business outcome"
    End

    It "embeds the pipeline.business.status value in the JSON data island"
      do_render() {
        write_aggregate "warning" 1 1 0
        _report._render_html "${RB_LOG_DIR}/aggregate-report.json" \
          | grep -F '"business":{"status":"warning"}'
      }
      When call do_render
      The status should be success
      The output should be present
    End
  End

  Describe "aggregate-report.md (built by _report._render_aggregate_md)"
    Before 'setup_dirs'
    After 'cleanup_dirs'

    It "renders the Business outcome section with the global status"
      do_render() {
        write_aggregate "warning" 1 1 0
        _report._render_aggregate_md "${RB_LOG_DIR}/aggregate-report.json"
      }
      When call do_render
      The output should include "## Business outcome"
      The output should include "warning"
    End

    It "renders the per-bucket counts"
      do_render() {
        write_aggregate "error" 0 1 1
        _report._render_aggregate_md "${RB_LOG_DIR}/aggregate-report.json"
      }
      When call do_render
      The output should include "success=0"
      The output should include "warning=1"
      The output should include "error=1"
    End
  End
End
