Describe "report.read"
  Include "$BRIK_PIPELINE_LIB/report.sh"

  setup_report_dir() {
    REPORT_LOG_DIR="$(mktemp -d)"
    export BRIK_LOG_DIR="$REPORT_LOG_DIR"
    export BRIK_RUN_ID="run-fixture-read"
  }
  cleanup_report_dir() {
    rm -rf "$REPORT_LOG_DIR"
    unset BRIK_RUN_ID
  }
  Before 'setup_report_dir'
  After 'cleanup_report_dir'

  It "returns the value recorded under stage/category/key"
    write_then_read() {
      report.init || return 1
      report.record "release" "env" "BRIK_APP_VERSION" "1.2.3" || return 1
      report.read   "release" "env" "BRIK_APP_VERSION"
    }
    When call write_then_read
    The output should equal "1.2.3"
  End

  It "returns the default when the key is absent"
    read_with_default() {
      report.init || return 1
      report.read "release" "env" "MISSING_KEY" "fallback-value"
    }
    When call read_with_default
    The output should equal "fallback-value"
  End

  It "returns empty when no default is given and the key is absent"
    read_without_default() {
      report.init || return 1
      report.read "release" "env" "MISSING_KEY"
    }
    When call read_without_default
    The output should equal ""
    The status should be success
  End

  It "reads tech and business categories too"
    read_other_categories() {
      report.init || return 1
      report.record "build" "tech"     "status"           "success" || return 1
      report.record "init"  "business" "project_name"     "myapp"   || return 1
      printf '%s|%s' \
        "$(report.read build tech status)" \
        "$(report.read init  business project_name)"
    }
    When call read_other_categories
    The output should equal "success|myapp"
  End

  It "rejects an unknown category"
    When call report.read "init" "runtime" "FOO"
    The status should equal "$BRIK_EXIT_INVALID_INPUT"
    The error should be present
  End

  It "fails when the backend is missing"
    When call report.read "init" "env" "FOO"
    The status should equal "$BRIK_EXIT_IO_FAILURE"
    The error should be present
  End

  It "rejects when called with too few arguments"
    When call report.read "init" "env"
    The status should equal "$BRIK_EXIT_INVALID_INPUT"
    The error should be present
  End

  It "preserves whitespace in returned values"
    read_ws_value() {
      report.init || return 1
      report.record "init" "env" "GREETING" "hello world" || return 1
      report.read   "init" "env" "GREETING"
    }
    When call read_ws_value
    The output should equal "hello world"
  End
End
