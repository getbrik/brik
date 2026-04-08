Describe "quality/deps.sh"
  Include "$BRIK_RUNTIME_LIB/logging.sh"
  Include "$BRIK_RUNTIME_LIB/tools.sh"
  Include "$BRIK_CORE_LIB/quality/_tools.sh"
  Include "$BRIK_CORE_LIB/quality/deps.sh"

  Describe "quality.deps.run"
    It "returns 6 for nonexistent workspace"
      When call quality.deps.run "/nonexistent/workspace"
      The status should equal 6
      The stderr should include "required directory not found"
    End

    Describe "unknown option"
      setup_ws() { TEST_WS="$(mktemp -d)"; }
      cleanup_ws() { rm -rf "$TEST_WS"; }
      Before 'setup_ws'
      After 'cleanup_ws'

      It "returns 2 for unknown option"
        When call quality.deps.run "$TEST_WS" --badopt foo
        The status should equal 2
        The stderr should include "unknown option"
      End
    End

    Describe "with Node.js workspace and mock npm"
      setup_npm() {
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_npm.log"
        printf '{"name":"test"}\n' > "${TEST_WS}/package.json"
        MOCK_BIN="$(mktemp -d)"
        cat > "${MOCK_BIN}/npm" << MOCKEOF
#!/usr/bin/env bash
printf 'npm %s\n' "\$*" >> "$MOCK_LOG"
exit 0
MOCKEOF
        chmod +x "${MOCK_BIN}/npm"
        ORIG_PATH="$PATH"
        export PATH="${MOCK_BIN}:${PATH}"
      }
      cleanup_npm() {
        export PATH="$ORIG_PATH"
        rm -rf "$TEST_WS" "$MOCK_BIN"
      }
      Before 'setup_npm'
      After 'cleanup_npm'

      It "runs npm audit"
        invoke_npm_audit() {
          quality.deps.run "$TEST_WS" 2>/dev/null || return 1
          grep -q "^npm audit" "$MOCK_LOG"
        }
        When call invoke_npm_audit
        The status should be success
      End

      It "uses default severity level (high)"
        invoke_default_severity() {
          quality.deps.run "$TEST_WS" 2>/dev/null || return 1
          grep -q "audit-level=high" "$MOCK_LOG"
        }
        When call invoke_default_severity
        The status should be success
      End

      It "uses specified severity"
        invoke_severity() {
          quality.deps.run "$TEST_WS" --severity critical 2>/dev/null || return 1
          grep -q "audit-level=critical" "$MOCK_LOG"
        }
        When call invoke_severity
        The status should be success
      End

      It "succeeds and reports scan passed"
        When call quality.deps.run "$TEST_WS"
        The status should be success
        The stderr should include "dependency scan passed"
      End
    End

    Describe "with Python workspace and mock pip-audit"
      setup_pip_audit() {
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_pip_audit.log"
        printf '[project]\nname = "test"\n' > "${TEST_WS}/pyproject.toml"
        MOCK_BIN="$(mktemp -d)"
        cat > "${MOCK_BIN}/pip-audit" << MOCKEOF
#!/usr/bin/env bash
printf 'pip-audit %s\n' "\$*" >> "$MOCK_LOG"
exit 0
MOCKEOF
        chmod +x "${MOCK_BIN}/pip-audit"
        ORIG_PATH="$PATH"
        export PATH="${MOCK_BIN}:${PATH}"
      }
      cleanup_pip_audit() {
        export PATH="$ORIG_PATH"
        rm -rf "$TEST_WS" "$MOCK_BIN"
      }
      Before 'setup_pip_audit'
      After 'cleanup_pip_audit'

      It "runs pip-audit for Python projects"
        invoke_pip_audit() {
          quality.deps.run "$TEST_WS" 2>/dev/null || return 1
          grep -q "^pip-audit" "$MOCK_LOG"
        }
        When call invoke_pip_audit
        The status should be success
      End
    End

    Describe "Python with safety fallback (no pip-audit)"
      setup_safety() {
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_safety.log"
        printf '[project]\nname = "test"\n' > "${TEST_WS}/pyproject.toml"
        MOCK_BIN="$(mktemp -d)"
        cat > "${MOCK_BIN}/safety" << MOCKEOF
#!/usr/bin/env bash
printf 'safety %s\n' "\$*" >> "$MOCK_LOG"
exit 0
MOCKEOF
        chmod +x "${MOCK_BIN}/safety"
        ln -sf "$(command -v bash)" "${MOCK_BIN}/bash"
        ln -sf "$(command -v grep)" "${MOCK_BIN}/grep"
        ORIG_PATH="$PATH"
        # Only safety, no pip-audit
        export PATH="${MOCK_BIN}"
      }
      cleanup_safety() {
        export PATH="$ORIG_PATH"
        rm -rf "$TEST_WS" "$MOCK_BIN"
      }
      Before 'setup_safety'
      After 'cleanup_safety'

      It "falls back to safety when pip-audit not available"
        invoke_safety() {
          quality.deps.run "$TEST_WS" 2>/dev/null || return 1
          grep -q "^safety check" "$MOCK_LOG"
        }
        When call invoke_safety
        The status should be success
      End
    End

    Describe "osv-scanner fallback for unknown stack"
      setup_osv() {
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_osv.log"
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
      cleanup_osv() {
        export PATH="$ORIG_PATH"
        rm -rf "$TEST_WS" "$MOCK_BIN"
      }
      Before 'setup_osv'
      After 'cleanup_osv'

      It "falls back to osv-scanner for unknown workspace"
        invoke_osv() {
          quality.deps.run "$TEST_WS" 2>/dev/null || return 1
          grep -q "^osv-scanner scan" "$MOCK_LOG"
        }
        When call invoke_osv
        The status should be success
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
        When call quality.deps.run "$TEST_WS"
        The status should be success
        The stderr should include "skipping"
      End
    End

    Describe "with failing npm audit"
      setup_fail() {
        TEST_WS="$(mktemp -d)"
        printf '{"name":"test"}\n' > "${TEST_WS}/package.json"
        MOCK_BIN="$(mktemp -d)"
        cat > "${MOCK_BIN}/npm" << 'EOF'
#!/usr/bin/env bash
exit 1
EOF
        chmod +x "${MOCK_BIN}/npm"
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
        When call quality.deps.run "$TEST_WS"
        The status should equal 10
        The stderr should include "dependency vulnerabilities found"
      End
    End
  End
End
