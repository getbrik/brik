Describe "security/container.sh"
  Include "$BRIK_RUNTIME_LIB/logging.sh"
  Include "$BRIK_RUNTIME_LIB/tools.sh"
  Include "$BRIK_CORE_LIB/_loader.sh"
  Include "$BRIK_CORE_LIB/quality/_tools.sh"
  Include "$BRIK_CORE_LIB/security/container.sh"

  Describe "security.container.run"
    Describe "Tier 3: auto-detect grype"
      setup_grype() {
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
      }
      cleanup_grype() {
        export PATH="$ORIG_PATH"
        rm -rf "$TEST_WS" "$MOCK_BIN"
      }
      Before 'setup_grype'
      After 'cleanup_grype'

      It "auto-detects grype and scans image"
        invoke_grype() {
          security.container.run "$TEST_WS" --image "myapp:1.0" 2>/dev/null || return 1
          grep -q "grype myapp:1.0" "$MOCK_LOG"
        }
        When call invoke_grype
        The status should be success
      End
    End

    Describe "no scanner available"
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

      It "skips when no scanner available"
        When call security.container.run "$TEST_WS"
        The status should be success
        The stderr should include "skipping"
      End
    End
  End
End
