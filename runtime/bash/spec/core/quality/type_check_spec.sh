Describe "quality/type_check.sh"
  Include "$BRIK_RUNTIME_LIB/logging.sh"
  Include "$BRIK_RUNTIME_LIB/tools.sh"
  Include "$BRIK_CORE_LIB/quality/type_check.sh"
  Include "$BRIK_HOME/runtime/bash/spec/support/mock_helper.sh"

  Describe "quality.type_check.run"
    It "returns 6 for nonexistent workspace"
      When call quality.type_check.run "/nonexistent/workspace"
      The status should equal 6
      The stderr should include "required directory not found"
    End

    Describe "unknown option"
      setup_ws() { TEST_WS="$(mktemp -d)"; }
      cleanup_ws() { rm -rf "$TEST_WS"; }
      Before 'setup_ws'
      After 'cleanup_ws'

      It "returns 2 for unknown option"
        When call quality.type_check.run "$TEST_WS" --badopt
        The status should equal 2
        The stderr should include "unknown option"
      End
    End

    Describe "Tier 1: command override success"
      setup_cmd() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        mock.create_exit "my-checker" 0
        mock.activate
        export BRIK_QUALITY_TYPE_CHECK_COMMAND="my-checker"
      }
      cleanup_cmd() {
        unset BRIK_QUALITY_TYPE_CHECK_COMMAND
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_cmd'
      After 'cleanup_cmd'

      It "runs command override and passes"
        When call quality.type_check.run "$TEST_WS"
        The status should be success
        The stderr should include "type check passed"
      End
    End

    Describe "Tier 1: command override failure"
      setup_cmd_fail() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        mock.create_exit "failing-checker" 1
        mock.activate
        export BRIK_QUALITY_TYPE_CHECK_COMMAND="failing-checker"
      }
      cleanup_cmd_fail() {
        unset BRIK_QUALITY_TYPE_CHECK_COMMAND
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_cmd_fail'
      After 'cleanup_cmd_fail'

      It "returns 10 when command fails"
        When call quality.type_check.run "$TEST_WS"
        The status should equal 10
        The stderr should include "type check violations found"
      End
    End

    Describe "Tier 2: tsc with npx"
      setup_tsc() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock.log"
        mock.create_logging "npx" "$MOCK_LOG"
        mock.activate
        export BRIK_QUALITY_TYPE_CHECK_TOOL="tsc"
      }
      cleanup_tsc() {
        unset BRIK_QUALITY_TYPE_CHECK_TOOL
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_tsc'
      After 'cleanup_tsc'

      It "runs npx tsc --noEmit"
        invoke_tsc() {
          quality.type_check.run "$TEST_WS" 2>/dev/null || return 1
          grep -q "tsc --noEmit" "$MOCK_LOG"
        }
        When call invoke_tsc
        The status should be success
      End
    End

    Describe "Tier 2: tsc without npx"
      setup_tsc_no_npx() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        mock.isolate
        export BRIK_QUALITY_TYPE_CHECK_TOOL="tsc"
      }
      cleanup_tsc_no_npx() {
        unset BRIK_QUALITY_TYPE_CHECK_TOOL
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_tsc_no_npx'
      After 'cleanup_tsc_no_npx'

      It "returns 3 when npx not found"
        When call quality.type_check.run "$TEST_WS"
        The status should equal 3
        The stderr should include "npx not found"
      End
    End

    Describe "Tier 2: mypy present"
      setup_mypy() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock.log"
        mock.create_logging "mypy" "$MOCK_LOG"
        mock.activate
        export BRIK_QUALITY_TYPE_CHECK_TOOL="mypy"
      }
      cleanup_mypy() {
        unset BRIK_QUALITY_TYPE_CHECK_TOOL
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_mypy'
      After 'cleanup_mypy'

      It "runs mypy ."
        invoke_mypy() {
          quality.type_check.run "$TEST_WS" 2>/dev/null || return 1
          grep -q "^mypy" "$MOCK_LOG"
        }
        When call invoke_mypy
        The status should be success
      End
    End

    Describe "Tier 2: mypy missing"
      setup_no_mypy() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        mock.isolate
        export BRIK_QUALITY_TYPE_CHECK_TOOL="mypy"
      }
      cleanup_no_mypy() {
        unset BRIK_QUALITY_TYPE_CHECK_TOOL
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_no_mypy'
      After 'cleanup_no_mypy'

      It "returns 3 when mypy not found"
        When call quality.type_check.run "$TEST_WS"
        The status should equal 3
        The stderr should include "mypy not found"
      End
    End

    Describe "Tier 2: pyright without npx"
      setup_pyright_no_npx() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        mock.isolate
        export BRIK_QUALITY_TYPE_CHECK_TOOL="pyright"
      }
      cleanup_pyright_no_npx() {
        unset BRIK_QUALITY_TYPE_CHECK_TOOL
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_pyright_no_npx'
      After 'cleanup_pyright_no_npx'

      It "returns 3 when npx not found for pyright"
        When call quality.type_check.run "$TEST_WS"
        The status should equal 3
        The stderr should include "npx not found"
      End
    End

    Describe "Tier 3: auto-detect tsconfig.json"
      setup_ts_auto() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock.log"
        printf '{"compilerOptions":{}}\n' > "${TEST_WS}/tsconfig.json"
        mock.create_logging "npx" "$MOCK_LOG"
        mock.activate
      }
      cleanup_ts_auto() {
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_ts_auto'
      After 'cleanup_ts_auto'

      It "auto-detects tsc from tsconfig.json"
        invoke_ts_auto() {
          quality.type_check.run "$TEST_WS" 2>/dev/null || return 1
          grep -q "tsc --noEmit" "$MOCK_LOG"
        }
        When call invoke_ts_auto
        The status should be success
      End
    End

    Describe "Tier 3: auto-detect mypy.ini"
      setup_mypy_auto() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock.log"
        printf '[mypy]\nstrict = True\n' > "${TEST_WS}/mypy.ini"
        mock.create_logging "mypy" "$MOCK_LOG"
        mock.activate
      }
      cleanup_mypy_auto() {
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_mypy_auto'
      After 'cleanup_mypy_auto'

      It "auto-detects mypy from mypy.ini"
        invoke_mypy_auto() {
          quality.type_check.run "$TEST_WS" 2>/dev/null || return 1
          grep -q "^mypy" "$MOCK_LOG"
        }
        When call invoke_mypy_auto
        The status should be success
      End
    End

    Describe "Tier 3: auto-detect [tool.mypy] in pyproject.toml"
      setup_mypy_pyproject() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock.log"
        printf '[project]\nname = "test"\n\n[tool.mypy]\nstrict = true\n' > "${TEST_WS}/pyproject.toml"
        mock.create_logging "mypy" "$MOCK_LOG"
        mock.activate
      }
      cleanup_mypy_pyproject() {
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_mypy_pyproject'
      After 'cleanup_mypy_pyproject'

      It "auto-detects mypy from pyproject.toml [tool.mypy]"
        invoke_mypy_pyproject() {
          quality.type_check.run "$TEST_WS" 2>/dev/null || return 1
          grep -q "^mypy" "$MOCK_LOG"
        }
        When call invoke_mypy_pyproject
        The status should be success
      End
    End

    Describe "Tier 3: no type checker detected"
      setup_empty() { TEST_WS="$(mktemp -d)"; }
      cleanup_empty() { rm -rf "$TEST_WS"; }
      Before 'setup_empty'
      After 'cleanup_empty'

      It "skips when no type checker detected"
        When call quality.type_check.run "$TEST_WS"
        The status should be success
        The stderr should include "no type checker detected"
      End
    End

    Describe "Tier 2: custom tool found on PATH"
      setup_raw() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        mock.create_exit "my-type-checker" 0
        mock.activate
        export BRIK_QUALITY_TYPE_CHECK_TOOL="my-type-checker"
      }
      cleanup_raw() {
        unset BRIK_QUALITY_TYPE_CHECK_TOOL
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_raw'
      After 'cleanup_raw'

      It "uses custom tool binary as command"
        When call quality.type_check.run "$TEST_WS"
        The status should be success
        The stderr should include "type check passed"
      End
    End

    Describe "Tier 2: unknown tool not found"
      setup_missing_tc() {
        TEST_WS="$(mktemp -d)"
        export BRIK_QUALITY_TYPE_CHECK_TOOL="nonexistent-checker"
      }
      cleanup_missing_tc() {
        unset BRIK_QUALITY_TYPE_CHECK_TOOL
        rm -rf "$TEST_WS"
      }
      Before 'setup_missing_tc'
      After 'cleanup_missing_tc'

      It "returns 7 for unknown tool not on PATH"
        When call quality.type_check.run "$TEST_WS"
        The status should equal 7
        The stderr should include "unknown type check tool"
      End
    End

    Describe "with failing type checker"
      setup_fail() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        printf '{"compilerOptions":{}}\n' > "${TEST_WS}/tsconfig.json"
        mock.create_exit "npx" 1
        mock.activate
      }
      cleanup_fail() {
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_fail'
      After 'cleanup_fail'

      It "returns 10 when type check fails"
        When call quality.type_check.run "$TEST_WS"
        The status should equal 10
        The stderr should include "type check violations found"
      End
    End
  End
End
