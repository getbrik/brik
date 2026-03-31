Describe "test.sh"
  Include "$BRIK_RUNTIME_LIB/logging.sh"
  Include "$BRIK_RUNTIME_LIB/tools.sh"
  Include "$BRIK_CORE_LIB/test.sh"

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
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_npx.log"
        printf '{"name":"test","scripts":{"test":"echo ok"}}\n' > "${TEST_WS}/package.json"
        MOCK_BIN="$(mktemp -d)"
        # Mock npx that records its arguments
        cat > "${MOCK_BIN}/npx" << MOCKEOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$MOCK_LOG"
exit 0
MOCKEOF
        chmod +x "${MOCK_BIN}/npx"
        ORIG_PATH="$PATH"
        export PATH="${MOCK_BIN}:${PATH}"
      }
      cleanup_node() {
        export PATH="$ORIG_PATH"
        rm -rf "$TEST_WS" "$MOCK_BIN"
      }
      Before 'setup_node'
      After 'cleanup_node'

      It "detects Node.js and runs npx jest"
        verify_npx_jest() {
          test.run "$TEST_WS" 2>/dev/null
          grep -q "jest" "$MOCK_LOG"
        }
        When call verify_npx_jest
        The status should be success
      End

      It "logs the suite being run"
        When call test.run "$TEST_WS" --suite integration
        The status should be success
        The stderr should include "running integration tests"
      End

      It "passes --reporters=jest-junit when --report-dir is set"
        verify_reporters() {
          local rdir="${TEST_WS}/reports"
          test.run "$TEST_WS" --report-dir "$rdir" 2>/dev/null
          [[ -d "$rdir" ]] || return 1
          grep -q "jest-junit" "$MOCK_LOG"
        }
        When call verify_reporters
        The status should be success
      End
    End

    Describe "with Python workspace"
      setup_py() {
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_python.log"
        printf '[project]\nname = "test"\n' > "${TEST_WS}/pyproject.toml"
        MOCK_BIN="$(mktemp -d)"
        cat > "${MOCK_BIN}/python" << MOCKEOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$MOCK_LOG"
exit 0
MOCKEOF
        chmod +x "${MOCK_BIN}/python"
        ORIG_PATH="$PATH"
        export PATH="${MOCK_BIN}:${PATH}"
      }
      cleanup_py() {
        export PATH="$ORIG_PATH"
        rm -rf "$TEST_WS" "$MOCK_BIN"
      }
      Before 'setup_py'
      After 'cleanup_py'

      It "detects Python and runs pytest"
        verify_pytest() {
          test.run "$TEST_WS" 2>/dev/null
          grep -q "\-m pytest" "$MOCK_LOG"
        }
        When call verify_pytest
        The status should be success
      End

      It "passes --junitxml when --report-dir is set"
        verify_junitxml() {
          test.run "$TEST_WS" --report-dir "${TEST_WS}/reports" 2>/dev/null
          grep -q "junitxml" "$MOCK_LOG"
        }
        When call verify_junitxml
        The status should be success
      End
    End

    Describe "with Java workspace"
      setup_java() {
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_mvn.log"
        printf '<project/>\n' > "${TEST_WS}/pom.xml"
        MOCK_BIN="$(mktemp -d)"
        cat > "${MOCK_BIN}/mvn" << MOCKEOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$MOCK_LOG"
exit 0
MOCKEOF
        chmod +x "${MOCK_BIN}/mvn"
        ORIG_PATH="$PATH"
        export PATH="${MOCK_BIN}:${PATH}"
      }
      cleanup_java() {
        export PATH="$ORIG_PATH"
        rm -rf "$TEST_WS" "$MOCK_BIN"
      }
      Before 'setup_java'
      After 'cleanup_java'

      It "detects Java and invokes mvn test"
        verify_mvn() {
          test.run "$TEST_WS" 2>/dev/null
          grep -q "test" "$MOCK_LOG"
        }
        When call verify_mvn
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

      It "returns 3 when no framework detected"
        When call test.run "$TEST_WS"
        The status should equal 3
        The stderr should include "cannot detect test framework"
      End
    End

    Describe "with failing test command"
      setup_fail() {
        TEST_WS="$(mktemp -d)"
        printf '{"name":"test"}\n' > "${TEST_WS}/package.json"
        MOCK_BIN="$(mktemp -d)"
        cat > "${MOCK_BIN}/npx" << 'EOF'
#!/usr/bin/env bash
exit 1
EOF
        chmod +x "${MOCK_BIN}/npx"
        ORIG_PATH="$PATH"
        export PATH="${MOCK_BIN}:${PATH}"
      }
      cleanup_fail() {
        export PATH="$ORIG_PATH"
        rm -rf "$TEST_WS" "$MOCK_BIN"
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
        TEST_WS="$(mktemp -d)"
        printf '{"name":"test","scripts":{"test":"echo ok"}}\n' > "${TEST_WS}/package.json"
        MOCK_BIN="$(mktemp -d)"
        # Only provide npm, no npx
        cat > "${MOCK_BIN}/npm" << 'EOF'
#!/usr/bin/env bash
exit 0
EOF
        chmod +x "${MOCK_BIN}/npm"
        ORIG_PATH="$PATH"
        # Put mock bin first, keep /usr/bin and /bin for shell basics but exclude npx
        export PATH="${MOCK_BIN}:/usr/bin:/bin"
      }
      cleanup_no_npx() {
        export PATH="$ORIG_PATH"
        rm -rf "$TEST_WS" "$MOCK_BIN"
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
      export BRIK_LOG_DIR
      BRIK_LOG_DIR="$(mktemp -d)"
      REPORT_FILE="$(mktemp)"
      printf '<testsuites><testsuite tests="1"/></testsuites>\n' > "$REPORT_FILE"
    }
    cleanup() { rm -rf "$BRIK_LOG_DIR" "$REPORT_FILE"; }
    Before 'setup'
    After 'cleanup'

    It "copies report to log directory"
      verify_copy() {
        test.publish_report "$REPORT_FILE" 2>/dev/null
        [[ -f "${BRIK_LOG_DIR}/reports/$(basename "$REPORT_FILE")" ]]
      }
      When call verify_copy
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
