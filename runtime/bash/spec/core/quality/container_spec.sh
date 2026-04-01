Describe "quality/container.sh"
  Include "$BRIK_RUNTIME_LIB/logging.sh"
  Include "$BRIK_RUNTIME_LIB/tools.sh"
  Include "$BRIK_CORE_LIB/quality/container.sh"

  Describe "quality.container.run"
    Describe "unknown option"
      setup_ws() { TEST_WS="$(mktemp -d)"; }
      cleanup_ws() { rm -rf "$TEST_WS"; }
      Before 'setup_ws'
      After 'cleanup_ws'

      It "returns 2 for unknown option"
        When call quality.container.run "$TEST_WS" --badopt
        The status should equal 2
        The stderr should include "unknown option"
      End
    End

    Describe "with no scanner"
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
        When call quality.container.run "$TEST_WS"
        The status should be success
        The stderr should include "skipping"
      End
    End

    Describe "with mock trivy"
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
        export PATH="${MOCK_BIN}:${PATH}"
      }
      cleanup_trivy() {
        export PATH="$ORIG_PATH"
        unset BRIK_PROJECT_NAME BRIK_VERSION 2>/dev/null
        rm -rf "$TEST_WS" "$MOCK_BIN"
      }
      Before 'setup_trivy'
      After 'cleanup_trivy'

      It "scans with trivy image command"
        invoke_trivy() {
          quality.container.run "$TEST_WS" --image "myapp:1.0" 2>/dev/null || return 1
          grep -q "^trivy image" "$MOCK_LOG"
        }
        When call invoke_trivy
        The status should be success
      End

      It "passes image name to trivy"
        invoke_image() {
          quality.container.run "$TEST_WS" --image "myapp:1.0" 2>/dev/null || return 1
          grep -q "myapp:1.0" "$MOCK_LOG"
        }
        When call invoke_image
        The status should be success
      End

      It "uses default severity HIGH"
        invoke_default_sev() {
          quality.container.run "$TEST_WS" --image "myapp:1.0" 2>/dev/null || return 1
          grep -q "\-\-severity HIGH" "$MOCK_LOG"
        }
        When call invoke_default_sev
        The status should be success
      End

      It "uppercases custom severity"
        invoke_severity() {
          quality.container.run "$TEST_WS" --image "myapp:1.0" --severity critical 2>/dev/null || return 1
          grep -q "\-\-severity CRITICAL" "$MOCK_LOG"
        }
        When call invoke_severity
        The status should be success
      End

      It "uses default image from BRIK_PROJECT_NAME and BRIK_VERSION"
        invoke_default_image() {
          export BRIK_PROJECT_NAME="webapp"
          export BRIK_VERSION="3.0"
          quality.container.run "$TEST_WS" 2>/dev/null || return 1
          grep -q "webapp:3.0" "$MOCK_LOG"
        }
        When call invoke_default_image
        The status should be success
      End

      It "succeeds and reports container scan passed"
        When call quality.container.run "$TEST_WS" --image "myapp:1.0"
        The status should be success
        The stderr should include "container scan passed"
      End
    End

    Describe "grype fallback (no trivy)"
      setup_grype() {
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_grype.log"
        MOCK_BIN="$(mktemp -d)"
        cat > "${MOCK_BIN}/grype" << MOCKEOF
#!/usr/bin/env bash
printf 'grype %s\n' "\$*" >> "$MOCK_LOG"
exit 0
MOCKEOF
        chmod +x "${MOCK_BIN}/grype"
        ln -sf "$(command -v bash)" "${MOCK_BIN}/bash"
        ln -sf "$(command -v grep)" "${MOCK_BIN}/grep"
        ORIG_PATH="$PATH"
        export PATH="${MOCK_BIN}"
      }
      cleanup_grype() {
        export PATH="$ORIG_PATH"
        rm -rf "$TEST_WS" "$MOCK_BIN"
      }
      Before 'setup_grype'
      After 'cleanup_grype'

      It "falls back to grype when trivy not available"
        invoke_grype() {
          quality.container.run "$TEST_WS" --image "myapp:1.0" 2>/dev/null || return 1
          grep -q "^grype myapp:1.0" "$MOCK_LOG"
        }
        When call invoke_grype
        The status should be success
      End
    End

    Describe "with failing scanner"
      setup_fail() {
        TEST_WS="$(mktemp -d)"
        MOCK_BIN="$(mktemp -d)"
        cat > "${MOCK_BIN}/trivy" << 'EOF'
#!/usr/bin/env bash
exit 1
EOF
        chmod +x "${MOCK_BIN}/trivy"
        ORIG_PATH="$PATH"
        export PATH="${MOCK_BIN}:${PATH}"
      }
      cleanup_fail() {
        export PATH="$ORIG_PATH"
        rm -rf "$TEST_WS" "$MOCK_BIN"
      }
      Before 'setup_fail'
      After 'cleanup_fail'

      It "returns 10 when vulnerabilities found"
        When call quality.container.run "$TEST_WS" --image "myapp:1.0"
        The status should equal 10
        The stderr should include "container vulnerabilities found"
      End
    End
  End
End
