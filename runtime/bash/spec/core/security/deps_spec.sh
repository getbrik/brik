Describe "security/deps.sh"
  Include "$BRIK_RUNTIME_LIB/logging.sh"
  Include "$BRIK_RUNTIME_LIB/tools.sh"
  Include "$BRIK_CORE_LIB/quality/_tools.sh"
  Include "$BRIK_CORE_LIB/security/deps.sh"

  Describe "security.deps.run"
    It "returns 6 for nonexistent workspace"
      When call security.deps.run "/nonexistent/workspace"
      The status should equal 6
      The stderr should include "required directory not found"
    End

    Describe "Tier 1: command override"
      setup_cmd() {
        TEST_WS="$(mktemp -d)"
        MOCK_BIN="$(mktemp -d)"
        cat > "${MOCK_BIN}/my-scanner" << 'EOF'
#!/usr/bin/env bash
exit 0
EOF
        chmod +x "${MOCK_BIN}/my-scanner"
        ORIG_PATH="$PATH"
        export PATH="${MOCK_BIN}:${PATH}"
        export BRIK_SECURITY_DEPS_COMMAND="my-scanner"
      }
      cleanup_cmd() {
        export PATH="$ORIG_PATH"
        unset BRIK_SECURITY_DEPS_COMMAND
        rm -rf "$TEST_WS" "$MOCK_BIN"
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
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock.log"
        MOCK_BIN="$(mktemp -d)"
        cat > "${MOCK_BIN}/grype" << MOCKEOF
#!/usr/bin/env bash
printf 'grype %s\n' "\$*" >> "$MOCK_LOG"
exit 0
MOCKEOF
        chmod +x "${MOCK_BIN}/grype"
        ORIG_PATH="$PATH"
        export PATH="${MOCK_BIN}:${PATH}"
        export BRIK_SECURITY_DEPS_TOOL="grype"
      }
      cleanup_tool() {
        export PATH="$ORIG_PATH"
        unset BRIK_SECURITY_DEPS_TOOL
        rm -rf "$TEST_WS" "$MOCK_BIN"
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

    Describe "Tier 2: tool not found"
      setup_missing() {
        TEST_WS="$(mktemp -d)"
        MOCK_BIN="$(mktemp -d)"
        ORIG_PATH="$PATH"
        export PATH="${MOCK_BIN}"
        export BRIK_SECURITY_DEPS_TOOL="grype"
      }
      cleanup_missing() {
        export PATH="$ORIG_PATH"
        unset BRIK_SECURITY_DEPS_TOOL
        rm -rf "$TEST_WS" "$MOCK_BIN"
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
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock.log"
        MOCK_BIN="$(mktemp -d)"
        cat > "${MOCK_BIN}/osv-scanner" << MOCKEOF
#!/usr/bin/env bash
printf 'osv-scanner %s\n' "\$*" >> "$MOCK_LOG"
exit 0
MOCKEOF
        chmod +x "${MOCK_BIN}/osv-scanner"
        ln -sf "$(command -v bash)" "${MOCK_BIN}/bash"
        ln -sf "$(command -v grep)" "${MOCK_BIN}/grep"
        ORIG_PATH="$PATH"
        export PATH="${MOCK_BIN}"
      }
      cleanup_auto() {
        export PATH="$ORIG_PATH"
        rm -rf "$TEST_WS" "$MOCK_BIN"
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
        TEST_WS="$(mktemp -d)"
        MOCK_BIN="$(mktemp -d)"
        ORIG_PATH="$PATH"
        export PATH="${MOCK_BIN}"
      }
      cleanup_none() {
        export PATH="$ORIG_PATH"
        rm -rf "$TEST_WS" "$MOCK_BIN"
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
