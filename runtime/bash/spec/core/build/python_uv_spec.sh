Describe "build/python.sh - uv support"
  Include "$BRIK_RUNTIME_LIB/logging.sh"
  Include "$BRIK_RUNTIME_LIB/tools.sh"
  Include "$BRIK_CORE_LIB/build/python.sh"
  Include "$BRIK_HOME/runtime/bash/spec/support/mock_helper.sh"

  Describe "_build.python._detect_pm"
    Describe "detects uv from uv.lock"
      setup_uv() {
        TEST_WS="$(mktemp -d)"
        printf '[project]\nname = "test"\n' > "${TEST_WS}/pyproject.toml"
        touch "${TEST_WS}/uv.lock"
      }
      cleanup_uv() { rm -rf "$TEST_WS"; }
      Before 'setup_uv'
      After 'cleanup_uv'

      It "detects uv from uv.lock"
        When call _build.python._detect_pm "$TEST_WS"
        The output should equal "uv"
      End
    End

    Describe "uv.lock takes priority over poetry.lock"
      setup_uv_over_poetry() {
        TEST_WS="$(mktemp -d)"
        printf '[project]\nname = "test"\n' > "${TEST_WS}/pyproject.toml"
        touch "${TEST_WS}/uv.lock"
        touch "${TEST_WS}/poetry.lock"
      }
      cleanup_uv_over_poetry() { rm -rf "$TEST_WS"; }
      Before 'setup_uv_over_poetry'
      After 'cleanup_uv_over_poetry'

      It "prioritizes uv over poetry"
        When call _build.python._detect_pm "$TEST_WS"
        The output should equal "uv"
      End
    End
  End

  Describe "build.python.run with mock uv"
    setup_uv_build() {
      mock.setup
      TEST_WS="$(mktemp -d)"
      MOCK_LOG="${TEST_WS}/mock_uv.log"
      printf '[project]\nname = "test"\n' > "${TEST_WS}/pyproject.toml"
      touch "${TEST_WS}/uv.lock"
      mock.create_logging "uv" "$MOCK_LOG"
      mock.activate
    }
    cleanup_uv_build() {
      mock.cleanup
      rm -rf "$TEST_WS"
    }
    Before 'setup_uv_build'
    After 'cleanup_uv_build'

    It "succeeds with uv"
      When call build.python.run "$TEST_WS"
      The status should be success
      The stderr should include "build completed successfully"
    End

    It "runs uv sync then uv build"
      invoke_uv_check() {
        build.python.run "$TEST_WS" 2>/dev/null || return 1
        grep -q "^uv sync" "$MOCK_LOG" && grep -q "^uv build" "$MOCK_LOG"
      }
      When call invoke_uv_check
      The status should be success
    End
  End

  Describe "build.python.run with --tool uv override"
    setup_uv_override() {
      mock.setup
      TEST_WS="$(mktemp -d)"
      MOCK_LOG="${TEST_WS}/mock_uv.log"
      printf '[project]\nname = "test"\n' > "${TEST_WS}/pyproject.toml"
      mock.create_logging "uv" "$MOCK_LOG"
      mock.activate
    }
    cleanup_uv_override() {
      mock.cleanup
      rm -rf "$TEST_WS"
    }
    Before 'setup_uv_override'
    After 'cleanup_uv_override'

    It "forces uv on a pip project when --tool uv specified"
      invoke_uv_override() {
        build.python.run "$TEST_WS" --tool uv 2>/dev/null || return 1
        grep -q "^uv " "$MOCK_LOG"
      }
      When call invoke_uv_override
      The status should be success
    End
  End

  Describe "build.python.run with failing uv"
    setup_uv_fail() {
      mock.setup
      TEST_WS="$(mktemp -d)"
      printf '[project]\nname = "test"\n' > "${TEST_WS}/pyproject.toml"
      touch "${TEST_WS}/uv.lock"
      mock.create_exit "uv" 1
      mock.activate
    }
    cleanup_uv_fail() {
      mock.cleanup
      rm -rf "$TEST_WS"
    }
    Before 'setup_uv_fail'
    After 'cleanup_uv_fail'

    It "returns 5 when uv fails"
      When call build.python.run "$TEST_WS"
      The status should equal 5
      The stderr should include "build failed"
    End
  End
End
