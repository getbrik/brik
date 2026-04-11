Describe "security/deps.sh"
  Include "$BRIK_RUNTIME_LIB/logging.sh"
  Include "$BRIK_RUNTIME_LIB/tools.sh"
  Include "$BRIK_CORE_LIB/_loader.sh"
  Include "$BRIK_CORE_LIB/quality/_tools.sh"
  Include "$BRIK_CORE_LIB/security/deps.sh"
  Include "$BRIK_HOME/runtime/bash/spec/support/mock_helper.sh"

  Describe "security.deps.run"
    It "returns 6 for nonexistent workspace"
      When call security.deps.run "/nonexistent/workspace"
      The status should equal 6
      The stderr should include "required directory not found"
    End

    Describe "Tier 1: command override"
      setup_cmd() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        mock.create_exit "my-scanner" 0
        mock.activate
        export BRIK_SECURITY_DEPS_COMMAND="my-scanner"
      }
      cleanup_cmd() {
        unset BRIK_SECURITY_DEPS_COMMAND
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_cmd'
      After 'cleanup_cmd'

      It "runs command override"
        When call security.deps.run "$TEST_WS"
        The status should be success
        The stderr should include "security dependency scan passed"
      End
    End

    Describe "Tier 2: explicit tool"
      setup_tool() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock.log"
        mock.create_logging "grype" "$MOCK_LOG"
        mock.activate
        export BRIK_SECURITY_DEPS_TOOL="grype"
      }
      cleanup_tool() {
        unset BRIK_SECURITY_DEPS_TOOL
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_tool'
      After 'cleanup_tool'

      It "runs specified tool"
        invoke_tool() {
          security.deps.run "$TEST_WS" 2>/dev/null || return 1
          grep -q "^grype" "$MOCK_LOG"
        }
        When call invoke_tool
        The status should be success
      End
    End

    Describe "Tier 2: osv-scanner no package sources"
      setup_no_sources() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        mock.create_script "osv-scanner" 'echo "No package sources found, --help for usage information."
exit 128'
        mock.activate
        export BRIK_SECURITY_DEPS_TOOL="osv-scanner"
      }
      cleanup_no_sources() {
        unset BRIK_SECURITY_DEPS_TOOL
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_no_sources'
      After 'cleanup_no_sources'

      It "skips when osv-scanner finds no package sources"
        When call security.deps.run "$TEST_WS"
        The status should be success
        The stderr should include "no package sources found"
      End
    End

    Describe "Tier 2: tool finds vulnerabilities"
      setup_vuln() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        mock.create_script "osv-scanner" 'echo "Found 3 vulnerabilities"
exit 1'
        mock.activate
        export BRIK_SECURITY_DEPS_TOOL="osv-scanner"
      }
      cleanup_vuln() {
        unset BRIK_SECURITY_DEPS_TOOL
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_vuln'
      After 'cleanup_vuln'

      It "returns 10 when vulnerabilities found"
        When call security.deps.run "$TEST_WS"
        The status should equal 10
        The stderr should include "security dependency vulnerabilities found"
      End
    End

    Describe "Tier 2: tool not found"
      setup_missing() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        mock.isolate
        export BRIK_SECURITY_DEPS_TOOL="grype"
      }
      cleanup_missing() {
        unset BRIK_SECURITY_DEPS_TOOL
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_missing'
      After 'cleanup_missing'

      It "returns 3 when tool not found"
        When call security.deps.run "$TEST_WS"
        The status should equal 3
        The stderr should include "not found"
      End
    End

    Describe "Tier 3: auto-detect osv-scanner"
      setup_auto() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock.log"
        mock.create_logging "osv-scanner" "$MOCK_LOG"
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

      It "auto-detects osv-scanner"
        invoke_auto() {
          security.deps.run "$TEST_WS" 2>/dev/null || return 1
          grep -q "osv-scanner scan" "$MOCK_LOG"
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
        When call security.deps.run "$TEST_WS"
        The status should be success
        The stderr should include "skipping"
      End
    End
  End
End
