Describe "config/dotnet.sh"
  Include "$BRIK_RUNTIME_LIB/logging.sh"
  Include "$BRIK_CORE_LIB/config.sh"
  Include "$BRIK_CORE_LIB/config/dotnet.sh"

  Describe "config.dotnet.default"
    It "returns empty string for build_command"
      When call config.dotnet.default "build_command"
      The output should equal ""
      The status should be success
    End

    It "returns 'xunit' for test_framework"
      When call config.dotnet.default "test_framework"
      The output should equal "xunit"
    End

    It "returns 'dotnet-format' for lint_tool"
      When call config.dotnet.default "lint_tool"
      The output should equal "dotnet-format"
    End

    It "returns 'dotnet-format' for format_tool"
      When call config.dotnet.default "format_tool"
      The output should equal "dotnet-format"
    End

    It "returns 1 for unknown setting"
      When call config.dotnet.default "unknown_setting"
      The status should equal 1
    End
  End

  Describe "config.dotnet.export_build_vars"
    Describe "when dotnet_version is configured"
      setup_config() {
        TEMP_CONFIG="$(mktemp)"
        cat > "$TEMP_CONFIG" <<'YAML'
version: 1
project:
  name: test
  stack: dotnet
build:
  dotnet_version: "8.0"
YAML
        export BRIK_CONFIG_FILE="$TEMP_CONFIG"
      }
      cleanup_config() {
        rm -f "$TEMP_CONFIG"
        unset BRIK_BUILD_DOTNET_VERSION BRIK_CONFIG_FILE
      }
      Before 'setup_config'
      After 'cleanup_config'

      It "exports BRIK_BUILD_DOTNET_VERSION"
        export_and_check() {
          config.dotnet.export_build_vars
          printf '%s' "${BRIK_BUILD_DOTNET_VERSION:-}"
        }
        When call export_and_check
        The output should equal "8.0"
      End
    End

    Describe "when dotnet_version is not configured"
      setup_config() {
        TEMP_CONFIG="$(mktemp)"
        printf 'version: 1\nproject:\n  name: test\n  stack: dotnet\n' > "$TEMP_CONFIG"
        export BRIK_CONFIG_FILE="$TEMP_CONFIG"
      }
      cleanup_config() {
        rm -f "$TEMP_CONFIG"
        unset BRIK_CONFIG_FILE
      }
      Before 'setup_config'
      After 'cleanup_config'

      It "does not export BRIK_BUILD_DOTNET_VERSION"
        export_and_check() {
          unset BRIK_BUILD_DOTNET_VERSION 2>/dev/null || true
          config.dotnet.export_build_vars
          printf '%s' "${BRIK_BUILD_DOTNET_VERSION:-UNSET}"
        }
        When call export_and_check
        The output should equal "UNSET"
      End
    End
  End
End
