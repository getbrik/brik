Describe "build/python artifacts - all package managers produce dist/"
  Include "$BRIK_RUNTIME_LIB/logging.sh"
  Include "$BRIK_RUNTIME_LIB/tools.sh"
  Include "$BRIK_CORE_LIB/build/python.sh"

  Describe "pip produces artifacts in dist/"
    setup_pip_artifacts() {
      TEST_WS="$(mktemp -d)"
      MOCK_LOG="${TEST_WS}/mock.log"
      printf '[project]\nname = "test"\n' > "${TEST_WS}/pyproject.toml"
      MOCK_BIN="$(mktemp -d)"
      cat > "${MOCK_BIN}/python" << MOCKEOF
#!/usr/bin/env bash
printf 'python %s\n' "\$*" >> "$MOCK_LOG"
# Simulate python -m build creating dist/
mkdir -p dist
touch dist/test-0.1.0.tar.gz dist/test-0.1.0-py3-none-any.whl
exit 0
MOCKEOF
      cat > "${MOCK_BIN}/pip" << MOCKEOF
#!/usr/bin/env bash
printf 'pip %s\n' "\$*" >> "$MOCK_LOG"
exit 0
MOCKEOF
      chmod +x "${MOCK_BIN}/python" "${MOCK_BIN}/pip"
      ORIG_PATH="$PATH"
      export PATH="${MOCK_BIN}:${PATH}"
    }
    cleanup_pip_artifacts() {
      export PATH="$ORIG_PATH"
      rm -rf "$TEST_WS" "$MOCK_BIN"
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
      TEST_WS="$(mktemp -d)"
      MOCK_LOG="${TEST_WS}/mock.log"
      printf '[project]\nname = "test"\n' > "${TEST_WS}/pyproject.toml"
      MOCK_BIN="$(mktemp -d)"
      cat > "${MOCK_BIN}/python" << 'MOCKEOF'
#!/usr/bin/env bash
exit 1
MOCKEOF
      cat > "${MOCK_BIN}/pip" << MOCKEOF
#!/usr/bin/env bash
printf 'pip %s\n' "\$*" >> "$MOCK_LOG"
# Simulate pip wheel creating dist/
if echo "\$*" | grep -q "wheel"; then
  mkdir -p dist
  touch dist/test-0.1.0-py3-none-any.whl
fi
exit 0
MOCKEOF
      chmod +x "${MOCK_BIN}/python" "${MOCK_BIN}/pip"
      ORIG_PATH="$PATH"
      export PATH="${MOCK_BIN}:${PATH}"
    }
    cleanup_pip_wheel() {
      export PATH="$ORIG_PATH"
      rm -rf "$TEST_WS" "$MOCK_BIN"
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
      TEST_WS="$(mktemp -d)"
      MOCK_LOG="${TEST_WS}/mock.log"
      printf '[tool.poetry]\nname = "test"\n\n[project]\nname = "test"\n' > "${TEST_WS}/pyproject.toml"
      touch "${TEST_WS}/poetry.lock"
      MOCK_BIN="$(mktemp -d)"
      cat > "${MOCK_BIN}/poetry" << MOCKEOF
#!/usr/bin/env bash
printf 'poetry %s\n' "\$*" >> "$MOCK_LOG"
exit 0
MOCKEOF
      chmod +x "${MOCK_BIN}/poetry"
      ORIG_PATH="$PATH"
      export PATH="${MOCK_BIN}:${PATH}"
    }
    cleanup_poetry_artifacts() {
      export PATH="$ORIG_PATH"
      rm -rf "$TEST_WS" "$MOCK_BIN"
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
      TEST_WS="$(mktemp -d)"
      MOCK_LOG="${TEST_WS}/mock.log"
      printf '[project]\nname = "test"\n' > "${TEST_WS}/pyproject.toml"
      touch "${TEST_WS}/uv.lock"
      MOCK_BIN="$(mktemp -d)"
      cat > "${MOCK_BIN}/uv" << MOCKEOF
#!/usr/bin/env bash
printf 'uv %s\n' "\$*" >> "$MOCK_LOG"
exit 0
MOCKEOF
      chmod +x "${MOCK_BIN}/uv"
      ORIG_PATH="$PATH"
      export PATH="${MOCK_BIN}:${PATH}"
    }
    cleanup_uv_artifacts() {
      export PATH="$ORIG_PATH"
      rm -rf "$TEST_WS" "$MOCK_BIN"
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
      TEST_WS="$(mktemp -d)"
      MOCK_LOG="${TEST_WS}/mock.log"
      printf '[packages]\n' > "${TEST_WS}/Pipfile"
      MOCK_BIN="$(mktemp -d)"
      cat > "${MOCK_BIN}/pipenv" << MOCKEOF
#!/usr/bin/env bash
printf 'pipenv %s\n' "\$*" >> "$MOCK_LOG"
exit 0
MOCKEOF
      chmod +x "${MOCK_BIN}/pipenv"
      ORIG_PATH="$PATH"
      export PATH="${MOCK_BIN}:${PATH}"
    }
    cleanup_pipenv_artifacts() {
      export PATH="$ORIG_PATH"
      rm -rf "$TEST_WS" "$MOCK_BIN"
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
