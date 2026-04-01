Describe "quality/sast.sh"
  Include "$BRIK_RUNTIME_LIB/logging.sh"
  Include "$BRIK_RUNTIME_LIB/tools.sh"
  Include "$BRIK_CORE_LIB/quality/sast.sh"

  Describe "quality.sast.run"
    It "returns 6 for nonexistent workspace"
      When call quality.sast.run "/nonexistent/workspace"
      The status should equal 6
      The stderr should include "required directory not found"
    End

    Describe "unknown option"
      setup_ws() { TEST_WS="$(mktemp -d)"; }
      cleanup_ws() { rm -rf "$TEST_WS"; }
      Before 'setup_ws'
      After 'cleanup_ws'

      It "returns 2 for unknown option"
        When call quality.sast.run "$TEST_WS" --badopt foo
        The status should equal 2
        The stderr should include "unknown option"
      End
    End

    Describe "unsupported tool"
      setup_ws2() { TEST_WS="$(mktemp -d)"; }
      cleanup_ws2() { rm -rf "$TEST_WS"; }
      Before 'setup_ws2'
      After 'cleanup_ws2'

      It "returns 7 for unsupported tool"
        When call quality.sast.run "$TEST_WS" --tool unknown
        The status should equal 7
        The stderr should include "unsupported SAST tool"
      End
    End

    Describe "with mock semgrep"
      setup_semgrep() {
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_semgrep.log"
        MOCK_BIN="$(mktemp -d)"
        cat > "${MOCK_BIN}/semgrep" << MOCKEOF
#!/usr/bin/env bash
printf 'semgrep %s\n' "\$*" >> "$MOCK_LOG"
exit 0
MOCKEOF
        chmod +x "${MOCK_BIN}/semgrep"
        ORIG_PATH="$PATH"
        export PATH="${MOCK_BIN}:${PATH}"
      }
      cleanup_semgrep() {
        export PATH="$ORIG_PATH"
        rm -rf "$TEST_WS" "$MOCK_BIN"
      }
      Before 'setup_semgrep'
      After 'cleanup_semgrep'

      It "auto-detects and runs semgrep scan"
        invoke_semgrep() {
          quality.sast.run "$TEST_WS" 2>/dev/null || return 1
          grep -q "^semgrep scan" "$MOCK_LOG"
        }
        When call invoke_semgrep
        The status should be success
      End

      It "passes --config auto to semgrep"
        invoke_semgrep_config() {
          quality.sast.run "$TEST_WS" 2>/dev/null || return 1
          grep -q "\-\-config auto" "$MOCK_LOG"
        }
        When call invoke_semgrep_config
        The status should be success
      End

      It "succeeds and reports SAST passed"
        When call quality.sast.run "$TEST_WS"
        The status should be success
        The stderr should include "SAST passed"
      End
    End

    Describe "explicit --tool semgrep"
      setup_explicit() {
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_semgrep.log"
        MOCK_BIN="$(mktemp -d)"
        cat > "${MOCK_BIN}/semgrep" << MOCKEOF
#!/usr/bin/env bash
printf 'semgrep %s\n' "\$*" >> "$MOCK_LOG"
exit 0
MOCKEOF
        chmod +x "${MOCK_BIN}/semgrep"
        ORIG_PATH="$PATH"
        export PATH="${MOCK_BIN}:${PATH}"
      }
      cleanup_explicit() {
        export PATH="$ORIG_PATH"
        rm -rf "$TEST_WS" "$MOCK_BIN"
      }
      Before 'setup_explicit'
      After 'cleanup_explicit'

      It "uses semgrep when --tool semgrep specified"
        invoke_explicit_semgrep() {
          quality.sast.run "$TEST_WS" --tool semgrep 2>/dev/null || return 1
          grep -q "^semgrep scan" "$MOCK_LOG"
        }
        When call invoke_explicit_semgrep
        The status should be success
      End
    End

    Describe "explicit --tool trivy"
      setup_explicit_trivy() {
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_trivy.log"
        MOCK_BIN="$(mktemp -d)"
        cat > "${MOCK_BIN}/trivy" << MOCKEOF
#!/usr/bin/env bash
printf 'trivy %s\n' "\$*" >> "$MOCK_LOG"
exit 0
MOCKEOF
        chmod +x "${MOCK_BIN}/trivy"
        ORIG_PATH="$PATH"
        export PATH="${MOCK_BIN}:${PATH}"
      }
      cleanup_explicit_trivy() {
        export PATH="$ORIG_PATH"
        rm -rf "$TEST_WS" "$MOCK_BIN"
      }
      Before 'setup_explicit_trivy'
      After 'cleanup_explicit_trivy'

      It "uses trivy fs when --tool trivy specified"
        invoke_explicit_trivy() {
          quality.sast.run "$TEST_WS" --tool trivy 2>/dev/null || return 1
          grep -q "^trivy fs" "$MOCK_LOG"
        }
        When call invoke_explicit_trivy
        The status should be success
      End
    End

    Describe "with mock trivy fallback (no semgrep)"
      setup_trivy() {
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_trivy.log"
        MOCK_BIN="$(mktemp -d)"
        cat > "${MOCK_BIN}/trivy" << MOCKEOF
#!/usr/bin/env bash
printf 'trivy %s\n' "\$*" >> "$MOCK_LOG"
exit 0
MOCKEOF
        chmod +x "${MOCK_BIN}/trivy"
        ORIG_PATH="$PATH"
        # Only trivy in PATH, no semgrep
        export PATH="${MOCK_BIN}:/usr/bin:/bin"
      }
      cleanup_trivy() {
        export PATH="$ORIG_PATH"
        rm -rf "$TEST_WS" "$MOCK_BIN"
      }
      Before 'setup_trivy'
      After 'cleanup_trivy'

      It "falls back to trivy when semgrep not available"
        invoke_trivy_fallback() {
          quality.sast.run "$TEST_WS" 2>/dev/null || return 1
          grep -q "^trivy fs" "$MOCK_LOG"
        }
        When call invoke_trivy_fallback
        The status should be success
      End
    End

    Describe "with no SAST tool"
      setup_none() {
        TEST_WS="$(mktemp -d)"
        MOCK_BIN="$(mktemp -d)"
        ORIG_PATH="$PATH"
        export PATH="${MOCK_BIN}:/usr/bin:/bin"
      }
      cleanup_none() {
        export PATH="$ORIG_PATH"
        rm -rf "$TEST_WS" "$MOCK_BIN"
      }
      Before 'setup_none'
      After 'cleanup_none'

      It "skips gracefully when no tool available"
        When call quality.sast.run "$TEST_WS"
        The status should be success
        The stderr should include "skipping"
      End
    End

    Describe "custom SAST"
      setup_custom() {
        TEST_WS="$(mktemp -d)"
      }
      cleanup_custom() { rm -rf "$TEST_WS"; }
      Before 'setup_custom'
      After 'cleanup_custom'

      It "returns 2 when custom tool has no command"
        When call quality.sast.run "$TEST_WS" --tool custom
        The status should equal 2
        The stderr should include "requires --command"
      End
    End

    Describe "custom SAST with command"
      setup_custom_cmd() {
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_custom.log"
        MOCK_BIN="$(mktemp -d)"
        cat > "${MOCK_BIN}/my-scanner" << MOCKEOF
#!/usr/bin/env bash
printf 'my-scanner %s\n' "\$*" >> "$MOCK_LOG"
exit 0
MOCKEOF
        chmod +x "${MOCK_BIN}/my-scanner"
        ORIG_PATH="$PATH"
        export PATH="${MOCK_BIN}:${PATH}"
      }
      cleanup_custom_cmd() {
        export PATH="$ORIG_PATH"
        rm -rf "$TEST_WS" "$MOCK_BIN"
      }
      Before 'setup_custom_cmd'
      After 'cleanup_custom_cmd'

      It "runs custom command when --tool custom --command provided"
        invoke_custom() {
          quality.sast.run "$TEST_WS" --tool custom --command "my-scanner scan" 2>/dev/null || return 1
          grep -q "^my-scanner" "$MOCK_LOG"
        }
        When call invoke_custom
        The status should be success
      End
    End

    Describe "with failing semgrep"
      setup_fail() {
        TEST_WS="$(mktemp -d)"
        MOCK_BIN="$(mktemp -d)"
        cat > "${MOCK_BIN}/semgrep" << 'EOF'
#!/usr/bin/env bash
exit 1
EOF
        chmod +x "${MOCK_BIN}/semgrep"
        ORIG_PATH="$PATH"
        export PATH="${MOCK_BIN}:${PATH}"
      }
      cleanup_fail() {
        export PATH="$ORIG_PATH"
        rm -rf "$TEST_WS" "$MOCK_BIN"
      }
      Before 'setup_fail'
      After 'cleanup_fail'

      It "returns 10 when SAST finds issues"
        When call quality.sast.run "$TEST_WS"
        The status should equal 10
        The stderr should include "SAST findings detected"
      End
    End
  End
End
