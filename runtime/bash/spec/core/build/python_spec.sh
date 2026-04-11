Describe "build/python.sh"
  Include "$BRIK_RUNTIME_LIB/logging.sh"
  Include "$BRIK_RUNTIME_LIB/tools.sh"
  Include "$BRIK_CORE_LIB/build/python.sh"
  Include "$BRIK_HOME/runtime/bash/spec/support/mock_helper.sh"

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
        mock.setup
        TEST_WS="$(mktemp -d)"
        printf '[project]\nname = "test"\n' > "${TEST_WS}/pyproject.toml"
        mock.isolate
      }
      cleanup_no_pip() {
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_no_pip'
      After 'cleanup_no_pip'

      It "returns 3 when pip is not on PATH"
        When call build.python.run "$TEST_WS"
        The status should equal 3
        The stderr should include "required tool not found"
      End
    End

    Describe "with mock pip and pyproject.toml (python -m build available)"
      setup_pip() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock.log"
        printf '[project]\nname = "test"\n' > "${TEST_WS}/pyproject.toml"
        mock.create_logging "pip" "$MOCK_LOG"
        mock.create_logging "python" "$MOCK_LOG"
        mock.activate
      }
      cleanup_pip() {
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_pip'
      After 'cleanup_pip'

      It "succeeds and reports completion"
        When call build.python.run "$TEST_WS"
        The status should be success
        The stderr should include "build completed successfully"
      End

      It "runs python -m build with pyproject.toml"
        invoke_pip_check() {
          build.python.run "$TEST_WS" 2>/dev/null || return 1
          grep -q "python -m build" "$MOCK_LOG"
        }
        When call invoke_pip_check
        The status should be success
      End
    End

    Describe "with mock pip fallback (python -m build unavailable)"
      setup_pip_fallback() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock.log"
        printf '[project]\nname = "test"\n' > "${TEST_WS}/pyproject.toml"
        mock.create_logging "pip" "$MOCK_LOG"
        mock.create_exit "python" 1
        mock.activate
      }
      cleanup_pip_fallback() {
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_pip_fallback'
      After 'cleanup_pip_fallback'

      It "falls back to pip wheel . -w dist/"
        invoke_pip_fallback() {
          build.python.run "$TEST_WS" 2>/dev/null || return 1
          grep -q "pip wheel \. -w dist/" "$MOCK_LOG"
        }
        When call invoke_pip_fallback
        The status should be success
      End
    End

    Describe "with mock pip and setup.py"
      setup_pip_setup() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock.log"
        printf 'from setuptools import setup\nsetup(name="test")\n' > "${TEST_WS}/setup.py"
        mock.create_logging "pip" "$MOCK_LOG"
        mock.create_logging "python" "$MOCK_LOG"
        mock.activate
      }
      cleanup_pip_setup() {
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_pip_setup'
      After 'cleanup_pip_setup'

      It "runs python -m build with setup.py"
        invoke_pip_setup_check() {
          build.python.run "$TEST_WS" 2>/dev/null || return 1
          grep -q "python -m build" "$MOCK_LOG"
        }
        When call invoke_pip_setup_check
        The status should be success
      End
    End

    Describe "with mock poetry"
      setup_poetry() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_poetry.log"
        printf '[tool.poetry]\nname = "test"\n\n[project]\nname = "test"\n' > "${TEST_WS}/pyproject.toml"
        touch "${TEST_WS}/poetry.lock"
        mock.create_logging "poetry" "$MOCK_LOG"
        mock.activate
      }
      cleanup_poetry() {
        mock.cleanup
        rm -rf "$TEST_WS"
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
        mock.setup
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_pipenv.log"
        printf '[packages]\n' > "${TEST_WS}/Pipfile"
        mock.create_logging "pipenv" "$MOCK_LOG"
        mock.activate
      }
      cleanup_pipenv() {
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_pipenv'
      After 'cleanup_pipenv'

      It "runs pipenv install then pipenv run python -m build"
        invoke_pipenv_check() {
          build.python.run "$TEST_WS" 2>/dev/null || return 1
          grep -q "^pipenv install" "$MOCK_LOG" && grep -q "^pipenv run python -m build" "$MOCK_LOG"
        }
        When call invoke_pipenv_check
        The status should be success
      End
    End

    Describe "with failing pip (both python -m build and pip wheel fail)"
      setup_fail() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        printf '[project]\nname = "test"\n' > "${TEST_WS}/pyproject.toml"
        mock.create_exit "pip" 1
        mock.create_exit "python" 1
        mock.activate
      }
      cleanup_fail() {
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_fail'
      After 'cleanup_fail'

      It "returns 5 when both build methods fail"
        When call build.python.run "$TEST_WS"
        The status should equal 5
        The stderr should include "build failed"
      End
    End

    Describe "with failing poetry"
      setup_poetry_fail() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        printf '[tool.poetry]\nname = "test"\n\n[project]\nname = "test"\n' > "${TEST_WS}/pyproject.toml"
        touch "${TEST_WS}/poetry.lock"
        mock.create_exit "poetry" 1
        mock.activate
      }
      cleanup_poetry_fail() {
        mock.cleanup
        rm -rf "$TEST_WS"
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
        mock.setup
        TEST_WS="$(mktemp -d)"
        printf '[packages]\n' > "${TEST_WS}/Pipfile"
        mock.create_exit "pipenv" 1
        mock.activate
      }
      cleanup_pipenv_fail() {
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_pipenv_fail'
      After 'cleanup_pipenv_fail'

      It "returns 5 when pipenv install fails"
        When call build.python.run "$TEST_WS"
        The status should equal 5
        The stderr should include "dependency install failed"
      End
    End

    Describe "pip install . for project installation"
      setup_pip_install() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock.log"
        printf '[project]\nname = "test"\n' > "${TEST_WS}/pyproject.toml"
        mock.create_logging "pip" "$MOCK_LOG"
        mock.create_logging "python" "$MOCK_LOG"
        mock.activate
      }
      cleanup_pip_install() {
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_pip_install'
      After 'cleanup_pip_install'

      It "runs pip install . before building"
        invoke_pip_install_check() {
          build.python.run "$TEST_WS" 2>/dev/null || return 1
          grep -q "pip install \." "$MOCK_LOG"
        }
        When call invoke_pip_install_check
        The status should be success
      End

      It "runs pip install . before python -m build"
        invoke_pip_install_order() {
          build.python.run "$TEST_WS" 2>/dev/null || return 1
          local install_line build_line
          install_line="$(grep -n "pip install \." "$MOCK_LOG" | head -1 | cut -d: -f1)"
          build_line="$(grep -n "python -m build" "$MOCK_LOG" | head -1 | cut -d: -f1)"
          [[ "$install_line" -lt "$build_line" ]]
        }
        When call invoke_pip_install_order
        The status should be success
      End
    End

    Describe "pip install . failure is non-fatal"
      setup_pip_install_fail() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock.log"
        printf '[project]\nname = "test"\n' > "${TEST_WS}/pyproject.toml"
        mock.create_script "pip" "printf 'pip %s\\n' \"\$*\" >> \"$MOCK_LOG\"
if echo \"\$*\" | grep -q \"install \\.\"; then
  exit 1
fi
exit 0"
        mock.create_exit "python" 1
        mock.activate
      }
      cleanup_pip_install_fail() {
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_pip_install_fail'
      After 'cleanup_pip_install_fail'

      It "succeeds even when pip install . fails"
        When call build.python.run "$TEST_WS"
        The status should be success
        The stderr should include "build completed successfully"
      End
    End

    Describe "explicit --tool override"
      setup_tool_override() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock.log"
        printf '[tool.poetry]\nname = "test"\n\n[project]\nname = "test"\n' > "${TEST_WS}/pyproject.toml"
        touch "${TEST_WS}/poetry.lock"
        mock.create_logging "pip" "$MOCK_LOG"
        mock.create_logging "python" "$MOCK_LOG"
        mock.activate
      }
      cleanup_tool_override() {
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_tool_override'
      After 'cleanup_tool_override'

      It "forces pip on a poetry project when --tool pip specified"
        invoke_override() {
          build.python.run "$TEST_WS" --tool pip 2>/dev/null || return 1
          grep -q "python -m build" "$MOCK_LOG"
        }
        When call invoke_override
        The status should be success
      End
    End
  End
End
