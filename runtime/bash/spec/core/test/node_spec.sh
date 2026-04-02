Describe "test/node.sh"
  Include "$BRIK_RUNTIME_LIB/logging.sh"
  Include "$BRIK_RUNTIME_LIB/tools.sh"
  Include "$BRIK_CORE_LIB/test/node.sh"

  Describe "test.node.cmd"
    It "returns npx jest for jest framework"
      When call test.node.cmd "jest" "/workspace" ""
      The output should equal "npx jest"
    End

    It "adds jest-junit reporters when report_dir is provided"
      When call test.node.cmd "jest" "/workspace" "/reports"
      The output should equal "npx jest --reporters=default --reporters=jest-junit"
    End

    It "returns npm test for npm framework"
      When call test.node.cmd "npm" "/workspace" ""
      The output should equal "npm test"
    End

    It "returns 7 for unsupported framework"
      When call test.node.cmd "unknown" "/workspace" ""
      The status should equal 7
      The stderr should include "unsupported Node.js test framework"
    End
  End

  Describe "test.node.run_cmd"
    Describe "with scripts.test in package.json"
      setup_with_test_script() {
        TEST_WS="$(mktemp -d)"
        printf '{"name":"test","scripts":{"test":"echo ok"}}\n' > "${TEST_WS}/package.json"
      }
      cleanup_with_test_script() { rm -rf "$TEST_WS"; }
      Before 'setup_with_test_script'
      After 'cleanup_with_test_script'

      It "prefers npm test when scripts.test exists"
        When call test.node.run_cmd "$TEST_WS" ""
        The output should equal "npm test"
      End
    End

    Describe "without scripts.test and with npx"
      setup_no_test_script() {
        TEST_WS="$(mktemp -d)"
        printf '{"name":"test"}\n' > "${TEST_WS}/package.json"
        MOCK_BIN="$(mktemp -d)"
        cat > "${MOCK_BIN}/npx" << 'EOF'
#!/usr/bin/env bash
exit 0
EOF
        chmod +x "${MOCK_BIN}/npx"
        ORIG_PATH="$PATH"
        export PATH="${MOCK_BIN}:${PATH}"
      }
      cleanup_no_test_script() {
        export PATH="$ORIG_PATH"
        rm -rf "$TEST_WS" "$MOCK_BIN"
      }
      Before 'setup_no_test_script'
      After 'cleanup_no_test_script'

      It "falls back to npx jest when no scripts.test"
        When call test.node.run_cmd "$TEST_WS" ""
        The output should equal "npx jest"
      End

      It "includes report flags when report_dir is provided"
        When call test.node.run_cmd "$TEST_WS" "/reports"
        The output should equal "npx jest --reporters=default --reporters=jest-junit"
      End
    End

    Describe "without scripts.test and without npx"
      setup_no_npx() {
        TEST_WS="$(mktemp -d)"
        printf '{"name":"test"}\n' > "${TEST_WS}/package.json"
        MOCK_BIN="$(mktemp -d)"
        ln -sf "$(command -v bash)" "${MOCK_BIN}/bash"
        ORIG_PATH="$PATH"
        export PATH="${MOCK_BIN}"
      }
      cleanup_no_npx() {
        export PATH="$ORIG_PATH"
        rm -rf "$TEST_WS" "$MOCK_BIN"
      }
      Before 'setup_no_npx'
      After 'cleanup_no_npx'

      It "falls back to npm test when npx is not available"
        When call test.node.run_cmd "$TEST_WS" ""
        The output should equal "npm test"
      End
    End
  End
End
