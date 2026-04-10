Describe "security/iac.sh"
  Include "$BRIK_RUNTIME_LIB/logging.sh"
  Include "$BRIK_RUNTIME_LIB/tools.sh"
  Include "$BRIK_CORE_LIB/_loader.sh"
  Include "$BRIK_CORE_LIB/quality/_tools.sh"
  Include "$BRIK_CORE_LIB/security/iac.sh"

  Describe "security.iac.run"
    It "returns 6 for nonexistent workspace"
      When call security.iac.run "/nonexistent/workspace"
      The status should equal 6
      The stderr should include "required directory not found"
    End

    Describe "Tier 1: command override"
      setup_cmd() {
        TEST_WS="$(mktemp -d)"
        MOCK_BIN="$(mktemp -d)"
        cat > "${MOCK_BIN}/my-iac-scanner" << 'EOF'
#!/usr/bin/env bash
exit 0
EOF
        chmod +x "${MOCK_BIN}/my-iac-scanner"
        ORIG_PATH="$PATH"
        export PATH="${MOCK_BIN}:${PATH}"
        export BRIK_SECURITY_IAC_COMMAND="my-iac-scanner"
      }
      cleanup_cmd() {
        export PATH="$ORIG_PATH"
        unset BRIK_SECURITY_IAC_COMMAND
        rm -rf "$TEST_WS" "$MOCK_BIN"
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
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock.log"
        MOCK_BIN="$(mktemp -d)"
        cat > "${MOCK_BIN}/checkov" << MOCKEOF
#!/usr/bin/env bash
printf 'checkov %s\n' "\$*" >> "$MOCK_LOG"
exit 0
MOCKEOF
        chmod +x "${MOCK_BIN}/checkov"
        ORIG_PATH="$PATH"
        export PATH="${MOCK_BIN}:${PATH}"
        export BRIK_SECURITY_IAC_TOOL="checkov"
      }
      cleanup_tool() {
        export PATH="$ORIG_PATH"
        unset BRIK_SECURITY_IAC_TOOL
        rm -rf "$TEST_WS" "$MOCK_BIN"
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
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock.log"
        MOCK_BIN="$(mktemp -d)"
        cat > "${MOCK_BIN}/tfsec" << MOCKEOF
#!/usr/bin/env bash
printf 'tfsec %s\n' "\$*" >> "$MOCK_LOG"
exit 0
MOCKEOF
        chmod +x "${MOCK_BIN}/tfsec"
        ORIG_PATH="$PATH"
        export PATH="${MOCK_BIN}:${PATH}"
        export BRIK_SECURITY_IAC_TOOL="tfsec"
      }
      cleanup_tfsec() {
        export PATH="$ORIG_PATH"
        unset BRIK_SECURITY_IAC_TOOL
        rm -rf "$TEST_WS" "$MOCK_BIN"
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
        TEST_WS="$(mktemp -d)"
        MOCK_BIN="$(mktemp -d)"
        ORIG_PATH="$PATH"
        export PATH="${MOCK_BIN}"
        export BRIK_SECURITY_IAC_TOOL="checkov"
      }
      cleanup_missing() {
        export PATH="$ORIG_PATH"
        unset BRIK_SECURITY_IAC_TOOL
        rm -rf "$TEST_WS" "$MOCK_BIN"
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
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock.log"
        MOCK_BIN="$(mktemp -d)"
        cat > "${MOCK_BIN}/checkov" << MOCKEOF
#!/usr/bin/env bash
printf 'checkov %s\n' "\$*" >> "$MOCK_LOG"
exit 0
MOCKEOF
        chmod +x "${MOCK_BIN}/checkov"
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
        When call security.iac.run "$TEST_WS"
        The status should be success
        The stderr should include "skipping"
      End
    End

    Describe "Tier 1: command override fails"
      setup_fail() {
        TEST_WS="$(mktemp -d)"
        MOCK_BIN="$(mktemp -d)"
        cat > "${MOCK_BIN}/failing-scanner" << 'EOF'
#!/usr/bin/env bash
exit 1
EOF
        chmod +x "${MOCK_BIN}/failing-scanner"
        ORIG_PATH="$PATH"
        export PATH="${MOCK_BIN}:${PATH}"
        export BRIK_SECURITY_IAC_COMMAND="failing-scanner"
      }
      cleanup_fail() {
        export PATH="$ORIG_PATH"
        unset BRIK_SECURITY_IAC_COMMAND
        rm -rf "$TEST_WS" "$MOCK_BIN"
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
