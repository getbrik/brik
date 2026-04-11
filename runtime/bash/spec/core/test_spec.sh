Describe "test.sh"
  Include "$BRIK_RUNTIME_LIB/logging.sh"
  Include "$BRIK_RUNTIME_LIB/tools.sh"
  Include "$BRIK_CORE_LIB/_loader.sh"
  Include "$BRIK_CORE_LIB/build.sh"
  Include "$BRIK_CORE_LIB/test.sh"
  Include "$BRIK_HOME/runtime/bash/spec/support/mock_helper.sh"

  Describe "test.run"
    It "returns 6 for nonexistent workspace"
      When call test.run "/nonexistent/workspace"
      The status should equal 6
      The stderr should include "required directory not found"
    End

    Describe "unknown option"
      setup_ws() {
        TEST_WS="$(mktemp -d)"
      }
      cleanup_ws() { rm -rf "$TEST_WS"; }
      Before 'setup_ws'
      After 'cleanup_ws'

      It "returns 2 for unknown option"
        When call test.run "$TEST_WS" --badopt foo
        The status should equal 2
        The stderr should include "unknown option"
      End
    End

    Describe "with Node.js workspace"
      setup_node() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_npm.log"
        printf '{"name":"test","scripts":{"test":"echo ok"}}\n' > "${TEST_WS}/package.json"
        mock.create_logging "npm" "$MOCK_LOG"
        mock.create_script "node" 'if [ "$1" = "-e" ]; then printf "yes\n"; fi
exit 0'
        mock.activate
      }
      cleanup_node() {
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_node'
      After 'cleanup_node'

      It "detects Node.js and runs npm test"
        invoke_npm_test() {
          test.run "$TEST_WS" 2>/dev/null || return 1
          grep -q "^npm test" "$MOCK_LOG"
        }
        When call invoke_npm_test
        The status should be success
      End

      It "logs the suite being run"
        When call test.run "$TEST_WS" --suite integration
        The status should be success
        The stderr should include "running integration tests"
      End

      It "succeeds and reports tests passed"
        When call test.run "$TEST_WS"
        The status should be success
        The stderr should include "tests passed"
      End
    End

    Describe "with Python workspace"
      setup_py() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_python.log"
        printf '[project]\nname = "test"\n' > "${TEST_WS}/pyproject.toml"
        mock.create_logging "python" "$MOCK_LOG"
        mock.activate
      }
      cleanup_py() {
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_py'
      After 'cleanup_py'

      It "detects Python and runs pytest"
        invoke_pytest() {
          test.run "$TEST_WS" 2>/dev/null || return 1
          grep -q "^python -m pytest" "$MOCK_LOG"
        }
        When call invoke_pytest
        The status should be success
      End

      It "passes --junitxml when --report-dir is set"
        invoke_junitxml() {
          test.run "$TEST_WS" --report-dir "${TEST_WS}/reports" 2>/dev/null || return 1
          grep -q "\-\-junitxml=" "$MOCK_LOG"
        }
        When call invoke_junitxml
        The status should be success
      End
    End

    Describe "with Java Maven workspace"
      setup_java() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_mvn.log"
        printf '<project/>\n' > "${TEST_WS}/pom.xml"
        mock.create_logging "mvn" "$MOCK_LOG"
        mock.activate
      }
      cleanup_java() {
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_java'
      After 'cleanup_java'

      It "detects Java and invokes mvn test"
        invoke_mvn() {
          test.run "$TEST_WS" 2>/dev/null || return 1
          grep -q "^mvn -B test" "$MOCK_LOG"
        }
        When call invoke_mvn
        The status should be success
      End

      It "passes -Dsurefire.reportsDirectory when --report-dir is set"
        invoke_mvn_report() {
          test.run "$TEST_WS" --report-dir "${TEST_WS}/reports" 2>/dev/null || return 1
          grep -q "\-Dsurefire.reportsDirectory=" "$MOCK_LOG"
        }
        When call invoke_mvn_report
        The status should be success
      End
    End

    Describe "with Gradle workspace"
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

      It "detects Gradle and runs gradle test"
        invoke_gradle() {
          test.run "$TEST_WS" 2>/dev/null || return 1
          grep -q "^gradle test" "$MOCK_LOG"
        }
        When call invoke_gradle
        The status should be success
      End
    End

    Describe "with build.gradle.kts workspace"
      setup_gradle_kts() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_gradle.log"
        printf 'plugins { id("java") }\n' > "${TEST_WS}/build.gradle.kts"
        mock.create_logging "gradle" "$MOCK_LOG"
        mock.activate
      }
      cleanup_gradle_kts() {
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_gradle_kts'
      After 'cleanup_gradle_kts'

      It "detects build.gradle.kts and runs gradle test"
        invoke_gradle_kts() {
          test.run "$TEST_WS" 2>/dev/null || return 1
          grep -q "^gradle test" "$MOCK_LOG"
        }
        When call invoke_gradle_kts
        The status should be success
      End
    End

    Describe "with Gradle wrapper"
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
        mock.preserve_cmds
        ln -sf "$(command -v bash)" "${MOCK_BIN}/bash"
        mock.isolate
      }
      cleanup_gradlew() {
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_gradlew'
      After 'cleanup_gradlew'

      It "uses gradlew when present"
        invoke_gradlew() {
          test.run "$TEST_WS" 2>/dev/null || return 1
          grep -q "^gradlew test" "$MOCK_LOG"
        }
        When call invoke_gradlew
        The status should be success
      End
    End

    Describe "with --framework override"
      setup_framework() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_cargo.log"
        mock.create_logging "cargo" "$MOCK_LOG"
        mock.activate
      }
      cleanup_framework() {
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_framework'
      After 'cleanup_framework'

      It "uses specified framework regardless of workspace content"
        invoke_cargo() {
          test.run "$TEST_WS" --framework cargo 2>/dev/null || return 1
          grep -q "^cargo test" "$MOCK_LOG"
        }
        When call invoke_cargo
        The status should be success
      End

      It "returns 7 for unsupported framework"
        When call test.run "$TEST_WS" --framework unknown
        The status should equal 7
        The stderr should include "unsupported test framework"
      End
    End

    Describe "with --framework npm"
      setup_npm() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_npm.log"
        mock.create_logging "npm" "$MOCK_LOG"
        mock.activate
      }
      cleanup_npm() {
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_npm'
      After 'cleanup_npm'

      It "runs npm test"
        invoke_npm() {
          test.run "$TEST_WS" --framework npm 2>/dev/null || return 1
          grep -q "^npm test" "$MOCK_LOG"
        }
        When call invoke_npm
        The status should be success
      End
    End

    Describe "with --framework dotnet"
      setup_dotnet() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_dotnet.log"
        mock.create_logging "dotnet" "$MOCK_LOG"
        mock.activate
      }
      cleanup_dotnet() {
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_dotnet'
      After 'cleanup_dotnet'

      It "runs dotnet test"
        invoke_dotnet() {
          test.run "$TEST_WS" --framework dotnet 2>/dev/null || return 1
          grep -q "^dotnet test" "$MOCK_LOG"
        }
        When call invoke_dotnet
        The status should be success
      End
    End

    Describe "with Rust workspace (Cargo.toml)"
      setup_rust() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_cargo.log"
        printf '[package]\nname = "test"\n' > "${TEST_WS}/Cargo.toml"
        mock.create_logging "cargo" "$MOCK_LOG"
        mock.activate
      }
      cleanup_rust() {
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_rust'
      After 'cleanup_rust'

      It "detects Rust and runs cargo test"
        invoke_cargo_auto() {
          test.run "$TEST_WS" 2>/dev/null || return 1
          grep -q "^cargo test" "$MOCK_LOG"
        }
        When call invoke_cargo_auto
        The status should be success
      End
    End

    Describe "with unknown workspace"
      setup_empty() {
        TEST_WS="$(mktemp -d)"
      }
      cleanup_empty() { rm -rf "$TEST_WS"; }
      Before 'setup_empty'
      After 'cleanup_empty'

      It "returns 3 when no stack detected"
        When call test.run "$TEST_WS"
        The status should equal 3
        The stderr should include "cannot detect stack"
      End
    End

    Describe "with failing test command"
      setup_fail() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        printf '{"name":"test"}\n' > "${TEST_WS}/package.json"
        mock.create_exit "npx" 1
        mock.activate
      }
      cleanup_fail() {
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_fail'
      After 'cleanup_fail'

      It "returns 10 when tests fail"
        When call test.run "$TEST_WS"
        The status should equal 10
        The stderr should include "tests failed"
      End
    End

    Describe "Node.js without npx"
      setup_no_npx() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_npm.log"
        printf '{"name":"test","scripts":{"test":"echo ok"}}\n' > "${TEST_WS}/package.json"
        mock.create_logging "npm" "$MOCK_LOG"
        ln -sf "$(command -v bash)" "${MOCK_BIN}/bash"
        mock.isolate
      }
      cleanup_no_npx() {
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_no_npx'
      After 'cleanup_no_npx'

      It "falls back to npm test when npx is not available"
        When call test.run "$TEST_WS"
        The status should be success
        The stderr should include "npm test"
      End
    End
  End

  Describe "test.publish_report"
    setup() {
      REPORT_FILE="$(mktemp)"
      printf '<testsuites><testsuite tests="1"/></testsuites>\n' > "$REPORT_FILE"
    }
    cleanup() { rm -rf "$REPORT_FILE"; }
    Before 'setup'
    After 'cleanup'

    It "copies report to log directory"
      invoke_copy() {
        test.publish_report "$REPORT_FILE" 2>/dev/null || return 1
        [[ -f "${BRIK_LOG_DIR}/reports/$(basename "$REPORT_FILE")" ]]
      }
      When call invoke_copy
      The status should be success
    End

    It "returns 6 for missing report file"
      When call test.publish_report "/nonexistent/report.xml"
      The status should equal 6
      The stderr should include "report file not found"
    End

    It "accepts --format option"
      When call test.publish_report "$REPORT_FILE" --format tap
      The status should be success
      The stderr should include "format: tap"
    End

    It "returns 2 for unknown option"
      When call test.publish_report "$REPORT_FILE" --badopt
      The status should equal 2
      The stderr should include "unknown option"
    End
  End
End
