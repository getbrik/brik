Describe "quality/secret_scan.sh"
  Include "$BRIK_RUNTIME_LIB/logging.sh"
  Include "$BRIK_RUNTIME_LIB/tools.sh"
  Include "$BRIK_CORE_LIB/quality/secret_scan.sh"

  Describe "quality.secret_scan.run"
    It "returns 6 for nonexistent workspace"
      When call quality.secret_scan.run "/nonexistent/workspace"
      The status should equal 6
      The stderr should include "required directory not found"
    End

    Describe "unknown option"
      setup_ws() { TEST_WS="$(mktemp -d)"; }
      cleanup_ws() { rm -rf "$TEST_WS"; }
      Before 'setup_ws'
      After 'cleanup_ws'

      It "returns 2 for unknown option"
        When call quality.secret_scan.run "$TEST_WS" --badopt
        The status should equal 2
        The stderr should include "unknown option"
      End
    End

    Describe "Tier 1: command override success"
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
        export BRIK_QUALITY_SECRET_SCAN_COMMAND="my-scanner"
      }
      cleanup_cmd() {
        export PATH="$ORIG_PATH"
        unset BRIK_QUALITY_SECRET_SCAN_COMMAND
        rm -rf "$TEST_WS" "$MOCK_BIN"
      }
      Before 'setup_cmd'
      After 'cleanup_cmd'

      It "runs command override and passes"
        When call quality.secret_scan.run "$TEST_WS"
        The status should be success
        The stderr should include "secret scan passed"
      End
    End

    Describe "Tier 1: command override failure"
      setup_cmd_fail() {
        TEST_WS="$(mktemp -d)"
        MOCK_BIN="$(mktemp -d)"
        cat > "${MOCK_BIN}/failing-scanner" << 'EOF'
#!/usr/bin/env bash
exit 1
EOF
        chmod +x "${MOCK_BIN}/failing-scanner"
        ORIG_PATH="$PATH"
        export PATH="${MOCK_BIN}:${PATH}"
        export BRIK_QUALITY_SECRET_SCAN_COMMAND="failing-scanner"
      }
      cleanup_cmd_fail() {
        export PATH="$ORIG_PATH"
        unset BRIK_QUALITY_SECRET_SCAN_COMMAND
        rm -rf "$TEST_WS" "$MOCK_BIN"
      }
      Before 'setup_cmd_fail'
      After 'cleanup_cmd_fail'

      It "returns 10 when command fails"
        When call quality.secret_scan.run "$TEST_WS"
        The status should equal 10
        The stderr should include "secrets detected"
      End
    End

    Describe "Tier 2: gitleaks present"
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
        export BRIK_QUALITY_SECRET_SCAN_TOOL="gitleaks"
      }
      cleanup_gitleaks() {
        export PATH="$ORIG_PATH"
        unset BRIK_QUALITY_SECRET_SCAN_TOOL
        rm -rf "$TEST_WS" "$MOCK_BIN"
      }
      Before 'setup_gitleaks'
      After 'cleanup_gitleaks'

      It "runs gitleaks detect"
        invoke_gitleaks() {
          quality.secret_scan.run "$TEST_WS" 2>/dev/null || return 1
          grep -q "gitleaks detect" "$MOCK_LOG"
        }
        When call invoke_gitleaks
        The status should be success
      End
    End

    Describe "Tier 2: gitleaks missing"
      setup_no_gitleaks() {
        TEST_WS="$(mktemp -d)"
        MOCK_BIN="$(mktemp -d)"
        ORIG_PATH="$PATH"
        export PATH="${MOCK_BIN}"
        export BRIK_QUALITY_SECRET_SCAN_TOOL="gitleaks"
      }
      cleanup_no_gitleaks() {
        export PATH="$ORIG_PATH"
        unset BRIK_QUALITY_SECRET_SCAN_TOOL
        rm -rf "$TEST_WS" "$MOCK_BIN"
      }
      Before 'setup_no_gitleaks'
      After 'cleanup_no_gitleaks'

      It "returns 3 when gitleaks not found"
        When call quality.secret_scan.run "$TEST_WS"
        The status should equal 3
        The stderr should include "gitleaks not found"
      End
    End

    Describe "Tier 2: trufflehog present"
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
        export BRIK_QUALITY_SECRET_SCAN_TOOL="trufflehog"
      }
      cleanup_trufflehog() {
        export PATH="$ORIG_PATH"
        unset BRIK_QUALITY_SECRET_SCAN_TOOL
        rm -rf "$TEST_WS" "$MOCK_BIN"
      }
      Before 'setup_trufflehog'
      After 'cleanup_trufflehog'

      It "runs trufflehog filesystem"
        invoke_trufflehog() {
          quality.secret_scan.run "$TEST_WS" 2>/dev/null || return 1
          grep -q "trufflehog filesystem" "$MOCK_LOG"
        }
        When call invoke_trufflehog
        The status should be success
      End
    End

    Describe "Tier 2: trivy present"
      setup_trivy() {
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock.log"
        MOCK_BIN="$(mktemp -d)"
        cat > "${MOCK_BIN}/trivy" << MOCKEOF
#!/usr/bin/env bash
printf 'trivy %s\n' "\$*" >> "$MOCK_LOG"
exit 0
MOCKEOF
        chmod +x "${MOCK_BIN}/trivy"
        ORIG_PATH="$PATH"
        export PATH="${MOCK_BIN}:${PATH}"
        export BRIK_QUALITY_SECRET_SCAN_TOOL="trivy"
      }
      cleanup_trivy() {
        export PATH="$ORIG_PATH"
        unset BRIK_QUALITY_SECRET_SCAN_TOOL
        rm -rf "$TEST_WS" "$MOCK_BIN"
      }
      Before 'setup_trivy'
      After 'cleanup_trivy'

      It "runs trivy fs --scanners secret"
        invoke_trivy() {
          quality.secret_scan.run "$TEST_WS" 2>/dev/null || return 1
          grep -q "trivy fs --scanners secret" "$MOCK_LOG"
        }
        When call invoke_trivy
        The status should be success
      End
    End

    Describe "Tier 3: auto-detect gitleaks"
      setup_auto_gitleaks() {
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
      cleanup_auto_gitleaks() {
        export PATH="$ORIG_PATH"
        rm -rf "$TEST_WS" "$MOCK_BIN"
      }
      Before 'setup_auto_gitleaks'
      After 'cleanup_auto_gitleaks'

      It "auto-detects gitleaks"
        invoke_auto() {
          quality.secret_scan.run "$TEST_WS" 2>/dev/null || return 1
          grep -q "gitleaks detect" "$MOCK_LOG"
        }
        When call invoke_auto
        The status should be success
      End
    End

    Describe "Tier 3: no tool available"
      setup_no_tools() {
        TEST_WS="$(mktemp -d)"
        MOCK_BIN="$(mktemp -d)"
        ORIG_PATH="$PATH"
        export PATH="${MOCK_BIN}"
      }
      cleanup_no_tools() {
        export PATH="$ORIG_PATH"
        rm -rf "$TEST_WS" "$MOCK_BIN"
      }
      Before 'setup_no_tools'
      After 'cleanup_no_tools'

      It "skips when no tool available"
        When call quality.secret_scan.run "$TEST_WS"
        The status should be success
        The stderr should include "no secret scanning tool available"
      End
    End

    Describe "with failing scanner"
      setup_fail() {
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
      cleanup_fail() {
        export PATH="$ORIG_PATH"
        rm -rf "$TEST_WS" "$MOCK_BIN"
      }
      Before 'setup_fail'
      After 'cleanup_fail'

      It "returns 10 when scanner finds secrets"
        When call quality.secret_scan.run "$TEST_WS"
        The status should equal 10
        The stderr should include "secrets detected"
      End
    End
  End
End
