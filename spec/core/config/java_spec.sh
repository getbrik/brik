Describe "config/java.sh"
  Include "$BRIK_RUNTIME_LIB/logging.sh"
  Include "$BRIK_CORE_LIB/config.sh"
  Include "$BRIK_CORE_LIB/config/java.sh"

  Describe "config.java.default"
    It "returns empty string for build_command"
      When call config.java.default "build_command"
      The output should equal ""
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

  Describe "config.java.validate_coherence"

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
        When call config.java.validate_coherence "$AUTO_WS"
        The status should be success
      End
    End

    Describe "maven with pom.xml"
      setup_maven_match() {
        MAVEN_WS="$(mktemp -d)"
        printf '<project/>\n' > "${MAVEN_WS}/pom.xml"
        export BRIK_BUILD_TOOL="maven"
      }
      cleanup_maven_match() {
        rm -rf "$MAVEN_WS"
        unset BRIK_BUILD_TOOL
      }
      Before 'setup_maven_match'
      After 'cleanup_maven_match'

      It "passes when pom.xml exists"
        When call config.java.validate_coherence "$MAVEN_WS"
        The status should be success
      End
    End

    Describe "maven without pom.xml"
      setup_maven_mismatch() {
        MAVEN_MISS_WS="$(mktemp -d)"
        export BRIK_BUILD_TOOL="maven"
      }
      cleanup_maven_mismatch() {
        rm -rf "$MAVEN_MISS_WS"
        unset BRIK_BUILD_TOOL
      }
      Before 'setup_maven_mismatch'
      After 'cleanup_maven_mismatch'

      It "fails with exit 7"
        When call config.java.validate_coherence "$MAVEN_MISS_WS"
        The status should equal 7
        The stderr should include "config mismatch"
        The stderr should include "maven"
      End
    End

    Describe "gradle with build.gradle"
      setup_gradle_match() {
        GRADLE_WS="$(mktemp -d)"
        printf 'apply plugin: "java"\n' > "${GRADLE_WS}/build.gradle"
        export BRIK_BUILD_TOOL="gradle"
      }
      cleanup_gradle_match() {
        rm -rf "$GRADLE_WS"
        unset BRIK_BUILD_TOOL
      }
      Before 'setup_gradle_match'
      After 'cleanup_gradle_match'

      It "passes when build.gradle exists"
        When call config.java.validate_coherence "$GRADLE_WS"
        The status should be success
      End
    End

    Describe "gradle with build.gradle.kts"
      setup_gradle_kts() {
        GRADLE_KTS_WS="$(mktemp -d)"
        printf 'plugins { java }\n' > "${GRADLE_KTS_WS}/build.gradle.kts"
        export BRIK_BUILD_TOOL="gradle"
      }
      cleanup_gradle_kts() {
        rm -rf "$GRADLE_KTS_WS"
        unset BRIK_BUILD_TOOL
      }
      Before 'setup_gradle_kts'
      After 'cleanup_gradle_kts'

      It "passes when build.gradle.kts exists"
        When call config.java.validate_coherence "$GRADLE_KTS_WS"
        The status should be success
      End
    End

    Describe "gradle without build files"
      setup_gradle_mismatch() {
        GRADLE_MISS_WS="$(mktemp -d)"
        export BRIK_BUILD_TOOL="gradle"
      }
      cleanup_gradle_mismatch() {
        rm -rf "$GRADLE_MISS_WS"
        unset BRIK_BUILD_TOOL
      }
      Before 'setup_gradle_mismatch'
      After 'cleanup_gradle_mismatch'

      It "fails with exit 7"
        When call config.java.validate_coherence "$GRADLE_MISS_WS"
        The status should equal 7
        The stderr should include "config mismatch"
        The stderr should include "gradle"
      End
    End
  End
End
