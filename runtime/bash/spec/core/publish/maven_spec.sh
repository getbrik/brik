Describe "publish/maven.sh"
  Include "$BRIK_RUNTIME_LIB/logging.sh"
  Include "$BRIK_RUNTIME_LIB/tools.sh"
  Include "$BRIK_CORE_LIB/publish.sh"
  Include "$BRIK_CORE_LIB/publish/maven.sh"
  Include "$BRIK_HOME/runtime/bash/spec/support/mock_helper.sh"

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
        mock.setup
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_mvn.log"
        printf '<project/>\n' > "${TEST_WS}/pom.xml"
        mock.create_logging "mvn" "$MOCK_LOG"
        mock.activate
        ORIG_DIR="$(pwd)"
        cd "$TEST_WS" || return 1
      }
      cleanup_mvn() {
        cd "$ORIG_DIR" || true
        mock.cleanup
        unset BRIK_DRY_RUN BRIK_PUBLISH_MAVEN_REPOSITORY 2>/dev/null
        rm -rf "$TEST_WS"
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

      It "writes temporary settings.xml with credentials"
        invoke_creds() {
          export MY_MVN_USER="admin"
          export MY_MVN_PASS="secret123"
          publish.maven.run --username-var "MY_MVN_USER" --password-var "MY_MVN_PASS" 2>/dev/null || return 1
          grep -q "\-\-settings" "$MOCK_LOG"
        }
        When call invoke_creds
        The status should be success
      End

      It "cleans up settings.xml after publish"
        invoke_creds_cleanup() {
          export MY_MVN_USER="admin"
          export MY_MVN_PASS="secret123"
          publish.maven.run --username-var "MY_MVN_USER" --password-var "MY_MVN_PASS" 2>/dev/null || return 1
          # Extract settings file path from mock log
          local settings_path
          settings_path="$(grep -o '\-\-settings [^ ]*' "$MOCK_LOG" | awk '{print $2}')"
          # File should have been deleted after publish
          [[ ! -f "$settings_path" ]]
        }
        When call invoke_creds_cleanup
        The status should be success
      End

      It "returns 7 when username_var references unset variable"
        When call publish.maven.run --username-var "NONEXISTENT_VAR_12345"
        The status should equal 7
        The stderr should include "is not set or empty"
      End

      It "returns 7 when password_var references unset variable"
        invoke_bad_pass() {
          export MY_MVN_USER="admin"
          publish.maven.run --username-var "MY_MVN_USER" --password-var "NONEXISTENT_VAR_12345"
        }
        When call invoke_bad_pass
        The status should equal 7
        The stderr should include "is not set or empty"
      End
    End

    Describe "with failing mvn"
      setup_fail_mvn() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        printf '<project/>\n' > "${TEST_WS}/pom.xml"
        mock.create_exit "mvn" 1
        mock.activate
        ORIG_DIR="$(pwd)"
        cd "$TEST_WS" || return 1
      }
      cleanup_fail_mvn() {
        cd "$ORIG_DIR" || true
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_fail_mvn'
      After 'cleanup_fail_mvn'

      It "returns 5 when mvn deploy fails"
        When call publish.maven.run
        The status should equal 5
        The stderr should include "maven publish failed"
      End
    End

    Describe "with gradle project"
      setup_gradle() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_gradle.log"
        printf 'apply plugin: java\n' > "${TEST_WS}/build.gradle"
        mock.create_logging "gradle" "$MOCK_LOG"
        mock.activate
        ORIG_DIR="$(pwd)"
        cd "$TEST_WS" || return 1
      }
      cleanup_gradle() {
        cd "$ORIG_DIR" || true
        mock.cleanup
        rm -rf "$TEST_WS"
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
