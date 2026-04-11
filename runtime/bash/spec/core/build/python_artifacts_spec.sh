Describe "build/python artifacts - all package managers produce dist/"
  Include "$BRIK_RUNTIME_LIB/logging.sh"
  Include "$BRIK_RUNTIME_LIB/tools.sh"
  Include "$BRIK_CORE_LIB/build/python.sh"
  Include "$BRIK_HOME/runtime/bash/spec/support/mock_helper.sh"

  Describe "pip produces artifacts in dist/"
    setup_pip_artifacts() {
      mock.setup
      TEST_WS="$(mktemp -d)"
      MOCK_LOG="${TEST_WS}/mock.log"
      printf '[project]\nname = "test"\n' > "${TEST_WS}/pyproject.toml"
      mock.create_script "python" "printf 'python %s\\n' \"\$*\" >> \"$MOCK_LOG\"
mkdir -p dist
touch dist/test-0.1.0.tar.gz dist/test-0.1.0-py3-none-any.whl
exit 0"
      mock.create_logging "pip" "$MOCK_LOG"
      mock.activate
    }
    cleanup_pip_artifacts() {
      mock.cleanup
      rm -rf "$TEST_WS"
    }
    Before 'setup_pip_artifacts'
    After 'cleanup_pip_artifacts'

    It "calls python -m build (PEP 517)"
      invoke_check() {
        build.python.run "$TEST_WS" 2>/dev/null || return 1
        grep -q "python -m build" "$MOCK_LOG"
      }
      When call invoke_check
      The status should be success
    End
  End

  Describe "pip fallback produces artifacts via pip wheel"
    setup_pip_wheel() {
      mock.setup
      TEST_WS="$(mktemp -d)"
      MOCK_LOG="${TEST_WS}/mock.log"
      printf '[project]\nname = "test"\n' > "${TEST_WS}/pyproject.toml"
      mock.create_exit "python" 1
      mock.create_script "pip" "printf 'pip %s\\n' \"\$*\" >> \"$MOCK_LOG\"
if echo \"\$*\" | grep -q \"wheel\"; then
  mkdir -p dist
  touch dist/test-0.1.0-py3-none-any.whl
fi
exit 0"
      mock.activate
    }
    cleanup_pip_wheel() {
      mock.cleanup
      rm -rf "$TEST_WS"
    }
    Before 'setup_pip_wheel'
    After 'cleanup_pip_wheel'

    It "falls back to pip wheel . -w dist/"
      invoke_check() {
        build.python.run "$TEST_WS" 2>/dev/null || return 1
        grep -q "pip wheel \. -w dist/" "$MOCK_LOG"
      }
      When call invoke_check
      The status should be success
    End
  End

  Describe "poetry produces artifacts in dist/"
    setup_poetry_artifacts() {
      mock.setup
      TEST_WS="$(mktemp -d)"
      MOCK_LOG="${TEST_WS}/mock.log"
      printf '[tool.poetry]\nname = "test"\n\n[project]\nname = "test"\n' > "${TEST_WS}/pyproject.toml"
      touch "${TEST_WS}/poetry.lock"
      mock.create_logging "poetry" "$MOCK_LOG"
      mock.activate
    }
    cleanup_poetry_artifacts() {
      mock.cleanup
      rm -rf "$TEST_WS"
    }
    Before 'setup_poetry_artifacts'
    After 'cleanup_poetry_artifacts'

    It "calls poetry build (produces dist/)"
      invoke_check() {
        build.python.run "$TEST_WS" 2>/dev/null || return 1
        grep -q "^poetry build" "$MOCK_LOG"
      }
      When call invoke_check
      The status should be success
    End
  End

  Describe "uv produces artifacts in dist/"
    setup_uv_artifacts() {
      mock.setup
      TEST_WS="$(mktemp -d)"
      MOCK_LOG="${TEST_WS}/mock.log"
      printf '[project]\nname = "test"\n' > "${TEST_WS}/pyproject.toml"
      touch "${TEST_WS}/uv.lock"
      mock.create_logging "uv" "$MOCK_LOG"
      mock.activate
    }
    cleanup_uv_artifacts() {
      mock.cleanup
      rm -rf "$TEST_WS"
    }
    Before 'setup_uv_artifacts'
    After 'cleanup_uv_artifacts'

    It "calls uv build (produces dist/)"
      invoke_check() {
        build.python.run "$TEST_WS" 2>/dev/null || return 1
        grep -q "^uv build" "$MOCK_LOG"
      }
      When call invoke_check
      The status should be success
    End
  End

  Describe "pipenv produces artifacts in dist/"
    setup_pipenv_artifacts() {
      mock.setup
      TEST_WS="$(mktemp -d)"
      MOCK_LOG="${TEST_WS}/mock.log"
      printf '[packages]\n' > "${TEST_WS}/Pipfile"
      mock.create_logging "pipenv" "$MOCK_LOG"
      mock.activate
    }
    cleanup_pipenv_artifacts() {
      mock.cleanup
      rm -rf "$TEST_WS"
    }
    Before 'setup_pipenv_artifacts'
    After 'cleanup_pipenv_artifacts'

    It "calls pipenv run python -m build after install"
      invoke_check() {
        build.python.run "$TEST_WS" 2>/dev/null || return 1
        grep -q "^pipenv install" "$MOCK_LOG" && grep -q "^pipenv run python -m build" "$MOCK_LOG"
      }
      When call invoke_check
      The status should be success
    End
  End
End
