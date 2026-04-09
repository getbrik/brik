Describe "config/python.sh"
  Include "$BRIK_RUNTIME_LIB/logging.sh"
  Include "$BRIK_CORE_LIB/config.sh"
  Include "$BRIK_CORE_LIB/config/python.sh"

  Describe "config.python.default"
    It "returns empty string for build_command (delegates to tool detection)"
      When call config.python.default "build_command"
      The output should equal ""
      The status should be success
    End

    It "returns 'pytest' for test_framework"
      When call config.python.default "test_framework"
      The output should equal "pytest"
    End

    It "returns 'ruff' for lint_tool"
      When call config.python.default "lint_tool"
      The output should equal "ruff"
    End

    It "returns 'ruff-format' for format_tool"
      When call config.python.default "format_tool"
      The output should equal "ruff-format"
    End

    It "returns 1 for unknown setting"
      When call config.python.default "unknown_setting"
      The status should equal 1
    End
  End

  Describe "config.python.export_build_vars"
    Describe "when python_version is configured"
      setup_config() {
        TEMP_CONFIG="$(mktemp)"
        cat > "$TEMP_CONFIG" <<'YAML'
version: 1
project:
  name: test
  stack: python
build:
  python_version: "3.12"
YAML
        export BRIK_CONFIG_FILE="$TEMP_CONFIG"
      }
      cleanup_config() {
        rm -f "$TEMP_CONFIG"
        unset BRIK_BUILD_PYTHON_VERSION BRIK_CONFIG_FILE
      }
      Before 'setup_config'
      After 'cleanup_config'

      It "exports BRIK_BUILD_PYTHON_VERSION"
        export_and_check() {
          config.python.export_build_vars
          printf '%s' "${BRIK_BUILD_PYTHON_VERSION:-}"
        }
        When call export_and_check
        The output should equal "3.12"
      End
    End

    Describe "when python_version is not configured"
      setup_config() {
        TEMP_CONFIG="$(mktemp)"
        printf 'version: 1\nproject:\n  name: test\n  stack: python\n' > "$TEMP_CONFIG"
        export BRIK_CONFIG_FILE="$TEMP_CONFIG"
      }
      cleanup_config() {
        rm -f "$TEMP_CONFIG"
        unset BRIK_CONFIG_FILE
      }
      Before 'setup_config'
      After 'cleanup_config'

      It "does not export BRIK_BUILD_PYTHON_VERSION"
        export_and_check() {
          unset BRIK_BUILD_PYTHON_VERSION 2>/dev/null || true
          config.python.export_build_vars
          printf '%s' "${BRIK_BUILD_PYTHON_VERSION:-UNSET}"
        }
        When call export_and_check
        The output should equal "UNSET"
      End
    End
  End

  Describe "config.python.validate_coherence"

    Describe "tool=auto skips validation"
      setup_auto() {
        AUTO_WS="$(mktemp -d)"
        export BRIK_BUILD_TOOL="auto"
      }
      cleanup_auto() {
        rm -rf "$AUTO_WS"
        unset BRIK_BUILD_TOOL
      }
      Before 'setup_auto'
      After 'cleanup_auto'

      It "passes when tool is auto"
        When call config.python.validate_coherence "$AUTO_WS"
        The status should be success
      End
    End

    Describe "uv with pyproject.toml"
      setup_uv_match() {
        UV_WS="$(mktemp -d)"
        printf '[project]\nname = "test"\n' > "${UV_WS}/pyproject.toml"
        export BRIK_BUILD_TOOL="uv"
      }
      cleanup_uv_match() {
        rm -rf "$UV_WS"
        unset BRIK_BUILD_TOOL
      }
      Before 'setup_uv_match'
      After 'cleanup_uv_match'

      It "passes when pyproject.toml exists"
        When call config.python.validate_coherence "$UV_WS"
        The status should be success
      End
    End

    Describe "uv without project files"
      setup_uv_mismatch() {
        UV_MISS_WS="$(mktemp -d)"
        export BRIK_BUILD_TOOL="uv"
      }
      cleanup_uv_mismatch() {
        rm -rf "$UV_MISS_WS"
        unset BRIK_BUILD_TOOL
      }
      Before 'setup_uv_mismatch'
      After 'cleanup_uv_mismatch'

      It "fails with exit 7"
        When call config.python.validate_coherence "$UV_MISS_WS"
        The status should equal 7
        The stderr should include "config mismatch"
        The stderr should include "uv"
      End
    End

    Describe "poetry with poetry.lock"
      setup_poetry_match() {
        POETRY_WS="$(mktemp -d)"
        printf '' > "${POETRY_WS}/poetry.lock"
        export BRIK_BUILD_TOOL="poetry"
      }
      cleanup_poetry_match() {
        rm -rf "$POETRY_WS"
        unset BRIK_BUILD_TOOL
      }
      Before 'setup_poetry_match'
      After 'cleanup_poetry_match'

      It "passes when poetry.lock exists"
        When call config.python.validate_coherence "$POETRY_WS"
        The status should be success
      End
    End

    Describe "pipenv with Pipfile"
      setup_pipenv_match() {
        PIPENV_WS="$(mktemp -d)"
        printf '[[source]]\nurl = "https://pypi.org/simple"\n' > "${PIPENV_WS}/Pipfile"
        export BRIK_BUILD_TOOL="pipenv"
      }
      cleanup_pipenv_match() {
        rm -rf "$PIPENV_WS"
        unset BRIK_BUILD_TOOL
      }
      Before 'setup_pipenv_match'
      After 'cleanup_pipenv_match'

      It "passes when Pipfile exists"
        When call config.python.validate_coherence "$PIPENV_WS"
        The status should be success
      End
    End

    Describe "pipenv without Pipfile"
      setup_pipenv_mismatch() {
        PIPENV_MISS_WS="$(mktemp -d)"
        export BRIK_BUILD_TOOL="pipenv"
      }
      cleanup_pipenv_mismatch() {
        rm -rf "$PIPENV_MISS_WS"
        unset BRIK_BUILD_TOOL
      }
      Before 'setup_pipenv_mismatch'
      After 'cleanup_pipenv_mismatch'

      It "fails with exit 7"
        When call config.python.validate_coherence "$PIPENV_MISS_WS"
        The status should equal 7
        The stderr should include "config mismatch"
        The stderr should include "pipenv"
      End
    End

    Describe "pip with requirements.txt"
      setup_pip_match() {
        PIP_WS="$(mktemp -d)"
        printf 'requests==2.31.0\n' > "${PIP_WS}/requirements.txt"
        export BRIK_BUILD_TOOL="pip"
      }
      cleanup_pip_match() {
        rm -rf "$PIP_WS"
        unset BRIK_BUILD_TOOL
      }
      Before 'setup_pip_match'
      After 'cleanup_pip_match'

      It "passes when requirements.txt exists"
        When call config.python.validate_coherence "$PIP_WS"
        The status should be success
      End
    End

    Describe "pip without any project file"
      setup_pip_mismatch() {
        PIP_MISS_WS="$(mktemp -d)"
        export BRIK_BUILD_TOOL="pip"
      }
      cleanup_pip_mismatch() {
        rm -rf "$PIP_MISS_WS"
        unset BRIK_BUILD_TOOL
      }
      Before 'setup_pip_mismatch'
      After 'cleanup_pip_mismatch'

      It "fails with exit 7"
        When call config.python.validate_coherence "$PIP_MISS_WS"
        The status should equal 7
        The stderr should include "config mismatch"
        The stderr should include "pip"
      End
    End
  End
End
