Describe "config/java.sh"
  Include "$BRIK_RUNTIME_LIB/logging.sh"
  Include "$BRIK_CORE_LIB/config.sh"
  Include "$BRIK_CORE_LIB/config/java.sh"

  Describe "config.java.default"
    It "returns 'mvn package -DskipTests' for build_command"
      When call config.java.default "build_command"
      The output should equal "mvn package -DskipTests"
      The status should be success
    End

    It "returns 'junit' for test_framework"
      When call config.java.default "test_framework"
      The output should equal "junit"
    End

    It "returns 'checkstyle' for lint_tool"
      When call config.java.default "lint_tool"
      The output should equal "checkstyle"
    End

    It "returns 'google-java-format' for format_tool"
      When call config.java.default "format_tool"
      The output should equal "google-java-format"
    End

    It "returns 1 for unknown setting"
      When call config.java.default "unknown_setting"
      The status should equal 1
    End
  End

  Describe "config.java.export_build_vars"
    Describe "when java_version is configured"
      setup_config() {
        TEMP_CONFIG="$(mktemp)"
        cat > "$TEMP_CONFIG" <<'YAML'
version: 1
project:
  name: test
  stack: java
build:
  java_version: "21"
YAML
        export BRIK_CONFIG_FILE="$TEMP_CONFIG"
      }
      cleanup_config() {
        rm -f "$TEMP_CONFIG"
        unset BRIK_BUILD_JAVA_VERSION BRIK_CONFIG_FILE
      }
      Before 'setup_config'
      After 'cleanup_config'

      It "exports BRIK_BUILD_JAVA_VERSION"
        export_and_check() {
          config.java.export_build_vars
          printf '%s' "${BRIK_BUILD_JAVA_VERSION:-}"
        }
        When call export_and_check
        The output should equal "21"
      End
    End

    Describe "when java_version is not configured"
      setup_config() {
        TEMP_CONFIG="$(mktemp)"
        printf 'version: 1\nproject:\n  name: test\n  stack: java\n' > "$TEMP_CONFIG"
        export BRIK_CONFIG_FILE="$TEMP_CONFIG"
      }
      cleanup_config() {
        rm -f "$TEMP_CONFIG"
        unset BRIK_CONFIG_FILE
      }
      Before 'setup_config'
      After 'cleanup_config'

      It "does not export BRIK_BUILD_JAVA_VERSION"
        export_and_check() {
          unset BRIK_BUILD_JAVA_VERSION 2>/dev/null || true
          config.java.export_build_vars
          printf '%s' "${BRIK_BUILD_JAVA_VERSION:-UNSET}"
        }
        When call export_and_check
        The output should equal "UNSET"
      End
    End
  End
End
