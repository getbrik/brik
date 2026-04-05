Describe "publish/maven.sh"
  Include "$BRIK_RUNTIME_LIB/logging.sh"
  Include "$BRIK_RUNTIME_LIB/tools.sh"
  Include "$BRIK_CORE_LIB/publish.sh"
  Include "$BRIK_CORE_LIB/publish/maven.sh"

  Describe "publish.maven.run"
    It "returns 2 for unknown option"
      When call publish.maven.run --badopt foo
      The status should equal 2
      The stderr should include "unknown option"
    End

    Describe "no build file"
      setup_empty() {
        TEST_WS="$(mktemp -d)"
        ORIG_DIR="$(pwd)"
        cd "$TEST_WS" || return 1
      }
      cleanup_empty() {
        cd "$ORIG_DIR" || true
        rm -rf "$TEST_WS"
      }
      Before 'setup_empty'
      After 'cleanup_empty'

      It "returns 6 when no pom.xml or build.gradle"
        When call publish.maven.run
        The status should equal 6
        The stderr should include "no pom.xml or build.gradle"
      End
    End

    Describe "with mock mvn"
      setup_mvn() {
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_mvn.log"
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
        ORIG_DIR="$(pwd)"
        cd "$TEST_WS" || return 1
      }
      cleanup_mvn() {
        cd "$ORIG_DIR" || true
        export PATH="$ORIG_PATH"
        unset BRIK_DRY_RUN BRIK_PUBLISH_MAVEN_REPOSITORY 2>/dev/null
        rm -rf "$TEST_WS" "$MOCK_BIN"
      }
      Before 'setup_mvn'
      After 'cleanup_mvn'

      It "runs mvn deploy"
        invoke_deploy() {
          publish.maven.run 2>/dev/null || return 1
          grep -q "mvn deploy" "$MOCK_LOG"
        }
        When call invoke_deploy
        The status should be success
      End

      It "passes repository option"
        invoke_repo() {
          publish.maven.run --repository "https://maven.example.com" 2>/dev/null || return 1
          grep -q "altDeploymentRepository" "$MOCK_LOG"
        }
        When call invoke_repo
        The status should be success
      End

      It "uses dry-run mode"
        When call publish.maven.run --dry-run
        The status should be success
        The stderr should include "[dry-run]"
      End

      It "reports success"
        When call publish.maven.run
        The status should be success
        The stderr should include "maven publish completed"
      End
    End

    Describe "with gradle project"
      setup_gradle() {
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_gradle.log"
        printf 'apply plugin: java\n' > "${TEST_WS}/build.gradle"
        MOCK_BIN="$(mktemp -d)"
        cat > "${MOCK_BIN}/gradle" << MOCKEOF
#!/usr/bin/env bash
printf 'gradle %s\n' "\$*" >> "$MOCK_LOG"
exit 0
MOCKEOF
        chmod +x "${MOCK_BIN}/gradle"
        ORIG_PATH="$PATH"
        export PATH="${MOCK_BIN}:${PATH}"
        ORIG_DIR="$(pwd)"
        cd "$TEST_WS" || return 1
      }
      cleanup_gradle() {
        cd "$ORIG_DIR" || true
        export PATH="$ORIG_PATH"
        rm -rf "$TEST_WS" "$MOCK_BIN"
      }
      Before 'setup_gradle'
      After 'cleanup_gradle'

      It "runs gradle publish"
        invoke_gradle() {
          publish.maven.run 2>/dev/null || return 1
          grep -q "gradle publish" "$MOCK_LOG"
        }
        When call invoke_gradle
        The status should be success
      End
    End
  End
End
