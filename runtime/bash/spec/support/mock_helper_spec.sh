Describe "mock_helper.sh API"
  Include "$BRIK_HOME/runtime/bash/spec/support/mock_helper.sh"

  # -- Core lifecycle -------------------------------------------------------

  Describe "mock.setup / mock.cleanup"
    It "creates MOCK_BIN directory and MOCK_LOG file"
      setup_lifecycle() {
        mock.setup
        [ -d "$MOCK_BIN" ] && [ -f "$MOCK_LOG" ]
      }
      When call setup_lifecycle
      The status should be success
      The variable MOCK_BIN should be present
      The variable MOCK_LOG should be present
    End

    It "cleans up on mock.cleanup"
      lifecycle_cleanup() {
        mock.setup
        local saved_dir="$MOCK_BIN"
        mock.cleanup
        [ ! -d "$saved_dir" ] && [ -z "$MOCK_BIN" ] && [ -z "$MOCK_LOG" ]
      }
      When call lifecycle_cleanup
      The status should be success
    End
  End

  # -- Simple mock creation -------------------------------------------------

  Describe "mock.create"
    Before 'mock.setup'
    After 'mock.cleanup'

    It "creates an executable that logs to MOCK_LOG"
      test_create() {
        mock.create "mytool"
        [ -x "${MOCK_BIN}/mytool" ] && "${MOCK_BIN}/mytool" hello world
        grep -q "^mytool hello world$" "$MOCK_LOG"
      }
      When call test_create
      The status should be success
    End
  End

  Describe "mock.create_failing"
    Before 'mock.setup'
    After 'mock.cleanup'

    It "creates an executable that exits 1 and logs"
      test_failing() {
        mock.create_failing "badtool"
        "${MOCK_BIN}/badtool" arg1 2>/dev/null || local rc=$?
        [ "$rc" -eq 1 ] && grep -q "^badtool arg1$" "$MOCK_LOG"
      }
      When call test_failing
      The status should be success
    End
  End

  Describe "mock.create_output"
    Before 'mock.setup'
    After 'mock.cleanup'

    It "creates a mock that echoes fixed text"
      test_output() {
        mock.create_output "greeter" "hello from mock" 0
        local out
        out="$("${MOCK_BIN}/greeter" 2>/dev/null)"
        [ "$out" = "hello from mock" ]
      }
      When call test_output
      The status should be success
    End

    It "supports custom exit code"
      test_output_exit() {
        mock.create_output "fail_greeter" "goodbye" 42
        "${MOCK_BIN}/fail_greeter" >/dev/null 2>&1 || local rc=$?
        [ "$rc" -eq 42 ]
      }
      When call test_output_exit
      The status should be success
    End
  End

  Describe "mock.create_echo"
    Before 'mock.setup'
    After 'mock.cleanup'

    It "echoes 'mock <name>: <args>' to stdout"
      test_echo() {
        mock.create_echo "npm"
        local out
        out="$("${MOCK_BIN}/npm" install lodash 2>/dev/null)"
        [ "$out" = "mock npm: install lodash" ]
      }
      When call test_echo
      The status should be success
    End
  End

  Describe "mock.create_logging"
    Before 'mock.setup'
    After 'mock.cleanup'

    It "logs calls to a custom log file via printf"
      test_logging() {
        local custom_log="${MOCK_BIN}/custom.log"
        mock.create_logging "ruff" "$custom_log"
        "${MOCK_BIN}/ruff" check src/
        grep -q "^ruff check src/$" "$custom_log"
      }
      When call test_logging
      The status should be success
    End
  End

  Describe "mock.create_exit"
    Before 'mock.setup'
    After 'mock.cleanup'

    It "creates a silent mock with custom exit code"
      test_exit() {
        mock.create_exit "node" 0
        "${MOCK_BIN}/node" --version 2>/dev/null
      }
      When call test_exit
      The status should be success
    End

    It "supports non-zero exit codes"
      test_exit_fail() {
        mock.create_exit "broken" 3
        "${MOCK_BIN}/broken" 2>/dev/null || local rc=$?
        [ "$rc" -eq 3 ]
      }
      When call test_exit_fail
      The status should be success
    End
  End

  # -- Advanced mock creation -----------------------------------------------

  Describe "mock.create_script"
    Before 'mock.setup'
    After 'mock.cleanup'

    It "creates a mock with custom body"
      test_script() {
        mock.create_script "npm" '
          if [ "$1" = "install" ]; then
            echo "installing"
            exit 0
          fi
          exit 1
        '
        local out
        out="$("${MOCK_BIN}/npm" install 2>/dev/null)"
        [ "$out" = "installing" ]
      }
      When call test_script
      The status should be success
    End

    It "runs the custom body faithfully"
      test_script_branch() {
        mock.create_script "npm" '
          if [ "$1" = "install" ]; then exit 0; fi
          exit 1
        '
        "${MOCK_BIN}/npm" test 2>/dev/null || local rc=$?
        [ "$rc" -eq 1 ]
      }
      When call test_script_branch
      The status should be success
    End
  End

  # -- Batch creation -------------------------------------------------------

  Describe "mock.create_many"
    Before 'mock.setup'
    After 'mock.cleanup'

    It "creates multiple silent mocks"
      test_many() {
        mock.create_many "git" "curl" "wget"
        [ -x "${MOCK_BIN}/git" ] && [ -x "${MOCK_BIN}/curl" ] && [ -x "${MOCK_BIN}/wget" ]
      }
      When call test_many
      The status should be success
    End
  End

  Describe "mock.create_many_echo"
    Before 'mock.setup'
    After 'mock.cleanup'

    It "creates multiple echo mocks"
      test_many_echo() {
        mock.create_many_echo "npm" "npx" "node"
        local out
        out="$("${MOCK_BIN}/npx" vitest 2>/dev/null)"
        [ "$out" = "mock npx: vitest" ]
      }
      When call test_many_echo
      The status should be success
    End
  End

  Describe "mock.pipeline_tools"
    Before 'mock.setup'
    After 'mock.cleanup'

    It "creates all standard pipeline mocks"
      test_pipeline() {
        mock.pipeline_tools
        [ -x "${MOCK_BIN}/npm" ] && \
        [ -x "${MOCK_BIN}/node" ] && \
        [ -x "${MOCK_BIN}/npx" ] && \
        [ -x "${MOCK_BIN}/semgrep" ] && \
        [ -x "${MOCK_BIN}/osv-scanner" ] && \
        [ -x "${MOCK_BIN}/gitleaks" ]
      }
      When call test_pipeline
      The status should be success
    End

    It "npm echoes mock output"
      test_pipeline_npm() {
        mock.pipeline_tools
        local out
        out="$("${MOCK_BIN}/npm" install 2>/dev/null)"
        [ "$out" = "mock npm: install" ]
      }
      When call test_pipeline_npm
      The status should be success
    End

    It "node exits silently with 0"
      test_pipeline_node() {
        mock.pipeline_tools
        local out
        out="$("${MOCK_BIN}/node" --version 2>/dev/null)"
        [ -z "$out" ]
      }
      When call test_pipeline_node
      The status should be success
    End
  End

  # -- Assertions -----------------------------------------------------------

  Describe "mock.was_called"
    Before 'mock.setup'
    After 'mock.cleanup'

    It "returns true when mock was invoked"
      test_was_called() {
        mock.create "git"
        "${MOCK_BIN}/git" status
        mock.was_called "git"
      }
      When call test_was_called
      The status should be success
    End

    It "returns false when mock was not invoked"
      test_not_called() {
        mock.create "git"
        mock.was_called "git"
      }
      When call test_not_called
      The status should be failure
    End
  End

  Describe "mock.call_args"
    Before 'mock.setup'
    After 'mock.cleanup'

    It "returns the last invocation arguments"
      test_call_args() {
        mock.create "git"
        "${MOCK_BIN}/git" add .
        "${MOCK_BIN}/git" commit -m "test"
        local args
        args="$(mock.call_args "git")"
        [ "$args" = "commit -m test" ]
      }
      When call test_call_args
      The status should be success
    End
  End

  Describe "mock.call_count"
    Before 'mock.setup'
    After 'mock.cleanup'

    It "counts invocations"
      test_call_count() {
        mock.create "curl"
        "${MOCK_BIN}/curl" http://a
        "${MOCK_BIN}/curl" http://b
        "${MOCK_BIN}/curl" http://c
        local count
        count="$(mock.call_count "curl")"
        [ "$count" -eq 3 ]
      }
      When call test_call_count
      The status should be success
    End

    It "returns 0 when not called"
      test_call_count_zero() {
        mock.create "curl"
        local count
        count="$(mock.call_count "curl")"
        [ "$count" -eq 0 ]
      }
      When call test_call_count_zero
      The status should be success
    End
  End

  # -- PATH management ------------------------------------------------------

  Describe "mock.activate"
    Before 'mock.setup'
    After 'mock.cleanup'

    It "prepends MOCK_BIN to PATH"
      test_activate() {
        mock.activate
        local first_dir="${PATH%%:*}"
        [ "$first_dir" = "$MOCK_BIN" ]
      }
      When call test_activate
      The status should be success
    End
  End

  Describe "mock.isolate"
    Before 'mock.setup'
    After 'mock.cleanup'

    It "sets PATH to MOCK_BIN only"
      test_isolate() {
        mock.isolate
        [ "$PATH" = "$MOCK_BIN" ]
      }
      When call test_isolate
      The status should be success
    End
  End

  Describe "mock.preserve_cmds"
    Before 'mock.setup'
    After 'mock.cleanup'

    It "symlinks essential commands into MOCK_BIN"
      test_preserve() {
        mock.preserve_cmds
        [ -e "${MOCK_BIN}/grep" ] && [ -e "${MOCK_BIN}/sed" ] && [ -e "${MOCK_BIN}/cat" ]
      }
      When call test_preserve
      The status should be success
    End

    It "does not overwrite existing mocks"
      test_preserve_no_overwrite() {
        mock.create "grep"
        local before after
        before="$(cat "${MOCK_BIN}/grep")"
        mock.preserve_cmds
        after="$(cat "${MOCK_BIN}/grep")"
        [ "$before" = "$after" ]
      }
      When call test_preserve_no_overwrite
      The status should be success
    End
  End

  # -- Workspace helpers ----------------------------------------------------

  Describe "mock.workspace"
    It "creates a temporary directory"
      test_workspace() {
        local ws
        ws="$(mock.workspace)"
        [ -d "$ws" ] && rm -rf "$ws"
      }
      When call test_workspace
      The status should be success
    End
  End
End
