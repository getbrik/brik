Describe "quality/format.sh"
  Include "$BRIK_RUNTIME_LIB/logging.sh"
  Include "$BRIK_RUNTIME_LIB/tools.sh"
  Include "$BRIK_CORE_LIB/quality/format.sh"
  Include "$BRIK_HOME/runtime/bash/spec/support/mock_helper.sh"

  Describe "quality.format.run"
    It "returns 6 for nonexistent workspace"
      When call quality.format.run "/nonexistent/workspace"
      The status should equal 6
      The stderr should include "required directory not found"
    End

    Describe "unknown option"
      setup_ws() { TEST_WS="$(mktemp -d)"; }
      cleanup_ws() { rm -rf "$TEST_WS"; }
      Before 'setup_ws'
      After 'cleanup_ws'

      It "returns 2 for unknown option"
        When call quality.format.run "$TEST_WS" --badopt
        The status should equal 2
        The stderr should include "unknown option"
      End
    End

    Describe "Tier 1: BRIK_QUALITY_FORMAT_COMMAND override"
      setup_cmd_override() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        mock.create_script "prettier" 'printf "prettier %s\n" "$*"
exit 0'
        mock.activate
        export BRIK_QUALITY_FORMAT_COMMAND="prettier --check ."
      }
      cleanup_cmd_override() {
        unset BRIK_QUALITY_FORMAT_COMMAND
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_cmd_override'
      After 'cleanup_cmd_override'

      It "uses BRIK_QUALITY_FORMAT_COMMAND as Tier 1 override"
        When call quality.format.run "$TEST_WS"
        The status should be success
        The stdout should be present
        The stderr should include "format check passed"
      End
    End

    Describe "Tier 2: BRIK_QUALITY_FORMAT_TOOL selection"
      setup_tool_selection() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock.log"
        printf '{"name":"test"}\n' > "${TEST_WS}/package.json"
        mock.create_logging "npx" "$MOCK_LOG"
        mock.activate
        export BRIK_QUALITY_FORMAT_TOOL="prettier"
      }
      cleanup_tool_selection() {
        unset BRIK_QUALITY_FORMAT_TOOL
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_tool_selection'
      After 'cleanup_tool_selection'

      It "uses prettier when BRIK_QUALITY_FORMAT_TOOL=prettier"
        invoke_check() {
          quality.format.run "$TEST_WS" 2>/dev/null || return 1
          grep -q "prettier" "$MOCK_LOG"
        }
        When call invoke_check
        The status should be success
      End
    End

    Describe "Tier 3: auto-detect for Node.js"
      setup_node_fmt() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock.log"
        printf '{"name":"test"}\n' > "${TEST_WS}/package.json"
        mock.create_logging "npx" "$MOCK_LOG"
        mock.activate
      }
      cleanup_node_fmt() {
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_node_fmt'
      After 'cleanup_node_fmt'

      It "auto-detects prettier for Node.js"
        invoke_auto() {
          quality.format.run "$TEST_WS" 2>/dev/null || return 1
          grep -q "prettier" "$MOCK_LOG"
        }
        When call invoke_auto
        The status should be success
      End
    End

    Describe "Tier 3: auto-detect for Python"
      setup_py_fmt() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock.log"
        printf '[project]\nname = "test"\n' > "${TEST_WS}/pyproject.toml"
        mock.create_logging "ruff" "$MOCK_LOG"
        mock.activate
      }
      cleanup_py_fmt() {
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_py_fmt'
      After 'cleanup_py_fmt'

      It "auto-detects ruff format for Python"
        invoke_py_auto() {
          quality.format.run "$TEST_WS" 2>/dev/null || return 1
          grep -q "ruff format" "$MOCK_LOG"
        }
        When call invoke_py_auto
        The status should be success
      End
    End

    Describe "Tier 3: auto-detect for Rust"
      setup_rust_fmt() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock.log"
        printf '[package]\nname = "test"\n' > "${TEST_WS}/Cargo.toml"
        mock.create_logging "cargo" "$MOCK_LOG"
        mock.activate
      }
      cleanup_rust_fmt() {
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_rust_fmt'
      After 'cleanup_rust_fmt'

      It "auto-detects rustfmt via cargo for Rust"
        invoke_rust_fmt() {
          quality.format.run "$TEST_WS" 2>/dev/null || return 1
          grep -q "cargo fmt" "$MOCK_LOG"
        }
        When call invoke_rust_fmt
        The status should be success
      End
    End

    Describe "Tier 1: command failure returns 10"
      setup_cmd_fail() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        mock.create_exit "failing-fmt" 1
        mock.activate
        export BRIK_QUALITY_FORMAT_COMMAND="failing-fmt"
      }
      cleanup_cmd_fail() {
        unset BRIK_QUALITY_FORMAT_COMMAND
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_cmd_fail'
      After 'cleanup_cmd_fail'

      It "returns 10 when Tier 1 command fails"
        When call quality.format.run "$TEST_WS"
        The status should equal 10
        The stderr should include "format violations found"
      End
    End

    Describe "--check option accepted"
      setup_check() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        printf '{"name":"test"}\n' > "${TEST_WS}/package.json"
        mock.create_exit "npx" 0
        mock.activate
      }
      cleanup_check() {
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_check'
      After 'cleanup_check'

      It "accepts --check without error"
        When call quality.format.run "$TEST_WS" --check
        The status should be success
        The stderr should include "format check passed"
      End
    End
  End
End
