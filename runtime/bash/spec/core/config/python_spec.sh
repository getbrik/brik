Describe "config/python.sh"
  Include "$BRIK_RUNTIME_LIB/logging.sh"
  Include "$BRIK_CORE_LIB/config.sh"
  Include "$BRIK_CORE_LIB/config/python.sh"

  Describe "config.python.default"
    It "returns 'pip install .' for build_command"
      When call config.python.default "build_command"
      The output should equal "pip install ."
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

    It "returns 'ruff format' for format_tool"
      When call config.python.default "format_tool"
      The output should equal "ruff format"
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
End
