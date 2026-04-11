Describe "security modules - tool selection via BRIK_SECURITY_*_TOOL"
  Include "$BRIK_RUNTIME_LIB/logging.sh"
  Include "$BRIK_RUNTIME_LIB/tools.sh"
  Include "$BRIK_CORE_LIB/_loader.sh"
  Include "$BRIK_CORE_LIB/quality/_tools.sh"
  Include "$BRIK_CORE_LIB/security/secret_scan.sh"
  Include "$BRIK_CORE_LIB/security/deps.sh"
  Include "$BRIK_HOME/runtime/bash/spec/support/mock_helper.sh"

  Describe "BRIK_SECURITY_SECRETS_TOOL selection"
    setup_secret_tool() {
      mock.setup
      TEST_WS="$(mktemp -d)"
      MOCK_LOG="${TEST_WS}/mock.log"
      mock.create_logging "gitleaks" "$MOCK_LOG"
      mock.activate
      export BRIK_SECURITY_SECRETS_TOOL="gitleaks"
    }
    cleanup_secret_tool() {
      mock.cleanup
      unset BRIK_SECURITY_SECRETS_TOOL
      rm -rf "$TEST_WS"
    }
    Before 'setup_secret_tool'
    After 'cleanup_secret_tool'

    It "uses gitleaks for secret scan when BRIK_SECURITY_SECRETS_TOOL=gitleaks"
      invoke_secret() {
        security.secret_scan.run "$TEST_WS" 2>/dev/null || return 1
        grep -q "gitleaks" "$MOCK_LOG"
      }
      When call invoke_secret
      The status should be success
    End
  End

  Describe "BRIK_SECURITY_DEPS_TOOL selection"
    setup_dep_tool() {
      mock.setup
      TEST_WS="$(mktemp -d)"
      MOCK_LOG="${TEST_WS}/mock.log"
      printf '{"name":"test"}\n' > "${TEST_WS}/package.json"
      mock.create_logging "grype" "$MOCK_LOG"
      mock.activate
      export BRIK_SECURITY_DEPS_TOOL="grype"
    }
    cleanup_dep_tool() {
      mock.cleanup
      unset BRIK_SECURITY_DEPS_TOOL
      rm -rf "$TEST_WS"
    }
    Before 'setup_dep_tool'
    After 'cleanup_dep_tool'

    It "uses grype for dependency scan when BRIK_SECURITY_DEPS_TOOL=grype"
      invoke_dep() {
        security.deps.run "$TEST_WS" 2>/dev/null || return 1
        grep -q "grype" "$MOCK_LOG"
      }
      When call invoke_dep
      The status should be success
    End
  End
End
