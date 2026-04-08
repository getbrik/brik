Describe "security/secret_scan.sh"
  Include "$BRIK_RUNTIME_LIB/logging.sh"
  Include "$BRIK_RUNTIME_LIB/tools.sh"
  Include "$BRIK_CORE_LIB/quality/_tools.sh"
  Include "$BRIK_CORE_LIB/security/secret_scan.sh"

  Describe "security.secret_scan.run"
    It "returns 6 for nonexistent workspace"
      When call security.secret_scan.run "/nonexistent/workspace"
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
        export BRIK_SECURITY_SECRET_SCAN_COMMAND="my-scanner"
      }
      cleanup_cmd() {
        export PATH="$ORIG_PATH"
        unset BRIK_SECURITY_SECRET_SCAN_COMMAND
        rm -rf "$TEST_WS" "$MOCK_BIN"
      }
      Before 'setup_cmd'
      After 'cleanup_cmd'

      It "runs command override"
        When call security.secret_scan.run "$TEST_WS"
        The status should be success
        The stderr should include "security secret scan passed"
      End
    End

    Describe "Tier 1: command override fails"
      setup_cmd_fail() {
        TEST_WS="$(mktemp -d)"
        MOCK_BIN="$(mktemp -d)"
        cat > "${MOCK_BIN}/fail-scanner" << 'EOF'
#!/usr/bin/env bash
exit 1
EOF
        chmod +x "${MOCK_BIN}/fail-scanner"
        ORIG_PATH="$PATH"
        export PATH="${MOCK_BIN}:${PATH}"
        export BRIK_SECURITY_SECRET_SCAN_COMMAND="fail-scanner"
      }
      cleanup_cmd_fail() {
        export PATH="$ORIG_PATH"
        unset BRIK_SECURITY_SECRET_SCAN_COMMAND
        rm -rf "$TEST_WS" "$MOCK_BIN"
      }
      Before 'setup_cmd_fail'
      After 'cleanup_cmd_fail'

      It "returns 10 when command override finds secrets"
        When call security.secret_scan.run "$TEST_WS"
        The status should equal 10
        The stderr should include "secrets detected"
      End
    End

    Describe "Tier 2: gitleaks"
      setup_gitleaks() {
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
      cleanup_gitleaks() {
        export PATH="$ORIG_PATH"
        unset BRIK_SECURITY_SECRET_SCAN_TOOL
        rm -rf "$TEST_WS" "$MOCK_BIN"
      }
      Before 'setup_gitleaks'
      After 'cleanup_gitleaks'

      It "runs gitleaks detect"
        invoke_gitleaks() {
          security.secret_scan.run "$TEST_WS" 2>/dev/null || return 1
          grep -q "gitleaks detect" "$MOCK_LOG"
        }
        When call invoke_gitleaks
        The status should be success
      End
    End

    Describe "Tier 2: trufflehog"
      setup_trufflehog() {
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock.log"
        MOCK_BIN="$(mktemp -d)"
        cat > "${MOCK_BIN}/trufflehog" << MOCKEOF
#!/usr/bin/env bash
printf 'trufflehog %s\n' "\$*" >> "$MOCK_LOG"
exit 0
MOCKEOF
        chmod +x "${MOCK_BIN}/trufflehog"
        ORIG_PATH="$PATH"
        export PATH="${MOCK_BIN}:${PATH}"
        export BRIK_SECURITY_SECRET_SCAN_TOOL="trufflehog"
      }
      cleanup_trufflehog() {
        export PATH="$ORIG_PATH"
        unset BRIK_SECURITY_SECRET_SCAN_TOOL
        rm -rf "$TEST_WS" "$MOCK_BIN"
      }
      Before 'setup_trufflehog'
      After 'cleanup_trufflehog'

      It "runs trufflehog filesystem"
        invoke_trufflehog() {
          security.secret_scan.run "$TEST_WS" 2>/dev/null || return 1
          grep -q "trufflehog filesystem" "$MOCK_LOG"
        }
        When call invoke_trufflehog
        The status should be success
      End
    End

    Describe "Tier 2: gitleaks not found"
      setup_gitleaks_missing() {
        TEST_WS="$(mktemp -d)"
        MOCK_BIN="$(mktemp -d)"
        ORIG_PATH="$PATH"
        export PATH="${MOCK_BIN}"
        export BRIK_SECURITY_SECRET_SCAN_TOOL="gitleaks"
      }
      cleanup_gitleaks_missing() {
        export PATH="$ORIG_PATH"
        unset BRIK_SECURITY_SECRET_SCAN_TOOL
        rm -rf "$TEST_WS" "$MOCK_BIN"
      }
      Before 'setup_gitleaks_missing'
      After 'cleanup_gitleaks_missing'

      It "returns 3 when gitleaks binary not found"
        When call security.secret_scan.run "$TEST_WS"
        The status should equal 3
        The stderr should include "gitleaks not found"
      End
    End

    Describe "Tier 2: trufflehog not found"
      setup_trufflehog_missing() {
        TEST_WS="$(mktemp -d)"
        MOCK_BIN="$(mktemp -d)"
        ORIG_PATH="$PATH"
        export PATH="${MOCK_BIN}"
        export BRIK_SECURITY_SECRET_SCAN_TOOL="trufflehog"
      }
      cleanup_trufflehog_missing() {
        export PATH="$ORIG_PATH"
        unset BRIK_SECURITY_SECRET_SCAN_TOOL
        rm -rf "$TEST_WS" "$MOCK_BIN"
      }
      Before 'setup_trufflehog_missing'
      After 'cleanup_trufflehog_missing'

      It "returns 3 when trufflehog binary not found"
        When call security.secret_scan.run "$TEST_WS"
        The status should equal 3
        The stderr should include "trufflehog not found"
      End
    End

    Describe "Tier 2: unknown tool"
      setup_unknown() {
        TEST_WS="$(mktemp -d)"
        export BRIK_SECURITY_SECRET_SCAN_TOOL="nosuch-tool"
      }
      cleanup_unknown() {
        unset BRIK_SECURITY_SECRET_SCAN_TOOL
        rm -rf "$TEST_WS"
      }
      Before 'setup_unknown'
      After 'cleanup_unknown'

      It "returns 7 for unknown tool name"
        When call security.secret_scan.run "$TEST_WS"
        The status should equal 7
        The stderr should include "unknown secret scan tool"
      End
    End

    Describe "Tier 3: auto-detect trufflehog fallback"
      setup_trufflehog_auto() {
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock.log"
        MOCK_BIN="$(mktemp -d)"
        cat > "${MOCK_BIN}/trufflehog" << MOCKEOF
#!/usr/bin/env bash
printf 'trufflehog %s\n' "\$*" >> "$MOCK_LOG"
exit 0
MOCKEOF
        chmod +x "${MOCK_BIN}/trufflehog"
        # Build a PATH that has trufflehog but NOT gitleaks
        # Keep /usr/bin etc. for system utilities (printf, cd, eval)
        ORIG_PATH="$PATH"
        # Remove any directory that contains a real gitleaks, then prepend mock
        local cleaned_path=""
        local IFS=':'
        for dir in $PATH; do
          [[ -x "${dir}/gitleaks" ]] && continue
          cleaned_path="${cleaned_path:+${cleaned_path}:}${dir}"
        done
        export PATH="${MOCK_BIN}:${cleaned_path}"
      }
      cleanup_trufflehog_auto() {
        export PATH="$ORIG_PATH"
        rm -rf "$TEST_WS" "$MOCK_BIN"
      }
      Before 'setup_trufflehog_auto'
      After 'cleanup_trufflehog_auto'

      It "falls back to trufflehog when gitleaks absent"
        invoke_trufflehog_auto() {
          security.secret_scan.run "$TEST_WS" 2>/dev/null || return 1
          grep -q "trufflehog filesystem" "$MOCK_LOG"
        }
        When call invoke_trufflehog_auto
        The status should be success
      End
    End

    Describe "scan detects secrets"
      setup_fail_scan() {
        TEST_WS="$(mktemp -d)"
        MOCK_BIN="$(mktemp -d)"
        cat > "${MOCK_BIN}/gitleaks" << 'EOF'
#!/usr/bin/env bash
exit 1
EOF
        chmod +x "${MOCK_BIN}/gitleaks"
        ORIG_PATH="$PATH"
        export PATH="${MOCK_BIN}:${PATH}"
      }
      cleanup_fail_scan() {
        export PATH="$ORIG_PATH"
        rm -rf "$TEST_WS" "$MOCK_BIN"
      }
      Before 'setup_fail_scan'
      After 'cleanup_fail_scan'

      It "returns 10 when scanner finds secrets"
        When call security.secret_scan.run "$TEST_WS"
        The status should equal 10
        The stderr should include "secrets detected"
      End
    End

    Describe "Tier 3: auto-detect"
      setup_auto() {
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
      }
      cleanup_auto() {
        export PATH="$ORIG_PATH"
        rm -rf "$TEST_WS" "$MOCK_BIN"
      }
      Before 'setup_auto'
      After 'cleanup_auto'

      It "auto-detects gitleaks"
        invoke_auto() {
          security.secret_scan.run "$TEST_WS" 2>/dev/null || return 1
          grep -q "gitleaks detect" "$MOCK_LOG"
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
        When call security.secret_scan.run "$TEST_WS"
        The status should be success
        The stderr should include "install gitleaks or trufflehog"
      End
    End
  End
End
