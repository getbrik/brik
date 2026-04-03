Describe "Integration: Quality and Security stages"
  Include "$BRIK_RUNTIME_LIB/logging.sh"
  Include "$BRIK_RUNTIME_LIB/tools.sh"
  Include "$BRIK_CORE_LIB/_loader.sh"
  Include "$BRIK_CORE_LIB/quality.sh"
  Include "$BRIK_CORE_LIB/quality/lint.sh"
  Include "$BRIK_CORE_LIB/quality/sast.sh"
  Include "$BRIK_CORE_LIB/quality/deps.sh"
  Include "$BRIK_CORE_LIB/quality/container.sh"
  Include "$BRIK_CORE_LIB/security.sh"

  Describe "quality.run with multiple real sub-modules"
    Describe "all checks pass"
      setup_pass() {
        TEST_WS="$(mktemp -d)"
        printf '{"name":"test"}\n' > "${TEST_WS}/package.json"
        printf 'export default [];\n' > "${TEST_WS}/eslint.config.js"
        MOCK_BIN="$(mktemp -d)"
        MOCK_NPX_LOG="${TEST_WS}/mock_npx.log"
        MOCK_NPM_LOG="${TEST_WS}/mock_npm.log"
        MOCK_SEMGREP_LOG="${TEST_WS}/mock_semgrep.log"
        # Mock npx (eslint)
        cat > "${MOCK_BIN}/npx" << MOCKEOF
#!/usr/bin/env bash
printf 'npx %s\n' "\$*" >> "$MOCK_NPX_LOG"
exit 0
MOCKEOF
        chmod +x "${MOCK_BIN}/npx"
        # Mock npm (audit)
        cat > "${MOCK_BIN}/npm" << MOCKEOF
#!/usr/bin/env bash
printf 'npm %s\n' "\$*" >> "$MOCK_NPM_LOG"
exit 0
MOCKEOF
        chmod +x "${MOCK_BIN}/npm"
        # Mock semgrep
        cat > "${MOCK_BIN}/semgrep" << MOCKEOF
#!/usr/bin/env bash
printf 'semgrep %s\n' "\$*" >> "$MOCK_SEMGREP_LOG"
exit 0
MOCKEOF
        chmod +x "${MOCK_BIN}/semgrep"
        ORIG_PATH="$PATH"
        export PATH="${MOCK_BIN}:${PATH}"
        # Mark sub-modules as loaded
        eval "_BRIK_MODULE_QUALITY_LINT_LOADED=1"
        eval "_BRIK_MODULE_QUALITY_SAST_LOADED=1"
        eval "_BRIK_MODULE_QUALITY_DEPS_LOADED=1"
        export _BRIK_MODULE_QUALITY_LINT_LOADED _BRIK_MODULE_QUALITY_SAST_LOADED _BRIK_MODULE_QUALITY_DEPS_LOADED
      }
      cleanup_pass() {
        export PATH="$ORIG_PATH"
        unset _BRIK_MODULE_QUALITY_LINT_LOADED _BRIK_MODULE_QUALITY_SAST_LOADED _BRIK_MODULE_QUALITY_DEPS_LOADED
        rm -rf "$TEST_WS" "$MOCK_BIN"
      }
      Before 'setup_pass'
      After 'cleanup_pass'

      It "runs lint, sast, and deps checks successfully"
        When call quality.run "$TEST_WS" --checks "lint,sast,deps"
        The status should be success
        The stderr should include "3/3 passed"
      End

      It "actually invokes the real sub-module functions"
        invoke_check_logs() {
          quality.run "$TEST_WS" --checks "lint,sast,deps" 2>/dev/null || return 1
          [[ -f "$MOCK_NPX_LOG" ]] && [[ -f "$MOCK_SEMGREP_LOG" ]] && [[ -f "$MOCK_NPM_LOG" ]]
        }
        When call invoke_check_logs
        The status should be success
      End
    End

    Describe "mixed pass/fail"
      setup_mixed() {
        TEST_WS="$(mktemp -d)"
        printf '{"name":"test"}\n' > "${TEST_WS}/package.json"
        printf 'export default [];\n' > "${TEST_WS}/eslint.config.js"
        MOCK_BIN="$(mktemp -d)"
        # npx (eslint) fails
        cat > "${MOCK_BIN}/npx" << 'EOF'
#!/usr/bin/env bash
exit 1
EOF
        chmod +x "${MOCK_BIN}/npx"
        # semgrep passes
        cat > "${MOCK_BIN}/semgrep" << 'EOF'
#!/usr/bin/env bash
exit 0
EOF
        chmod +x "${MOCK_BIN}/semgrep"
        ORIG_PATH="$PATH"
        export PATH="${MOCK_BIN}:${PATH}"
        eval "_BRIK_MODULE_QUALITY_LINT_LOADED=1"
        eval "_BRIK_MODULE_QUALITY_SAST_LOADED=1"
        export _BRIK_MODULE_QUALITY_LINT_LOADED _BRIK_MODULE_QUALITY_SAST_LOADED
      }
      cleanup_mixed() {
        export PATH="$ORIG_PATH"
        unset _BRIK_MODULE_QUALITY_LINT_LOADED _BRIK_MODULE_QUALITY_SAST_LOADED
        rm -rf "$TEST_WS" "$MOCK_BIN"
      }
      Before 'setup_mixed'
      After 'cleanup_mixed'

      It "returns 10 when any check fails"
        When call quality.run "$TEST_WS" --checks "lint,sast"
        The status should equal 10
        The stderr should include "1/2 passed"
      End
    End
  End

  Describe "security.run composing quality sub-modules"
    Describe "with mocked tools"
      setup_security() {
        TEST_WS="$(mktemp -d)"
        MOCK_BIN="$(mktemp -d)"
        MOCK_NPM_LOG="${TEST_WS}/mock_npm.log"
        MOCK_TRIVY_LOG="${TEST_WS}/mock_trivy.log"
        # Mock npm for deps scan
        cat > "${MOCK_BIN}/npm" << MOCKEOF
#!/usr/bin/env bash
printf 'npm %s\n' "\$*" >> "$MOCK_NPM_LOG"
exit 0
MOCKEOF
        chmod +x "${MOCK_BIN}/npm"
        printf '{"name":"test"}\n' > "${TEST_WS}/package.json"
        # Mock trivy for secret scan
        cat > "${MOCK_BIN}/trivy" << MOCKEOF
#!/usr/bin/env bash
printf 'trivy %s\n' "\$*" >> "$MOCK_TRIVY_LOG"
exit 0
MOCKEOF
        chmod +x "${MOCK_BIN}/trivy"
        ORIG_PATH="$PATH"
        export PATH="${MOCK_BIN}:${PATH}"
      }
      cleanup_security() {
        export PATH="$ORIG_PATH"
        rm -rf "$TEST_WS" "$MOCK_BIN"
      }
      Before 'setup_security'
      After 'cleanup_security'

      It "runs dependency and secret scans via quality modules"
        When call security.run "$TEST_WS"
        The status should be success
        The stderr should include "2/2 scans passed"
      End

      It "deps scan invokes npm audit"
        invoke_check_npm() {
          security.run "$TEST_WS" 2>/dev/null || return 1
          grep -q "^npm audit" "$MOCK_NPM_LOG"
        }
        When call invoke_check_npm
        The status should be success
      End

      It "secret scan invokes trivy"
        invoke_check_trivy() {
          security.run "$TEST_WS" 2>/dev/null || return 1
          grep -q "^trivy fs" "$MOCK_TRIVY_LOG"
        }
        When call invoke_check_trivy
        The status should be success
      End
    End

    Describe "with container scan enabled"
      setup_container() {
        TEST_WS="$(mktemp -d)"
        MOCK_BIN="$(mktemp -d)"
        printf '{"name":"test"}\n' > "${TEST_WS}/package.json"
        # Mock npm for deps scan
        cat > "${MOCK_BIN}/npm" << 'EOF'
#!/usr/bin/env bash
exit 0
EOF
        chmod +x "${MOCK_BIN}/npm"
        # Mock trivy for both sast and container
        cat > "${MOCK_BIN}/trivy" << 'EOF'
#!/usr/bin/env bash
exit 0
EOF
        chmod +x "${MOCK_BIN}/trivy"
        ORIG_PATH="$PATH"
        export PATH="${MOCK_BIN}:${PATH}"
      }
      cleanup_container() {
        export PATH="$ORIG_PATH"
        rm -rf "$TEST_WS" "$MOCK_BIN"
      }
      Before 'setup_container'
      After 'cleanup_container'

      It "runs all three scans including container"
        When call security.run "$TEST_WS" --container-scan true --image "myapp:1.0"
        The status should be success
        The stderr should include "3/3 scans passed"
      End
    End
  End
End
