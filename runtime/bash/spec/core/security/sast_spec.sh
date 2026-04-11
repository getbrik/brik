Describe "security/sast.sh"
  Include "$BRIK_RUNTIME_LIB/logging.sh"
  Include "$BRIK_RUNTIME_LIB/tools.sh"
  Include "$BRIK_CORE_LIB/_loader.sh"
  Include "$BRIK_CORE_LIB/quality/_tools.sh"
  Include "$BRIK_CORE_LIB/security/sast.sh"
  Include "$BRIK_HOME/runtime/bash/spec/support/mock_helper.sh"

  Describe "security.sast.run"
    It "returns 6 for nonexistent workspace"
      When call security.sast.run "/nonexistent/workspace"
      The status should equal 6
      The stderr should include "required directory not found"
    End

    Describe "Tier 1: command override"
      setup_cmd() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        mock.create_exit "my-sast" 0
        mock.activate
        export BRIK_SECURITY_SAST_COMMAND="my-sast"
      }
      cleanup_cmd() {
        unset BRIK_SECURITY_SAST_COMMAND
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_cmd'
      After 'cleanup_cmd'

      It "runs command override"
        When call security.sast.run "$TEST_WS"
        The status should be success
        The stderr should include "SAST passed"
      End
    End

    Describe "Tier 1: command fails"
      setup_cmd_fail() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        mock.create_exit "failing-sast" 1
        mock.activate
        export BRIK_SECURITY_SAST_COMMAND="failing-sast"
      }
      cleanup_cmd_fail() {
        unset BRIK_SECURITY_SAST_COMMAND
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_cmd_fail'
      After 'cleanup_cmd_fail'

      It "returns 10 on failure"
        When call security.sast.run "$TEST_WS"
        The status should equal 10
        The stderr should include "SAST findings detected"
      End
    End

    Describe "Tier 2: explicit tool semgrep"
      setup_tool() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock.log"
        mock.create_logging "semgrep" "$MOCK_LOG"
        mock.activate
        export BRIK_SECURITY_SAST_TOOL="semgrep"
      }
      cleanup_tool() {
        unset BRIK_SECURITY_SAST_TOOL BRIK_SECURITY_SAST_RULESET
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_tool'
      After 'cleanup_tool'

      It "runs semgrep with auto config"
        invoke_tool() {
          security.sast.run "$TEST_WS" 2>/dev/null || return 1
          grep -q "semgrep scan --config auto" "$MOCK_LOG"
        }
        When call invoke_tool
        The status should be success
      End

      It "uses custom ruleset when configured"
        invoke_with_ruleset() {
          export BRIK_SECURITY_SAST_RULESET="p/owasp-top-ten"
          security.sast.run "$TEST_WS" 2>/dev/null || return 1
          grep -q "semgrep scan --config p/owasp-top-ten" "$MOCK_LOG"
        }
        When call invoke_with_ruleset
        The status should be success
      End
    End

    Describe "Tier 2: tool not found"
      setup_missing() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        mock.isolate
        export BRIK_SECURITY_SAST_TOOL="semgrep"
      }
      cleanup_missing() {
        unset BRIK_SECURITY_SAST_TOOL
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_missing'
      After 'cleanup_missing'

      It "returns 3 when tool not found"
        When call security.sast.run "$TEST_WS"
        The status should equal 3
        The stderr should include "not found"
      End
    End

    Describe "Tier 2: tool fails"
      setup_tool_fail() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        mock.create_exit "semgrep" 1
        mock.activate
        export BRIK_SECURITY_SAST_TOOL="semgrep"
      }
      cleanup_tool_fail() {
        unset BRIK_SECURITY_SAST_TOOL
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_tool_fail'
      After 'cleanup_tool_fail'

      It "returns 10 when tool finds issues"
        When call security.sast.run "$TEST_WS"
        The status should equal 10
        The stderr should include "SAST findings detected"
      End
    End

    Describe "Tier 3: auto-detect semgrep"
      setup_auto() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock.log"
        mock.create_logging "semgrep" "$MOCK_LOG"
        ln -sf "$(command -v bash)" "${MOCK_BIN}/bash"
        ln -sf "$(command -v grep)" "${MOCK_BIN}/grep"
        mock.isolate
      }
      cleanup_auto() {
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_auto'
      After 'cleanup_auto'

      It "auto-detects semgrep"
        invoke_auto() {
          security.sast.run "$TEST_WS" 2>/dev/null || return 1
          grep -q "semgrep" "$MOCK_LOG"
        }
        When call invoke_auto
        The status should be success
      End
    End

    Describe "no tool available"
      setup_none() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        mock.isolate
      }
      cleanup_none() {
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_none'
      After 'cleanup_none'

      It "skips when no tool available"
        When call security.sast.run "$TEST_WS"
        The status should be success
        The stderr should include "skipping"
      End
    End
  End
End
