Describe "security/iac.sh"
  Include "$BRIK_RUNTIME_LIB/logging.sh"
  Include "$BRIK_RUNTIME_LIB/tools.sh"
  Include "$BRIK_CORE_LIB/_loader.sh"
  Include "$BRIK_CORE_LIB/quality/_tools.sh"
  Include "$BRIK_CORE_LIB/security/iac.sh"
  Include "$BRIK_HOME/runtime/bash/spec/support/mock_helper.sh"

  Describe "security.iac.run"
    It "returns 6 for nonexistent workspace"
      When call security.iac.run "/nonexistent/workspace"
      The status should equal 6
      The stderr should include "required directory not found"
    End

    Describe "Tier 1: command override"
      setup_cmd() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        mock.create_exit "my-iac-scanner" 0
        mock.activate
        export BRIK_SECURITY_IAC_COMMAND="my-iac-scanner"
      }
      cleanup_cmd() {
        unset BRIK_SECURITY_IAC_COMMAND
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_cmd'
      After 'cleanup_cmd'

      It "runs command override"
        When call security.iac.run "$TEST_WS"
        The status should be success
        The stderr should include "IaC scan passed"
      End
    End

    Describe "Tier 2: explicit tool (checkov)"
      setup_tool() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock.log"
        mock.create_logging "checkov" "$MOCK_LOG"
        mock.activate
        export BRIK_SECURITY_IAC_TOOL="checkov"
      }
      cleanup_tool() {
        unset BRIK_SECURITY_IAC_TOOL
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_tool'
      After 'cleanup_tool'

      It "runs checkov"
        invoke_tool() {
          security.iac.run "$TEST_WS" 2>/dev/null || return 1
          grep -q "^checkov" "$MOCK_LOG"
        }
        When call invoke_tool
        The status should be success
      End
    End

    Describe "Tier 2: explicit tool (tfsec)"
      setup_tfsec() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock.log"
        mock.create_logging "tfsec" "$MOCK_LOG"
        mock.activate
        export BRIK_SECURITY_IAC_TOOL="tfsec"
      }
      cleanup_tfsec() {
        unset BRIK_SECURITY_IAC_TOOL
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_tfsec'
      After 'cleanup_tfsec'

      It "runs tfsec"
        invoke_tfsec() {
          security.iac.run "$TEST_WS" 2>/dev/null || return 1
          grep -q "^tfsec" "$MOCK_LOG"
        }
        When call invoke_tfsec
        The status should be success
      End
    End

    Describe "Tier 2: tool not found"
      setup_missing() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        mock.isolate
        export BRIK_SECURITY_IAC_TOOL="checkov"
      }
      cleanup_missing() {
        unset BRIK_SECURITY_IAC_TOOL
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_missing'
      After 'cleanup_missing'

      It "returns 3 when tool not found"
        When call security.iac.run "$TEST_WS"
        The status should equal 3
        The stderr should include "not found"
      End
    End

    Describe "Tier 3: auto-detect checkov"
      setup_auto() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock.log"
        mock.create_logging "checkov" "$MOCK_LOG"
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

      It "auto-detects checkov"
        invoke_auto() {
          security.iac.run "$TEST_WS" 2>/dev/null || return 1
          grep -q "checkov" "$MOCK_LOG"
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
        When call security.iac.run "$TEST_WS"
        The status should be success
        The stderr should include "skipping"
      End
    End

    Describe "Tier 1: command override fails"
      setup_fail() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        mock.create_exit "failing-scanner" 1
        mock.activate
        export BRIK_SECURITY_IAC_COMMAND="failing-scanner"
      }
      cleanup_fail() {
        unset BRIK_SECURITY_IAC_COMMAND
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_fail'
      After 'cleanup_fail'

      It "returns 10 on failure"
        When call security.iac.run "$TEST_WS"
        The status should equal 10
        The stderr should include "IaC security findings detected"
      End
    End
  End
End
