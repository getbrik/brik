Describe "report.render_terminal"
  # Terminal-friendly recap rendered from aggregate-report.json on stdout.
  # Extracted from the former brik.local.print_summary in P3 of the
  # lib-soc-cleanup chantier so the rendering concern lives next to the
  # other report.* helpers (md/json/html) rather than in the local wrapper.
  Include "$BRIK_PIPELINE_LIB/logging.sh"
  Include "$BRIK_PIPELINE_LIB/error.sh"
  Include "$BRIK_PIPELINE_LIB/report.sh"

  setup_fixture() {
    REPORT_FILE="$(mktemp)"
    jq -n '{
      pipeline_id: "run-fixture",
      started_at: "2026-01-01T00:00:00+0000",
      finished_at: "2026-01-01T00:00:05+0000",
      stages: [
        { name: "init",  tech: { status: "success", duration_ms: "1000" }, business: {} },
        { name: "build", tech: { status: "success", duration_ms: "2000" }, business: {} },
        { name: "lint",  tech: { status: "skipped" },                       business: {} }
      ]
    }' > "$REPORT_FILE"
  }
  cleanup_fixture() { rm -f "$REPORT_FILE"; }
  Before 'setup_fixture'
  After 'cleanup_fixture'

  It "is defined as a function"
    callable_check() { declare -f report.render_terminal >/dev/null; }
    When call callable_check
    The status should be success
  End

  It "prints the pass/skip counts on a passing run"
    check_summary() {
      local output
      output="$(report.render_terminal "$REPORT_FILE")"
      if echo "$output" | grep -qF "2/2 passed" && echo "$output" | grep -qF "1 skipped"; then
        echo "correct"
      else
        echo "wrong: $output"
      fi
    }
    When call check_summary
    The output should equal "correct"
  End

  It "shows FAIL when any stage failed"
    check_fail() {
      local report
      report="$(mktemp)"
      jq -n '{
        pipeline_id: "run-fail",
        started_at: "2026-01-01T00:00:00+0000",
        finished_at: "2026-01-01T00:00:02+0000",
        stages: [
          { name: "init",  tech: { status: "success", duration_ms: "1000" }, business: {} },
          { name: "build", tech: { status: "failed",  duration_ms: "2000" }, business: {} }
        ]
      }' > "$report"
      local output
      output="$(report.render_terminal "$report")"
      rm -f "$report"
      if echo "$output" | grep -qF "FAIL"; then
        echo "shows_fail"
      else
        echo "no_fail"
      fi
    }
    When call check_fail
    The output should equal "shows_fail"
  End

  It "reports the correct counts across success / failed / skipped stages"
    check_all_states() {
      local report
      report="$(mktemp)"
      jq -n '{
        pipeline_id: "run-mixed",
        started_at: "2026-01-01T00:00:00+0000",
        finished_at: "2026-01-01T00:00:04+0000",
        stages: [
          { name: "init",  tech: { status: "success", duration_ms: "1000" }, business: {} },
          { name: "build", tech: { status: "failed",  duration_ms: "2000" }, business: {} },
          { name: "lint",  tech: { status: "success", duration_ms: "1000" }, business: {} },
          { name: "scan",  tech: { status: "skipped" },                       business: {} }
        ]
      }' > "$report"
      local output
      output="$(report.render_terminal "$report")"
      rm -f "$report"
      if echo "$output" | grep -qF "2/3 passed" && echo "$output" | grep -qF "1 skipped"; then
        echo "correct"
      else
        echo "wrong: $output"
      fi
    }
    When call check_all_states
    The output should equal "correct"
  End

  It "returns BRIK_EXIT_IO_FAILURE when the report path does not exist"
    When call report.render_terminal "/nonexistent/aggregate-report.json"
    The status should equal 6
    The error should include "pipeline report not found"
  End

  It "defaults to \$BRIK_LOG_DIR/aggregate-report.json when called without arguments"
    check_default_path() {
      local prev_log_dir="${BRIK_LOG_DIR:-}"
      BRIK_LOG_DIR="$(mktemp -d)"
      export BRIK_LOG_DIR
      cp "$REPORT_FILE" "$BRIK_LOG_DIR/aggregate-report.json"
      local output
      output="$(report.render_terminal)"
      rm -rf "$BRIK_LOG_DIR"
      export BRIK_LOG_DIR="$prev_log_dir"
      if echo "$output" | grep -qF "2/2 passed"; then
        echo "ok"
      else
        echo "wrong: $output"
      fi
    }
    When call check_default_path
    The output should equal "ok"
  End
End
