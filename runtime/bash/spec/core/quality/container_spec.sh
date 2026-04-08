Describe "quality/container.sh"
  Include "$BRIK_RUNTIME_LIB/logging.sh"
  Include "$BRIK_RUNTIME_LIB/tools.sh"
  Include "$BRIK_CORE_LIB/quality/_tools.sh"
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

    Describe "with mock grype"
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
        ORIG_PATH="$PATH"
        export PATH="${MOCK_BIN}:${PATH}"
      }
      cleanup_grype() {
        export PATH="$ORIG_PATH"
        unset BRIK_PROJECT_NAME BRIK_VERSION 2>/dev/null
        rm -rf "$TEST_WS" "$MOCK_BIN"
      }
      Before 'setup_grype'
      After 'cleanup_grype'

      It "scans with grype command"
        invoke_grype() {
          quality.container.run "$TEST_WS" --image "myapp:1.0" 2>/dev/null || return 1
          grep -q "^grype" "$MOCK_LOG"
        }
        When call invoke_grype
        The status should be success
      End

      It "passes image name to grype"
        invoke_image() {
          quality.container.run "$TEST_WS" --image "myapp:1.0" 2>/dev/null || return 1
          grep -q "myapp:1.0" "$MOCK_LOG"
        }
        When call invoke_image
        The status should be success
      End

      It "passes fail-on severity to grype"
        invoke_severity() {
          quality.container.run "$TEST_WS" --image "myapp:1.0" --severity critical 2>/dev/null || return 1
          grep -q "\-\-fail-on critical" "$MOCK_LOG"
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

    Describe "dockle fallback (no grype)"
      setup_dockle() {
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_dockle.log"
        MOCK_BIN="$(mktemp -d)"
        cat > "${MOCK_BIN}/dockle" << MOCKEOF
#!/usr/bin/env bash
printf 'dockle %s\n' "\$*" >> "$MOCK_LOG"
exit 0
MOCKEOF
        chmod +x "${MOCK_BIN}/dockle"
        ln -sf "$(command -v bash)" "${MOCK_BIN}/bash"
        ln -sf "$(command -v grep)" "${MOCK_BIN}/grep"
        ORIG_PATH="$PATH"
        export PATH="${MOCK_BIN}"
      }
      cleanup_dockle() {
        export PATH="$ORIG_PATH"
        rm -rf "$TEST_WS" "$MOCK_BIN"
      }
      Before 'setup_dockle'
      After 'cleanup_dockle'

      It "falls back to dockle when grype not available"
        invoke_dockle() {
          quality.container.run "$TEST_WS" --image "myapp:1.0" 2>/dev/null || return 1
          grep -q "^dockle myapp:1.0" "$MOCK_LOG"
        }
        When call invoke_dockle
        The status should be success
      End
    End

    Describe "with failing scanner"
      setup_fail() {
        TEST_WS="$(mktemp -d)"
        MOCK_BIN="$(mktemp -d)"
        cat > "${MOCK_BIN}/grype" << 'EOF'
#!/usr/bin/env bash
exit 1
EOF
        chmod +x "${MOCK_BIN}/grype"
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
