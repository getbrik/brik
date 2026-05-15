Describe "_brik.log_dir._resolve"
  Include "$BRIK_PIPELINE_LIB/logging.sh"
  Include "$BRIK_HOME/spec/support/mock_helper.sh"

  setup_workspace() {
    mock.workspace.setup
    LOGRES_WS="$BRIK_WORKSPACE"
    unset BRIK_LOG_DIR
  }
  Before 'setup_workspace'
  After 'mock.workspace.teardown'

  It "honors a pre-exported BRIK_LOG_DIR (highest precedence)"
    run_resolve_with_override() {
      export BRIK_LOG_DIR="/custom/log/dir"
      _brik.log_dir._resolve
    }
    When call run_resolve_with_override
    The output should equal "/custom/log/dir"
  End

  It "derives from BRIK_WORKSPACE when BRIK_LOG_DIR is unset"
    run_resolve_derived() {
      _brik.log_dir._resolve
    }
    When call run_resolve_derived
    The output should equal "$LOGRES_WS/.brik-logs"
  End

  It "falls back to /tmp/brik/logs when BRIK_WORKSPACE and BRIK_LOG_DIR are both unset"
    run_resolve_fallback() {
      unset BRIK_WORKSPACE
      _brik.log_dir._resolve
    }
    When call run_resolve_fallback
    The output should equal "/tmp/brik/logs"
  End

  It "treats an empty BRIK_LOG_DIR as unset (derives from workspace)"
    run_resolve_empty_var() {
      export BRIK_LOG_DIR=""
      _brik.log_dir._resolve
    }
    When call run_resolve_empty_var
    The output should equal "$LOGRES_WS/.brik-logs"
  End
End
