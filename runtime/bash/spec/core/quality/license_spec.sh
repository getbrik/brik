Describe "quality/license.sh"
  Include "$BRIK_RUNTIME_LIB/logging.sh"
  Include "$BRIK_RUNTIME_LIB/tools.sh"
  Include "$BRIK_CORE_LIB/quality/_tools.sh"
  Include "$BRIK_CORE_LIB/quality/license.sh"

  Describe "quality.license.run"
    It "returns 6 for nonexistent workspace"
      When call quality.license.run "/nonexistent/workspace"
      The status should equal 6
      The stderr should include "required directory not found"
    End

    Describe "unknown option"
      setup_ws() { TEST_WS="$(mktemp -d)"; }
      cleanup_ws() { rm -rf "$TEST_WS"; }
      Before 'setup_ws'
      After 'cleanup_ws'

      It "returns 2 for unknown option"
        When call quality.license.run "$TEST_WS" --badopt
        The status should equal 2
        The stderr should include "unknown option"
      End
    End

    Describe "with no license tool"
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
        When call quality.license.run "$TEST_WS"
        The status should be success
        The stderr should include "skipping"
      End
    End

    Describe "with mock license_finder"
      setup_lf() {
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_lf.log"
        MOCK_BIN="$(mktemp -d)"
        cat > "${MOCK_BIN}/license_finder" << MOCKEOF
#!/usr/bin/env bash
printf 'license_finder %s\n' "\$*" >> "$MOCK_LOG"
exit 0
MOCKEOF
        chmod +x "${MOCK_BIN}/license_finder"
        ORIG_PATH="$PATH"
        export PATH="${MOCK_BIN}:${PATH}"
      }
      cleanup_lf() {
        export PATH="$ORIG_PATH"
        rm -rf "$TEST_WS" "$MOCK_BIN"
      }
      Before 'setup_lf'
      After 'cleanup_lf'

      It "uses license_finder when available"
        invoke_lf() {
          quality.license.run "$TEST_WS" 2>/dev/null || return 1
          grep -q "^license_finder" "$MOCK_LOG"
        }
        When call invoke_lf
        The status should be success
      End

      It "passes --allowed to license_finder"
        invoke_allowed() {
          quality.license.run "$TEST_WS" --allowed "MIT,Apache-2.0" 2>/dev/null || return 1
          grep -q "\-\-permitted-licenses=MIT,Apache-2.0" "$MOCK_LOG"
        }
        When call invoke_allowed
        The status should be success
      End

      It "passes --denied to license_finder"
        invoke_denied() {
          quality.license.run "$TEST_WS" --denied "GPL-3.0" 2>/dev/null || return 1
          grep -q "\-\-restricted-licenses=GPL-3.0" "$MOCK_LOG"
        }
        When call invoke_denied
        The status should be success
      End

      It "succeeds and reports license check passed"
        When call quality.license.run "$TEST_WS"
        The status should be success
        The stderr should include "license check passed"
      End
    End

    Describe "license_finder has priority over syft"
      setup_priority() {
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_lf.log"
        MOCK_BIN="$(mktemp -d)"
        cat > "${MOCK_BIN}/license_finder" << MOCKEOF
#!/usr/bin/env bash
printf 'license_finder %s\n' "\$*" >> "$MOCK_LOG"
exit 0
MOCKEOF
        chmod +x "${MOCK_BIN}/license_finder"
        cat > "${MOCK_BIN}/syft" << MOCKEOF
#!/usr/bin/env bash
printf 'syft %s\n' "\$*" >> "$MOCK_LOG"
exit 0
MOCKEOF
        chmod +x "${MOCK_BIN}/syft"
        ORIG_PATH="$PATH"
        export PATH="${MOCK_BIN}:${PATH}"
      }
      cleanup_priority() {
        export PATH="$ORIG_PATH"
        rm -rf "$TEST_WS" "$MOCK_BIN"
      }
      Before 'setup_priority'
      After 'cleanup_priority'

      It "prefers license_finder when both available"
        invoke_priority() {
          quality.license.run "$TEST_WS" 2>/dev/null || return 1
          grep -q "^license_finder" "$MOCK_LOG" && ! grep -q "^syft" "$MOCK_LOG"
        }
        When call invoke_priority
        The status should be success
      End
    End

    Describe "with mock syft (no license_finder)"
      setup_syft() {
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_syft.log"
        MOCK_BIN="$(mktemp -d)"
        cat > "${MOCK_BIN}/syft" << MOCKEOF
#!/usr/bin/env bash
printf 'syft %s\n' "\$*" >> "$MOCK_LOG"
exit 0
MOCKEOF
        chmod +x "${MOCK_BIN}/syft"
        ln -sf "$(command -v bash)" "${MOCK_BIN}/bash"
        ln -sf "$(command -v grep)" "${MOCK_BIN}/grep"
        ORIG_PATH="$PATH"
        export PATH="${MOCK_BIN}"
      }
      cleanup_syft() {
        export PATH="$ORIG_PATH"
        rm -rf "$TEST_WS" "$MOCK_BIN"
      }
      Before 'setup_syft'
      After 'cleanup_syft'

      It "falls back to syft for license scanning"
        invoke_syft() {
          quality.license.run "$TEST_WS" 2>/dev/null || return 1
          grep -q "^syft scan" "$MOCK_LOG"
        }
        When call invoke_syft
        The status should be success
      End
    End

    Describe "with failing license_finder"
      setup_fail() {
        TEST_WS="$(mktemp -d)"
        MOCK_BIN="$(mktemp -d)"
        cat > "${MOCK_BIN}/license_finder" << 'EOF'
#!/usr/bin/env bash
exit 1
EOF
        chmod +x "${MOCK_BIN}/license_finder"
        ORIG_PATH="$PATH"
        export PATH="${MOCK_BIN}:${PATH}"
      }
      cleanup_fail() {
        export PATH="$ORIG_PATH"
        rm -rf "$TEST_WS" "$MOCK_BIN"
      }
      Before 'setup_fail'
      After 'cleanup_fail'

      It "returns 10 when license violations found"
        When call quality.license.run "$TEST_WS"
        The status should equal 10
        The stderr should include "license violations found"
      End
    End
  End
End
