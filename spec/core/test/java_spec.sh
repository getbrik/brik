Describe "test/java.sh"
  Include "$BRIK_RUNTIME_LIB/logging.sh"
  Include "$BRIK_RUNTIME_LIB/tools.sh"
  Include "$BRIK_CORE_LIB/test/java.sh"

  Describe "test.java.cmd"
    It "returns mvn test for maven framework"
      When call test.java.cmd "maven" "/workspace" ""
      The output should equal "mvn -B test"
    End

    It "returns mvn test for junit framework"
      When call test.java.cmd "junit" "/workspace" ""
      The output should equal "mvn -B test"
    End

    It "adds surefire report dir when report_dir is provided"
      When call test.java.cmd "maven" "/workspace" "/reports"
      The output should equal "mvn -B test -Dsurefire.reportsDirectory=/reports"
    End

    It "returns gradle test for gradle framework"
      When call test.java.cmd "gradle" "/workspace" ""
      The output should equal "gradle test"
    End

    Describe "with gradlew present"
      setup_gradlew() {
        TEST_WS="$(mktemp -d)"
        printf 'plugins { id "java" }\n' > "${TEST_WS}/build.gradle"
        touch "${TEST_WS}/gradlew"
        chmod +x "${TEST_WS}/gradlew"
      }
      cleanup_gradlew() { rm -rf "$TEST_WS"; }
      Before 'setup_gradlew'
      After 'cleanup_gradlew'

      It "uses ./gradlew test when gradlew is executable"
        When call test.java.cmd "gradle" "$TEST_WS" ""
        The output should equal "./gradlew test"
      End
    End

    It "returns 7 for unsupported framework"
      When call test.java.cmd "unknown" "/workspace" ""
      The status should equal 7
      The stderr should include "unsupported Java test framework"
    End
  End

  Describe "test.java.run_cmd"
    Describe "with pom.xml"
      setup_maven() {
        TEST_WS="$(mktemp -d)"
        printf '<project/>\n' > "${TEST_WS}/pom.xml"
      }
      cleanup_maven() { rm -rf "$TEST_WS"; }
      Before 'setup_maven'
      After 'cleanup_maven'

      It "auto-detects maven from pom.xml"
        When call test.java.run_cmd "$TEST_WS" ""
        The output should equal "mvn -B test"
      End

      It "passes report_dir to maven"
        When call test.java.run_cmd "$TEST_WS" "/reports"
        The output should equal "mvn -B test -Dsurefire.reportsDirectory=/reports"
      End
    End

    Describe "with build.gradle"
      setup_gradle() {
        TEST_WS="$(mktemp -d)"
        printf 'plugins { id "java" }\n' > "${TEST_WS}/build.gradle"
      }
      cleanup_gradle() { rm -rf "$TEST_WS"; }
      Before 'setup_gradle'
      After 'cleanup_gradle'

      It "auto-detects gradle from build.gradle"
        When call test.java.run_cmd "$TEST_WS" ""
        The output should equal "gradle test"
      End
    End

    Describe "with build.gradle.kts"
      setup_gradle_kts() {
        TEST_WS="$(mktemp -d)"
        printf 'plugins { id("java") }\n' > "${TEST_WS}/build.gradle.kts"
      }
      cleanup_gradle_kts() { rm -rf "$TEST_WS"; }
      Before 'setup_gradle_kts'
      After 'cleanup_gradle_kts'

      It "auto-detects gradle from build.gradle.kts"
        When call test.java.run_cmd "$TEST_WS" ""
        The output should equal "gradle test"
      End
    End

    Describe "with unknown workspace"
      setup_empty() {
        TEST_WS="$(mktemp -d)"
      }
      cleanup_empty() { rm -rf "$TEST_WS"; }
      Before 'setup_empty'
      After 'cleanup_empty'

      It "returns 7 when no Java build tool detected"
        When call test.java.run_cmd "$TEST_WS" ""
        The status should equal 7
        The stderr should include "cannot detect Java test tool"
      End
    End
  End
End
