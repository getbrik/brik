Describe "build/java.sh"
  Include "$BRIK_PIPELINE_LIB/logging.sh"
  Include "$BRIK_PIPELINE_LIB/tools.sh"
  Include "$BRIK_STACKS_LIB/java.sh"
  Include "$BRIK_HOME/spec/support/mock_helper.sh"

  Describe "_stacks.java._detect_tool"
    It "detects maven from pom.xml"
      When call _stacks.java._detect_tool "$WORKSPACES/java-maven"
      The output should equal "maven"
    End

    It "detects gradle from build.gradle"
      When call _stacks.java._detect_tool "$WORKSPACES/java-gradle"
      The output should equal "gradle"
    End

    Describe "detects gradle from build.gradle.kts"
      setup_kts() {
        TEST_WS="$(mktemp -d)"
        printf 'plugins { id("java") }\n' > "${TEST_WS}/build.gradle.kts"
      }
      cleanup_kts() { rm -rf "$TEST_WS"; }
      Before 'setup_kts'
      After 'cleanup_kts'

      It "detects gradle from build.gradle.kts"
        When call _stacks.java._detect_tool "$TEST_WS"
        The output should equal "gradle"
      End
    End

    It "returns empty for unknown workspace"
      When call _stacks.java._detect_tool "$WORKSPACES/unknown"
      The output should equal ""
    End
  End

  Describe "stacks.java.build"
    It "returns 6 for nonexistent workspace"
      When call stacks.java.build "/nonexistent/workspace"
      The status should equal 6
      The stderr should include "required directory not found"
    End

    It "returns 2 for unknown option"
      When call stacks.java.build "$WORKSPACES/java-maven" --badopt foo
      The status should equal 2
      The stderr should include "unknown option"
    End

    It "returns 7 when no build tool detected"
      When call stacks.java.build "$WORKSPACES/unknown"
      The status should equal 7
      The stderr should include "cannot detect Java build tool"
    End

    It "returns 7 for unsupported tool"
      When call stacks.java.build "$WORKSPACES/java-maven" --tool ant
      The status should equal 7
      The stderr should include "unsupported Java build tool"
    End

    Describe "require_tool mvn failure"
      setup_no_mvn() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        printf '<project/>\n' > "${TEST_WS}/pom.xml"
        mock.isolate
      }
      cleanup_no_mvn() {
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_no_mvn'
      After 'cleanup_no_mvn'

      It "returns 3 when mvn is not on PATH"
        When call stacks.java.build "$TEST_WS"
        The status should equal 3
        The stderr should include "required tool not found"
      End
    End

    Describe "require_tool gradle failure"
      setup_no_gradle() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        printf 'plugins { id "java" }\n' > "${TEST_WS}/build.gradle"
        mock.isolate
      }
      cleanup_no_gradle() {
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_no_gradle'
      After 'cleanup_no_gradle'

      It "returns 3 when gradle is not on PATH and no gradlew"
        When call stacks.java.build "$TEST_WS"
        The status should equal 3
        The stderr should include "required tool not found"
      End
    End

    Describe "with mock mvn"
      setup_mvn() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_mvn.log"
        printf '<project><modelVersion>4.0.0</modelVersion></project>\n' > "${TEST_WS}/pom.xml"
        mock.create_logging "mvn" "$MOCK_LOG"
        mock.activate
      }
      cleanup_mvn() {
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_mvn'
      After 'cleanup_mvn'

      It "runs mvn with default goals and succeeds"
        When call stacks.java.build "$TEST_WS"
        The status should be success
        The stderr should include "build completed successfully"
      End

      It "passes default goals: package -DskipTests"
        invoke_and_check_log() {
          stacks.java.build "$TEST_WS" 2>/dev/null || return 1
          grep -qx "mvn -B package -DskipTests" "$MOCK_LOG"
        }
        When call invoke_and_check_log
        The status should be success
      End

      It "passes custom goals"
        invoke_custom_goals() {
          stacks.java.build "$TEST_WS" --goals "clean install" 2>/dev/null || return 1
          grep -qx "mvn -B clean install" "$MOCK_LOG"
        }
        When call invoke_custom_goals
        The status should be success
      End
    End

    Describe "explicit --tool maven override on gradle workspace"
      setup_override() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_mvn.log"
        printf 'plugins { id "java" }\n' > "${TEST_WS}/build.gradle"
        printf '<project/>\n' > "${TEST_WS}/pom.xml"
        mock.create_logging "mvn" "$MOCK_LOG"
        mock.activate
      }
      cleanup_override() {
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_override'
      After 'cleanup_override'

      It "uses Maven when --tool maven is specified"
        invoke_tool_override() {
          stacks.java.build "$TEST_WS" --tool maven 2>/dev/null || return 1
          grep -q "^mvn " "$MOCK_LOG"
        }
        When call invoke_tool_override
        The status should be success
      End
    End

    Describe "with mock gradle"
      setup_gradle() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_gradle.log"
        printf 'plugins { id "java" }\n' > "${TEST_WS}/build.gradle"
        mock.create_logging "gradle" "$MOCK_LOG"
        mock.activate
      }
      cleanup_gradle() {
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_gradle'
      After 'cleanup_gradle'

      It "runs gradle with default goals and succeeds"
        When call stacks.java.build "$TEST_WS"
        The status should be success
        The stderr should include "build completed successfully"
      End

      It "passes default goals: build -x test"
        invoke_gradle_check() {
          stacks.java.build "$TEST_WS" 2>/dev/null || return 1
          grep -qx "gradle build -x test" "$MOCK_LOG"
        }
        When call invoke_gradle_check
        The status should be success
      End

      It "passes custom goals to gradle"
        invoke_gradle_custom() {
          stacks.java.build "$TEST_WS" --tool gradle --goals "clean build" 2>/dev/null || return 1
          grep -qx "gradle clean build" "$MOCK_LOG"
        }
        When call invoke_gradle_custom
        The status should be success
      End
    End

    Describe "with gradlew wrapper"
      setup_gradlew() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_gradlew.log"
        printf 'plugins { id "java" }\n' > "${TEST_WS}/build.gradle"
        cat > "${TEST_WS}/gradlew" << MOCKEOF
#!/usr/bin/env bash
printf 'gradlew %s\n' "\$*" >> "$MOCK_LOG"
exit 0
MOCKEOF
        chmod +x "${TEST_WS}/gradlew"
        ln -sf "$(command -v bash)" "${MOCK_BIN}/bash"
        ln -sf "$(command -v grep)" "${MOCK_BIN}/grep"
        mock.isolate
      }
      cleanup_gradlew() {
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_gradlew'
      After 'cleanup_gradlew'

      It "uses gradlew when present and succeeds"
        When call stacks.java.build "$TEST_WS"
        The status should be success
        The stderr should include "build completed successfully"
      End

      It "invokes gradlew not gradle"
        invoke_gradlew_check() {
          stacks.java.build "$TEST_WS" 2>/dev/null || return 1
          grep -q "^gradlew " "$MOCK_LOG"
        }
        When call invoke_gradlew_check
        The status should be success
      End
    End

    Describe "with failing mvn"
      setup_fail() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        printf '<project/>\n' > "${TEST_WS}/pom.xml"
        mock.create_exit "mvn" 1
        mock.activate
      }
      cleanup_fail() {
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_fail'
      After 'cleanup_fail'

      It "returns 5 when build fails"
        When call stacks.java.build "$TEST_WS"
        The status should equal 5
        The stderr should include "build failed"
      End
    End
  End
End
Describe "test/java.sh"
  Include "$BRIK_PIPELINE_LIB/logging.sh"
  Include "$BRIK_PIPELINE_LIB/tools.sh"
  Include "$BRIK_STACKS_LIB/java.sh"

  Describe "stacks.java.test_cmd"
    It "returns mvn test for maven framework"
      When call stacks.java.test_cmd "maven" "/workspace" ""
      The output should equal "mvn -B test"
    End

    It "returns mvn test for junit framework"
      When call stacks.java.test_cmd "junit" "/workspace" ""
      The output should equal "mvn -B test"
    End

    It "adds surefire report dir when report_dir is provided"
      When call stacks.java.test_cmd "maven" "/workspace" "/reports"
      The output should equal "mvn -B test -Dsurefire.reportsDirectory=/reports"
    End

    It "returns gradle test for gradle framework"
      When call stacks.java.test_cmd "gradle" "/workspace" ""
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
        When call stacks.java.test_cmd "gradle" "$TEST_WS" ""
        The output should equal "./gradlew test"
      End
    End

    It "returns 7 for unsupported framework"
      When call stacks.java.test_cmd "unknown" "/workspace" ""
      The status should equal 7
      The stderr should include "unsupported Java test framework"
    End
  End

  Describe "stacks.java.test"
    Describe "with pom.xml"
      setup_maven() {
        TEST_WS="$(mktemp -d)"
        printf '<project/>\n' > "${TEST_WS}/pom.xml"
      }
      cleanup_maven() { rm -rf "$TEST_WS"; }
      Before 'setup_maven'
      After 'cleanup_maven'

      It "auto-detects maven from pom.xml"
        When call stacks.java.test "$TEST_WS" ""
        The output should equal "mvn -B test"
      End

      It "passes report_dir to maven"
        When call stacks.java.test "$TEST_WS" "/reports"
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
        When call stacks.java.test "$TEST_WS" ""
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
        When call stacks.java.test "$TEST_WS" ""
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
        When call stacks.java.test "$TEST_WS" ""
        The status should equal 7
        The stderr should include "cannot detect Java test tool"
      End
    End
  End
End
