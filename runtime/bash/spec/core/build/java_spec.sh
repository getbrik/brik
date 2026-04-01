Describe "build/java.sh"
  Include "$BRIK_RUNTIME_LIB/logging.sh"
  Include "$BRIK_RUNTIME_LIB/tools.sh"
  Include "$BRIK_CORE_LIB/build/java.sh"

  Describe "_build.java._detect_tool"
    It "detects maven from pom.xml"
      When call _build.java._detect_tool "$WORKSPACES/java-maven"
      The output should equal "maven"
    End

    It "detects gradle from build.gradle"
      When call _build.java._detect_tool "$WORKSPACES/java-gradle"
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
        When call _build.java._detect_tool "$TEST_WS"
        The output should equal "gradle"
      End
    End

    It "returns empty for unknown workspace"
      When call _build.java._detect_tool "$WORKSPACES/unknown"
      The output should equal ""
    End
  End

  Describe "build.java.run"
    It "returns 6 for nonexistent workspace"
      When call build.java.run "/nonexistent/workspace"
      The status should equal 6
      The stderr should include "required directory not found"
    End

    It "returns 2 for unknown option"
      When call build.java.run "$WORKSPACES/java-maven" --badopt foo
      The status should equal 2
      The stderr should include "unknown option"
    End

    It "returns 7 when no build tool detected"
      When call build.java.run "$WORKSPACES/unknown"
      The status should equal 7
      The stderr should include "cannot detect Java build tool"
    End

    It "returns 7 for unsupported tool"
      When call build.java.run "$WORKSPACES/java-maven" --tool ant
      The status should equal 7
      The stderr should include "unsupported Java build tool"
    End

    Describe "require_tool mvn failure"
      setup_no_mvn() {
        TEST_WS="$(mktemp -d)"
        printf '<project/>\n' > "${TEST_WS}/pom.xml"
        MOCK_BIN="$(mktemp -d)"
        ORIG_PATH="$PATH"
        export PATH="${MOCK_BIN}"
      }
      cleanup_no_mvn() {
        export PATH="$ORIG_PATH"
        rm -rf "$TEST_WS" "$MOCK_BIN"
      }
      Before 'setup_no_mvn'
      After 'cleanup_no_mvn'

      It "returns 3 when mvn is not on PATH"
        When call build.java.run "$TEST_WS"
        The status should equal 3
        The stderr should include "required tool not found"
      End
    End

    Describe "require_tool gradle failure"
      setup_no_gradle() {
        TEST_WS="$(mktemp -d)"
        printf 'plugins { id "java" }\n' > "${TEST_WS}/build.gradle"
        MOCK_BIN="$(mktemp -d)"
        ORIG_PATH="$PATH"
        export PATH="${MOCK_BIN}"
      }
      cleanup_no_gradle() {
        export PATH="$ORIG_PATH"
        rm -rf "$TEST_WS" "$MOCK_BIN"
      }
      Before 'setup_no_gradle'
      After 'cleanup_no_gradle'

      It "returns 3 when gradle is not on PATH and no gradlew"
        When call build.java.run "$TEST_WS"
        The status should equal 3
        The stderr should include "required tool not found"
      End
    End

    Describe "with mock mvn"
      setup_mvn() {
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_mvn.log"
        printf '<project><modelVersion>4.0.0</modelVersion></project>\n' > "${TEST_WS}/pom.xml"
        MOCK_BIN="$(mktemp -d)"
        cat > "${MOCK_BIN}/mvn" << MOCKEOF
#!/usr/bin/env bash
printf 'mvn %s\n' "\$*" >> "$MOCK_LOG"
exit 0
MOCKEOF
        chmod +x "${MOCK_BIN}/mvn"
        ORIG_PATH="$PATH"
        export PATH="${MOCK_BIN}:${PATH}"
      }
      cleanup_mvn() {
        export PATH="$ORIG_PATH"
        rm -rf "$TEST_WS" "$MOCK_BIN"
      }
      Before 'setup_mvn'
      After 'cleanup_mvn'

      It "runs mvn with default goals and succeeds"
        When call build.java.run "$TEST_WS"
        The status should be success
        The stderr should include "build completed successfully"
      End

      It "passes default goals: package -DskipTests"
        invoke_and_check_log() {
          build.java.run "$TEST_WS" 2>/dev/null || return 1
          grep -qx "mvn package -DskipTests" "$MOCK_LOG"
        }
        When call invoke_and_check_log
        The status should be success
      End

      It "passes custom goals"
        invoke_custom_goals() {
          build.java.run "$TEST_WS" --goals "clean install" 2>/dev/null || return 1
          grep -qx "mvn clean install" "$MOCK_LOG"
        }
        When call invoke_custom_goals
        The status should be success
      End
    End

    Describe "explicit --tool maven override on gradle workspace"
      setup_override() {
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_mvn.log"
        printf 'plugins { id "java" }\n' > "${TEST_WS}/build.gradle"
        printf '<project/>\n' > "${TEST_WS}/pom.xml"
        MOCK_BIN="$(mktemp -d)"
        cat > "${MOCK_BIN}/mvn" << MOCKEOF
#!/usr/bin/env bash
printf 'mvn %s\n' "\$*" >> "$MOCK_LOG"
exit 0
MOCKEOF
        chmod +x "${MOCK_BIN}/mvn"
        ORIG_PATH="$PATH"
        export PATH="${MOCK_BIN}:${PATH}"
      }
      cleanup_override() {
        export PATH="$ORIG_PATH"
        rm -rf "$TEST_WS" "$MOCK_BIN"
      }
      Before 'setup_override'
      After 'cleanup_override'

      It "uses Maven when --tool maven is specified"
        invoke_tool_override() {
          build.java.run "$TEST_WS" --tool maven 2>/dev/null || return 1
          grep -q "^mvn " "$MOCK_LOG"
        }
        When call invoke_tool_override
        The status should be success
      End
    End

    Describe "with mock gradle"
      setup_gradle() {
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_gradle.log"
        printf 'plugins { id "java" }\n' > "${TEST_WS}/build.gradle"
        MOCK_BIN="$(mktemp -d)"
        cat > "${MOCK_BIN}/gradle" << MOCKEOF
#!/usr/bin/env bash
printf 'gradle %s\n' "\$*" >> "$MOCK_LOG"
exit 0
MOCKEOF
        chmod +x "${MOCK_BIN}/gradle"
        ORIG_PATH="$PATH"
        export PATH="${MOCK_BIN}:${PATH}"
      }
      cleanup_gradle() {
        export PATH="$ORIG_PATH"
        rm -rf "$TEST_WS" "$MOCK_BIN"
      }
      Before 'setup_gradle'
      After 'cleanup_gradle'

      It "runs gradle with default goals and succeeds"
        When call build.java.run "$TEST_WS"
        The status should be success
        The stderr should include "build completed successfully"
      End

      It "passes default goals: build -x test"
        invoke_gradle_check() {
          build.java.run "$TEST_WS" 2>/dev/null || return 1
          grep -qx "gradle build -x test" "$MOCK_LOG"
        }
        When call invoke_gradle_check
        The status should be success
      End

      It "passes custom goals to gradle"
        invoke_gradle_custom() {
          build.java.run "$TEST_WS" --tool gradle --goals "clean build" 2>/dev/null || return 1
          grep -qx "gradle clean build" "$MOCK_LOG"
        }
        When call invoke_gradle_custom
        The status should be success
      End
    End

    Describe "with gradlew wrapper"
      setup_gradlew() {
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_gradlew.log"
        printf 'plugins { id "java" }\n' > "${TEST_WS}/build.gradle"
        cat > "${TEST_WS}/gradlew" << MOCKEOF
#!/usr/bin/env bash
printf 'gradlew %s\n' "\$*" >> "$MOCK_LOG"
exit 0
MOCKEOF
        chmod +x "${TEST_WS}/gradlew"
        ORIG_PATH="$PATH"
        MOCK_BIN="$(mktemp -d)"
        ln -sf "$(command -v bash)" "${MOCK_BIN}/bash"
        ln -sf "$(command -v grep)" "${MOCK_BIN}/grep"
        export PATH="${MOCK_BIN}"
      }
      cleanup_gradlew() {
        export PATH="$ORIG_PATH"
        rm -rf "$TEST_WS" "$MOCK_BIN"
      }
      Before 'setup_gradlew'
      After 'cleanup_gradlew'

      It "uses gradlew when present and succeeds"
        When call build.java.run "$TEST_WS"
        The status should be success
        The stderr should include "build completed successfully"
      End

      It "invokes gradlew not gradle"
        invoke_gradlew_check() {
          build.java.run "$TEST_WS" 2>/dev/null || return 1
          grep -q "^gradlew " "$MOCK_LOG"
        }
        When call invoke_gradlew_check
        The status should be success
      End
    End

    Describe "with failing mvn"
      setup_fail() {
        TEST_WS="$(mktemp -d)"
        printf '<project/>\n' > "${TEST_WS}/pom.xml"
        MOCK_BIN="$(mktemp -d)"
        cat > "${MOCK_BIN}/mvn" << 'EOF'
#!/usr/bin/env bash
exit 1
EOF
        chmod +x "${MOCK_BIN}/mvn"
        ORIG_PATH="$PATH"
        export PATH="${MOCK_BIN}:${PATH}"
      }
      cleanup_fail() {
        export PATH="$ORIG_PATH"
        rm -rf "$TEST_WS" "$MOCK_BIN"
      }
      Before 'setup_fail'
      After 'cleanup_fail'

      It "returns 5 when build fails"
        When call build.java.run "$TEST_WS"
        The status should equal 5
        The stderr should include "build failed"
      End
    End
  End
End
