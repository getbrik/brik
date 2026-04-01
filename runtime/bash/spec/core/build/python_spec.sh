Describe "build/python.sh"
  Include "$BRIK_RUNTIME_LIB/logging.sh"
  Include "$BRIK_RUNTIME_LIB/tools.sh"
  Include "$BRIK_CORE_LIB/build/python.sh"

  Describe "_build.python._detect_pm"
    It "detects poetry from poetry.lock"
      When call _build.python._detect_pm "$WORKSPACES/python-poetry"
      The output should equal "poetry"
    End

    It "detects pipenv from Pipfile"
      When call _build.python._detect_pm "$WORKSPACES/python-pipenv"
      The output should equal "pipenv"
    End

    It "defaults to pip"
      When call _build.python._detect_pm "$WORKSPACES/python-simple"
      The output should equal "pip"
    End

    Describe "detects poetry from [tool.poetry] without poetry.lock"
      setup_toml() {
        TEST_WS="$(mktemp -d)"
        printf '[tool.poetry]\nname = "test"\n\n[project]\nname = "test"\n' > "${TEST_WS}/pyproject.toml"
      }
      cleanup_toml() { rm -rf "$TEST_WS"; }
      Before 'setup_toml'
      After 'cleanup_toml'

      It "detects poetry from pyproject.toml tool.poetry section"
        When call _build.python._detect_pm "$TEST_WS"
        The output should equal "poetry"
      End
    End
  End

  Describe "build.python.run"
    It "returns 6 for nonexistent workspace"
      When call build.python.run "/nonexistent/workspace"
      The status should equal 6
      The stderr should include "required directory not found"
    End

    It "returns 2 for unknown option"
      When call build.python.run "$WORKSPACES/python-simple" --badopt foo
      The status should equal 2
      The stderr should include "unknown option"
    End

    It "returns 6 when no Python project file found"
      When call build.python.run "$WORKSPACES/unknown"
      The status should equal 6
      The stderr should include "no Python project file found"
    End

    It "returns 7 for unsupported tool"
      When call build.python.run "$WORKSPACES/python-simple" --tool conda
      The status should equal 7
      The stderr should include "unsupported Python package manager"
    End

    Describe "require_tool pip failure"
      setup_no_pip() {
        TEST_WS="$(mktemp -d)"
        printf '[project]\nname = "test"\n' > "${TEST_WS}/pyproject.toml"
        MOCK_BIN="$(mktemp -d)"
        ORIG_PATH="$PATH"
        export PATH="${MOCK_BIN}"
      }
      cleanup_no_pip() {
        export PATH="$ORIG_PATH"
        rm -rf "$TEST_WS" "$MOCK_BIN"
      }
      Before 'setup_no_pip'
      After 'cleanup_no_pip'

      It "returns 3 when pip is not on PATH"
        When call build.python.run "$TEST_WS"
        The status should equal 3
        The stderr should include "required tool not found"
      End
    End

    Describe "with mock pip and pyproject.toml"
      setup_pip() {
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_pip.log"
        printf '[project]\nname = "test"\n' > "${TEST_WS}/pyproject.toml"
        MOCK_BIN="$(mktemp -d)"
        cat > "${MOCK_BIN}/pip" << MOCKEOF
#!/usr/bin/env bash
printf 'pip %s\n' "\$*" >> "$MOCK_LOG"
exit 0
MOCKEOF
        chmod +x "${MOCK_BIN}/pip"
        ORIG_PATH="$PATH"
        export PATH="${MOCK_BIN}:${PATH}"
      }
      cleanup_pip() {
        export PATH="$ORIG_PATH"
        rm -rf "$TEST_WS" "$MOCK_BIN"
      }
      Before 'setup_pip'
      After 'cleanup_pip'

      It "succeeds and reports completion"
        When call build.python.run "$TEST_WS"
        The status should be success
        The stderr should include "build completed successfully"
      End

      It "runs pip install -e . with pyproject.toml"
        invoke_pip_check() {
          build.python.run "$TEST_WS" 2>/dev/null || return 1
          grep -qx "pip install -e \." "$MOCK_LOG"
        }
        When call invoke_pip_check
        The status should be success
      End
    End

    Describe "with mock pip and setup.py"
      setup_pip_setup() {
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_pip.log"
        printf 'from setuptools import setup\nsetup(name="test")\n' > "${TEST_WS}/setup.py"
        MOCK_BIN="$(mktemp -d)"
        cat > "${MOCK_BIN}/pip" << MOCKEOF
#!/usr/bin/env bash
printf 'pip %s\n' "\$*" >> "$MOCK_LOG"
exit 0
MOCKEOF
        chmod +x "${MOCK_BIN}/pip"
        ORIG_PATH="$PATH"
        export PATH="${MOCK_BIN}:${PATH}"
      }
      cleanup_pip_setup() {
        export PATH="$ORIG_PATH"
        rm -rf "$TEST_WS" "$MOCK_BIN"
      }
      Before 'setup_pip_setup'
      After 'cleanup_pip_setup'

      It "runs pip install . (not -e) with setup.py"
        invoke_pip_setup_check() {
          build.python.run "$TEST_WS" 2>/dev/null || return 1
          grep -qx "pip install \." "$MOCK_LOG"
        }
        When call invoke_pip_setup_check
        The status should be success
      End
    End

    Describe "with mock poetry"
      setup_poetry() {
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_poetry.log"
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
      cleanup_poetry() {
        export PATH="$ORIG_PATH"
        rm -rf "$TEST_WS" "$MOCK_BIN"
      }
      Before 'setup_poetry'
      After 'cleanup_poetry'

      It "succeeds with poetry"
        When call build.python.run "$TEST_WS"
        The status should be success
        The stderr should include "build completed successfully"
      End

      It "calls poetry install then poetry build (two invocations)"
        invoke_poetry_check() {
          build.python.run "$TEST_WS" 2>/dev/null || return 1
          local count
          count="$(wc -l < "$MOCK_LOG")"
          [[ "$count" -ge 2 ]] && grep -q "^poetry install" "$MOCK_LOG" && grep -q "^poetry build" "$MOCK_LOG"
        }
        When call invoke_poetry_check
        The status should be success
      End
    End

    Describe "with mock pipenv"
      setup_pipenv() {
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_pipenv.log"
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
      cleanup_pipenv() {
        export PATH="$ORIG_PATH"
        rm -rf "$TEST_WS" "$MOCK_BIN"
      }
      Before 'setup_pipenv'
      After 'cleanup_pipenv'

      It "runs pipenv install"
        invoke_pipenv_check() {
          build.python.run "$TEST_WS" 2>/dev/null || return 1
          grep -qx "pipenv install" "$MOCK_LOG"
        }
        When call invoke_pipenv_check
        The status should be success
      End
    End

    Describe "with failing pip"
      setup_fail() {
        TEST_WS="$(mktemp -d)"
        printf '[project]\nname = "test"\n' > "${TEST_WS}/pyproject.toml"
        MOCK_BIN="$(mktemp -d)"
        cat > "${MOCK_BIN}/pip" << 'EOF'
#!/usr/bin/env bash
exit 1
EOF
        chmod +x "${MOCK_BIN}/pip"
        ORIG_PATH="$PATH"
        export PATH="${MOCK_BIN}:${PATH}"
      }
      cleanup_fail() {
        export PATH="$ORIG_PATH"
        rm -rf "$TEST_WS" "$MOCK_BIN"
      }
      Before 'setup_fail'
      After 'cleanup_fail'

      It "returns 5 when pip fails"
        When call build.python.run "$TEST_WS"
        The status should equal 5
        The stderr should include "build failed"
      End
    End

    Describe "with failing poetry"
      setup_poetry_fail() {
        TEST_WS="$(mktemp -d)"
        printf '[tool.poetry]\nname = "test"\n\n[project]\nname = "test"\n' > "${TEST_WS}/pyproject.toml"
        touch "${TEST_WS}/poetry.lock"
        MOCK_BIN="$(mktemp -d)"
        cat > "${MOCK_BIN}/poetry" << 'EOF'
#!/usr/bin/env bash
exit 1
EOF
        chmod +x "${MOCK_BIN}/poetry"
        ORIG_PATH="$PATH"
        export PATH="${MOCK_BIN}:${PATH}"
      }
      cleanup_poetry_fail() {
        export PATH="$ORIG_PATH"
        rm -rf "$TEST_WS" "$MOCK_BIN"
      }
      Before 'setup_poetry_fail'
      After 'cleanup_poetry_fail'

      It "returns 5 when poetry fails"
        When call build.python.run "$TEST_WS"
        The status should equal 5
        The stderr should include "build failed"
      End
    End

    Describe "with failing pipenv"
      setup_pipenv_fail() {
        TEST_WS="$(mktemp -d)"
        printf '[packages]\n' > "${TEST_WS}/Pipfile"
        MOCK_BIN="$(mktemp -d)"
        cat > "${MOCK_BIN}/pipenv" << 'EOF'
#!/usr/bin/env bash
exit 1
EOF
        chmod +x "${MOCK_BIN}/pipenv"
        ORIG_PATH="$PATH"
        export PATH="${MOCK_BIN}:${PATH}"
      }
      cleanup_pipenv_fail() {
        export PATH="$ORIG_PATH"
        rm -rf "$TEST_WS" "$MOCK_BIN"
      }
      Before 'setup_pipenv_fail'
      After 'cleanup_pipenv_fail'

      It "returns 5 when pipenv fails"
        When call build.python.run "$TEST_WS"
        The status should equal 5
        The stderr should include "build failed"
      End
    End

    Describe "explicit --tool override"
      setup_tool_override() {
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_pip.log"
        printf '[tool.poetry]\nname = "test"\n\n[project]\nname = "test"\n' > "${TEST_WS}/pyproject.toml"
        touch "${TEST_WS}/poetry.lock"
        MOCK_BIN="$(mktemp -d)"
        cat > "${MOCK_BIN}/pip" << MOCKEOF
#!/usr/bin/env bash
printf 'pip %s\n' "\$*" >> "$MOCK_LOG"
exit 0
MOCKEOF
        chmod +x "${MOCK_BIN}/pip"
        ORIG_PATH="$PATH"
        export PATH="${MOCK_BIN}:${PATH}"
      }
      cleanup_tool_override() {
        export PATH="$ORIG_PATH"
        rm -rf "$TEST_WS" "$MOCK_BIN"
      }
      Before 'setup_tool_override'
      After 'cleanup_tool_override'

      It "forces pip on a poetry project when --tool pip specified"
        invoke_override() {
          build.python.run "$TEST_WS" --tool pip 2>/dev/null || return 1
          grep -q "^pip " "$MOCK_LOG"
        }
        When call invoke_override
        The status should be success
      End
    End
  End
End
