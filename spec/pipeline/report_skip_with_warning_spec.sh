Describe "stage.skip_with_warning + summary.warnings"
  Include "$BRIK_PIPELINE_LIB/stage.sh"
  Include "$BRIK_PIPELINE_LIB/report.sh"
  Include "$BRIK_HOME/spec/support/mock_helper.sh"

  setup_dirs() {
    REPORT_LOG_DIR="$(mktemp -d)"
    export BRIK_LOG_DIR="$REPORT_LOG_DIR"
    mock.workspace.setup
    REPORT_WORKSPACE="$BRIK_WORKSPACE"
    export BRIK_RUN_ID="run-skip-warning-fixture"
    unset BRIK_PLATFORM BRIK_RUNNER_IMAGE CI_JOB_URL BUILD_URL
  }
  cleanup_dirs() {
    rm -rf "$REPORT_LOG_DIR"
    mock.workspace.teardown
    unset BRIK_LOG_DIR BRIK_RUN_ID
    unset BRIK_PLATFORM BRIK_RUNNER_IMAGE CI_JOB_URL BUILD_URL
  }

  # ---------------------------------------------------------------------------
  # stage.skip_with_warning helper
  # ---------------------------------------------------------------------------
  Describe "stage.skip_with_warning"
    Before 'setup_dirs'
    After 'cleanup_dirs'

    It "returns BRIK_EXIT_INVALID_INPUT when arity is wrong"
      wrong_arity() {
        report.init >/dev/null 2>&1
        stage.skip_with_warning "lint"
      }
      When call wrong_arity
      The status should equal "$BRIK_EXIT_INVALID_INPUT"
      The stderr should include "expects 2 arguments"
    End

    It "returns BRIK_EXIT_SKIP_WITH_WARNING (99) on valid call"
      skip_lint() {
        report.init >/dev/null 2>&1
        stage.skip_with_warning "lint" "user disabled outside release"
      }
      When call skip_lint
      The status should equal 99
      The status should equal "$BRIK_EXIT_SKIP_WITH_WARNING"
      The stderr should include "skipped with warning"
    End

    It "logs a warn with the reason"
      skip_with_log() {
        report.init >/dev/null 2>&1
        stage.skip_with_warning "lint" "user disabled outside release"
      }
      When call skip_with_log
      The status should equal "$BRIK_EXIT_SKIP_WITH_WARNING"
      The stderr should include "lint"
      The stderr should include "user disabled outside release"
    End

    It "records tech.status=skipped on the backend"
      skip_record_status() {
        report.init >/dev/null 2>&1
        stage.skip_with_warning "sast" "user disabled outside release" >/dev/null 2>&1
        jq -r '.stages[] | select(.name=="sast") | .tech.status' \
            "${BRIK_LOG_DIR}/aggregate-report.json"
      }
      When call skip_record_status
      The output should equal "skipped"
    End

    It "records tech.warning=true on the backend"
      skip_record_warning() {
        report.init >/dev/null 2>&1
        stage.skip_with_warning "scan" "user disabled outside release" >/dev/null 2>&1
        jq -r '.stages[] | select(.name=="scan") | .tech.warning' \
            "${BRIK_LOG_DIR}/aggregate-report.json"
      }
      When call skip_record_warning
      The output should equal "true"
    End

    It "records tech.warning_reason with the reason text"
      skip_record_reason() {
        report.init >/dev/null 2>&1
        stage.skip_with_warning "scan" "user disabled outside release" >/dev/null 2>&1
        jq -r '.stages[] | select(.name=="scan") | .tech.warning_reason' \
            "${BRIK_LOG_DIR}/aggregate-report.json"
      }
      When call skip_record_reason
      The output should equal "user disabled outside release"
    End
  End

End
