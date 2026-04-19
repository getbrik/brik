Describe "quality.sh"
  Include "$BRIK_RUNTIME_LIB/logging.sh"
  Include "$BRIK_RUNTIME_LIB/tools.sh"
  Include "$BRIK_CORE_LIB/_loader.sh"
  Include "$BRIK_CORE_LIB/quality.sh"

  Describe "quality.run"
    It "returns 6 for nonexistent workspace"
      When call quality.run "/nonexistent/workspace"
      The status should equal 6
      The stderr should include "required directory not found"
    End

    Describe "unknown option"
      setup_ws() { TEST_WS="$(mktemp -d)"; }
      cleanup_ws() { rm -rf "$TEST_WS"; }
      Before 'setup_ws'
      After 'cleanup_ws'

      It "returns 2 for unknown option"
        When call quality.run "$TEST_WS" --badopt foo
        The status should equal 2
        The stderr should include "unknown option"
      End
    End

    Describe "with mock lint module"
      setup_mock_lint() {
        TEST_WS="$(mktemp -d)"
        MOCK_LINT_LOG="${TEST_WS}/lint_args.log"
        # Create a mock that records its workspace argument
        eval "quality.lint.run() { printf '%s\n' \"\$1\" > \"$MOCK_LINT_LOG\"; return 0; }"
        eval "_BRIK_MODULE_QUALITY_LINT_LOADED=1"
        export _BRIK_MODULE_QUALITY_LINT_LOADED
      }
      cleanup_mock_lint() {
        unset -f quality.lint.run 2>/dev/null
        unset _BRIK_MODULE_QUALITY_LINT_LOADED
        rm -rf "$TEST_WS"
      }
      Before 'setup_mock_lint'
      After 'cleanup_mock_lint'

      It "runs lint by default"
        When call quality.run "$TEST_WS"
        The status should be success
        The stderr should include "running quality check: lint"
        The stderr should include "quality check passed: lint"
      End

      It "passes workspace to sub-module"
        invoke_check_ws() {
          quality.run "$TEST_WS" 2>/dev/null || return 1
          grep -qx "$TEST_WS" "$MOCK_LINT_LOG"
        }
        When call invoke_check_ws
        The status should be success
      End
    End

    Describe "with failing check"
      setup_mock_fail() {
        TEST_WS="$(mktemp -d)"
        quality.lint.run() { return 10; }
        eval "_BRIK_MODULE_QUALITY_LINT_LOADED=1"
        export _BRIK_MODULE_QUALITY_LINT_LOADED
      }
      cleanup_mock_fail() {
        unset -f quality.lint.run 2>/dev/null
        unset _BRIK_MODULE_QUALITY_LINT_LOADED
        rm -rf "$TEST_WS"
      }
      Before 'setup_mock_fail'
      After 'cleanup_mock_fail'

      It "returns 10 when a check fails"
        When call quality.run "$TEST_WS"
        The status should equal 10
        The stderr should include "quality check failed: lint"
      End
    End

    Describe "with multiple checks"
      setup_multi() {
        TEST_WS="$(mktemp -d)"
        quality.lint.run() { return 0; }
        quality.sast.run() { return 0; }
        eval "_BRIK_MODULE_QUALITY_LINT_LOADED=1"
        eval "_BRIK_MODULE_QUALITY_SAST_LOADED=1"
        export _BRIK_MODULE_QUALITY_LINT_LOADED _BRIK_MODULE_QUALITY_SAST_LOADED
      }
      cleanup_multi() {
        unset -f quality.lint.run quality.sast.run 2>/dev/null
        unset _BRIK_MODULE_QUALITY_LINT_LOADED _BRIK_MODULE_QUALITY_SAST_LOADED
        rm -rf "$TEST_WS"
      }
      Before 'setup_multi'
      After 'cleanup_multi'

      It "runs multiple comma-separated checks"
        When call quality.run "$TEST_WS" --checks "lint,sast"
        The status should be success
        The stderr should include "2/2 passed"
      End
    End

    Describe "with whitespace in checks list"
      setup_space() {
        TEST_WS="$(mktemp -d)"
        quality.lint.run() { return 0; }
        quality.sast.run() { return 0; }
        eval "_BRIK_MODULE_QUALITY_LINT_LOADED=1"
        eval "_BRIK_MODULE_QUALITY_SAST_LOADED=1"
        export _BRIK_MODULE_QUALITY_LINT_LOADED _BRIK_MODULE_QUALITY_SAST_LOADED
      }
      cleanup_space() {
        unset -f quality.lint.run quality.sast.run 2>/dev/null
        unset _BRIK_MODULE_QUALITY_LINT_LOADED _BRIK_MODULE_QUALITY_SAST_LOADED
        rm -rf "$TEST_WS"
      }
      Before 'setup_space'
      After 'cleanup_space'

      It "trims whitespace around check names"
        When call quality.run "$TEST_WS" --checks "lint, sast"
        The status should be success
        The stderr should include "2/2 passed"
      End
    End

    Describe "module not found skips gracefully"
      setup_no_module() {
        TEST_WS="$(mktemp -d)"
      }
      cleanup_no_module() { rm -rf "$TEST_WS"; }
      Before 'setup_no_module'
      After 'cleanup_no_module'

      It "warns when module not found and continues"
        When call quality.run "$TEST_WS" --checks "nonexistent"
        The status should be success
        The stderr should include "not found"
      End
    End

    Describe "mixed pass/fail with multiple checks"
      setup_mixed() {
        TEST_WS="$(mktemp -d)"
        quality.lint.run() { return 0; }
        quality.sast.run() { return 10; }
        eval "_BRIK_MODULE_QUALITY_LINT_LOADED=1"
        eval "_BRIK_MODULE_QUALITY_SAST_LOADED=1"
        export _BRIK_MODULE_QUALITY_LINT_LOADED _BRIK_MODULE_QUALITY_SAST_LOADED
      }
      cleanup_mixed() {
        unset -f quality.lint.run quality.sast.run 2>/dev/null
        unset _BRIK_MODULE_QUALITY_LINT_LOADED _BRIK_MODULE_QUALITY_SAST_LOADED
        rm -rf "$TEST_WS"
      }
      Before 'setup_mixed'
      After 'cleanup_mixed'

      It "returns 10 and reports 1/2 passed"
        When call quality.run "$TEST_WS" --checks "lint,sast"
        The status should equal 10
        The stderr should include "1/2 passed"
        The stderr should include "1 failed"
      End
    End
  End
End
