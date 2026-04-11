Describe "Integration: Quality and Security stages"
  Include "$BRIK_RUNTIME_LIB/logging.sh"
  Include "$BRIK_RUNTIME_LIB/tools.sh"
  Include "$BRIK_CORE_LIB/quality/_tools.sh"
  Include "$BRIK_CORE_LIB/_loader.sh"
  Include "$BRIK_CORE_LIB/quality.sh"
  Include "$BRIK_CORE_LIB/quality/lint.sh"
  Include "$BRIK_CORE_LIB/quality/format.sh"
  Include "$BRIK_CORE_LIB/security.sh"
  Include "$BRIK_HOME/runtime/bash/spec/support/mock_helper.sh"

  Describe "quality.run with multiple real sub-modules"
    Describe "lint and format pass"
      setup_pass() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        MOCK_NPX_LOG="${TEST_WS}/mock_npx.log"
        printf '{"name":"test"}\n' > "${TEST_WS}/package.json"
        printf 'export default [];\n' > "${TEST_WS}/eslint.config.js"
        mock.create_logging "npx" "$MOCK_NPX_LOG"
        mock.activate
        eval "_BRIK_MODULE_QUALITY_LINT_LOADED=1"
        eval "_BRIK_MODULE_QUALITY_FORMAT_LOADED=1"
        export _BRIK_MODULE_QUALITY_LINT_LOADED _BRIK_MODULE_QUALITY_FORMAT_LOADED
      }
      cleanup_pass() {
        mock.cleanup
        unset _BRIK_MODULE_QUALITY_LINT_LOADED _BRIK_MODULE_QUALITY_FORMAT_LOADED
        rm -rf "$TEST_WS"
      }
      Before 'setup_pass'
      After 'cleanup_pass'

      It "runs lint and format checks successfully"
        When call quality.run "$TEST_WS" --checks "lint,format"
        The status should be success
        The stderr should include "2/2 passed"
      End

      It "actually invokes the real sub-module functions"
        invoke_check_logs() {
          quality.run "$TEST_WS" --checks "lint,format" 2>/dev/null || return 1
          [[ -f "$MOCK_NPX_LOG" ]]
        }
        When call invoke_check_logs
        The status should be success
      End
    End

    Describe "mixed pass/fail"
      setup_mixed() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        printf '{"name":"test"}\n' > "${TEST_WS}/package.json"
        printf 'export default [];\n' > "${TEST_WS}/eslint.config.js"
        mock.create_exit "npx" 1
        mock.activate
        eval "_BRIK_MODULE_QUALITY_LINT_LOADED=1"
        eval "_BRIK_MODULE_QUALITY_FORMAT_LOADED=1"
        export _BRIK_MODULE_QUALITY_LINT_LOADED _BRIK_MODULE_QUALITY_FORMAT_LOADED
      }
      cleanup_mixed() {
        mock.cleanup
        unset _BRIK_MODULE_QUALITY_LINT_LOADED _BRIK_MODULE_QUALITY_FORMAT_LOADED
        rm -rf "$TEST_WS"
      }
      Before 'setup_mixed'
      After 'cleanup_mixed'

      It "returns 10 when any check fails"
        When call quality.run "$TEST_WS" --checks "lint,format"
        The status should equal 10
        The stderr should include "quality check failed"
      End
    End
  End

  Describe "security.run composing security sub-modules"
    Describe "with mocked tools"
      setup_security() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        MOCK_NPM_LOG="${TEST_WS}/mock_npm.log"
        MOCK_GITLEAKS_LOG="${TEST_WS}/mock_gitleaks.log"
        mock.create_logging "npm" "$MOCK_NPM_LOG"
        printf '{"name":"test"}\n' > "${TEST_WS}/package.json"
        mock.create_logging "gitleaks" "$MOCK_GITLEAKS_LOG"
        mock.activate
      }
      cleanup_security() {
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_security'
      After 'cleanup_security'

      It "runs dependency and secret scans via security modules"
        When call security.run "$TEST_WS"
        The status should be success
        The stderr should include "2/2 scans passed"
      End

      It "secret scan invokes gitleaks"
        invoke_check_gitleaks() {
          security.run "$TEST_WS" 2>/dev/null || return 1
          grep -q "^gitleaks detect" "$MOCK_GITLEAKS_LOG"
        }
        When call invoke_check_gitleaks
        The status should be success
      End
    End

    Describe "with container scan enabled"
      setup_container() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        printf '{"name":"test"}\n' > "${TEST_WS}/package.json"
        mock.create_exit "npm" 0
        mock.create_exit "gitleaks" 0
        mock.create_exit "grype" 0
        mock.activate
      }
      cleanup_container() {
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_container'
      After 'cleanup_container'

      It "runs all three scans including container"
        When call security.run "$TEST_WS" --scans "deps,secret,container" --image "myapp:1.0"
        The status should be success
        The stderr should include "3/3 scans passed"
      End
    End
  End
End
