Describe "security.sh - tool selection via BRIK_SECURITY_*_TOOL"
  Include "$BRIK_RUNTIME_LIB/logging.sh"
  Include "$BRIK_RUNTIME_LIB/tools.sh"
  Include "$BRIK_CORE_LIB/_loader.sh"
  Include "$BRIK_CORE_LIB/security.sh"

  Describe "BRIK_SECURITY_SECRET_SCAN_TOOL selection"
    setup_secret_tool() {
      TEST_WS="$(mktemp -d)"
      MOCK_LOG="${TEST_WS}/mock.log"
      MOCK_BIN="$(mktemp -d)"
      cat > "${MOCK_BIN}/gitleaks" << MOCKEOF
#!/usr/bin/env bash
printf 'gitleaks %s\n' "\$*" >> "$MOCK_LOG"
exit 0
MOCKEOF
      chmod +x "${MOCK_BIN}/gitleaks"
      ORIG_PATH="$PATH"
      export PATH="${MOCK_BIN}:${PATH}"
      export BRIK_SECURITY_SECRET_SCAN_TOOL="gitleaks"
    }
    cleanup_secret_tool() {
      export PATH="$ORIG_PATH"
      unset BRIK_SECURITY_SECRET_SCAN_TOOL
      rm -rf "$TEST_WS" "$MOCK_BIN"
    }
    Before 'setup_secret_tool'
    After 'cleanup_secret_tool'

    It "uses gitleaks for secret scan when BRIK_SECURITY_SECRET_SCAN_TOOL=gitleaks"
      invoke_secret() {
        security.run "$TEST_WS" --dependency-scan false --container-scan false 2>/dev/null || return 1
        grep -q "gitleaks" "$MOCK_LOG"
      }
      When call invoke_secret
      The status should be success
    End
  End

  Describe "BRIK_SECURITY_DEPENDENCY_SCAN_TOOL selection"
    setup_dep_tool() {
      TEST_WS="$(mktemp -d)"
      MOCK_LOG="${TEST_WS}/mock.log"
      printf '{"name":"test"}\n' > "${TEST_WS}/package.json"
      MOCK_BIN="$(mktemp -d)"
      cat > "${MOCK_BIN}/grype" << MOCKEOF
#!/usr/bin/env bash
printf 'grype %s\n' "\$*" >> "$MOCK_LOG"
exit 0
MOCKEOF
      chmod +x "${MOCK_BIN}/grype"
      ORIG_PATH="$PATH"
      export PATH="${MOCK_BIN}:${PATH}"
      export BRIK_SECURITY_DEPENDENCY_SCAN_TOOL="grype"
    }
    cleanup_dep_tool() {
      export PATH="$ORIG_PATH"
      unset BRIK_SECURITY_DEPENDENCY_SCAN_TOOL
      rm -rf "$TEST_WS" "$MOCK_BIN"
    }
    Before 'setup_dep_tool'
    After 'cleanup_dep_tool'

    It "uses grype for dependency scan when BRIK_SECURITY_DEPENDENCY_SCAN_TOOL=grype"
      invoke_dep() {
        security.run "$TEST_WS" --secret-scan false --container-scan false 2>/dev/null || return 1
        grep -q "grype" "$MOCK_LOG"
      }
      When call invoke_dep
      The status should be success
    End
  End
End
