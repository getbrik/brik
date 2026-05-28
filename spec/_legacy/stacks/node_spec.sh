Describe "build/node.sh"
  Include "$BRIK_PIPELINE_LIB/logging.sh"
  Include "$BRIK_PIPELINE_LIB/tools.sh"
  Include "$BRIK_STACKS_LIB/node.sh"
  Include "$BRIK_HOME/spec/support/mock_helper.sh"

  Describe "_stacks.node._detect_pm"
    It "detects yarn from yarn.lock"
      When call _stacks.node._detect_pm "$WORKSPACES/node-yarn"
      The output should equal "yarn"
    End

    It "detects pnpm from pnpm-lock.yaml"
      When call _stacks.node._detect_pm "$WORKSPACES/node-pnpm"
      The output should equal "pnpm"
    End

    It "defaults to npm"
      When call _stacks.node._detect_pm "$WORKSPACES/node-simple"
      The output should equal "npm"
    End
  End

  Describe "stacks.node.install"
    It "returns 6 if package.json is missing"
      When call stacks.node.install "$WORKSPACES/unknown"
      The status should equal 6
      The stderr should be present
    End

    It "returns 2 for unknown option"
      When call stacks.node.install "$WORKSPACES/node-simple" --badopt foo
      The status should equal 2
      The stderr should include "unknown option"
    End

    Describe "with mock npm and package-lock.json"
      setup_npm() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_npm.log"
        printf '{"name":"test","version":"1.0.0"}\n' > "${TEST_WS}/package.json"
        printf '{"lockfileVersion":2}\n' > "${TEST_WS}/package-lock.json"
        mock.create_script "npm" "printf '%s\\n' \"\$*\" >> \"$MOCK_LOG\""
        mock.activate
      }
      cleanup_npm() {
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_npm'
      After 'cleanup_npm'

      It "runs npm ci with cache flags when package-lock.json exists"
        verify_ci() {
          stacks.node.install "$TEST_WS" 2>/dev/null
          grep -q "ci --cache .npm --prefer-offline" "$MOCK_LOG"
        }
        When call verify_ci
        The status should be success
      End
    End

    Describe "with mock npm and no lock file"
      setup_npm_no_lock() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_npm.log"
        printf '{"name":"test","version":"1.0.0"}\n' > "${TEST_WS}/package.json"
        mock.create_script "npm" "printf '%s\\n' \"\$*\" >> \"$MOCK_LOG\""
        mock.activate
      }
      cleanup_npm_no_lock() {
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_npm_no_lock'
      After 'cleanup_npm_no_lock'

      It "runs npm install when no lock file"
        verify_install() {
          stacks.node.install "$TEST_WS" 2>/dev/null
          grep -qx "install" "$MOCK_LOG"
        }
        When call verify_install
        The status should be success
      End
    End

    Describe "with mock yarn"
      setup_yarn() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_yarn.log"
        printf '{"name":"test","version":"1.0.0"}\n' > "${TEST_WS}/package.json"
        printf '# yarn lockfile v1\n' > "${TEST_WS}/yarn.lock"
        mock.create_script "yarn" "printf '%s\\n' \"\$*\" >> \"$MOCK_LOG\""
        mock.activate
      }
      cleanup_yarn() {
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_yarn'
      After 'cleanup_yarn'

      It "runs yarn install --frozen-lockfile"
        verify_yarn() {
          stacks.node.install "$TEST_WS" --package-manager yarn 2>/dev/null
          grep -q "frozen-lockfile" "$MOCK_LOG"
        }
        When call verify_yarn
        The status should be success
      End
    End

    Describe "with failing npm"
      setup_fail() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        printf '{"name":"test","version":"1.0.0"}\n' > "${TEST_WS}/package.json"
        mock.create_exit "npm" 1
        mock.activate
      }
      cleanup_fail() {
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_fail'
      After 'cleanup_fail'

      It "returns 5 when install fails"
        When call stacks.node.install "$TEST_WS"
        The status should equal 5
        The stderr should include "dependency installation failed"
      End
    End
  End

  Describe "stacks.node.build"
    It "returns 6 if package.json is missing"
      When call stacks.node.build "$WORKSPACES/unknown"
      The status should equal 6
      The stderr should include "required file not found"
    End

    Describe "with mock npm and node_modules present"
      setup_run() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        printf '{"name":"test","version":"1.0.0","scripts":{"build":"echo ok"}}\n' > "${TEST_WS}/package.json"
        mkdir -p "${TEST_WS}/node_modules"
        mock.create_script "npm" 'printf "mock-npm %s\n" "$*"
exit 0'
        mock.create_exit "node" 0
        mock.activate
      }
      cleanup_run() {
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_run'
      After 'cleanup_run'

      It "runs build successfully"
        When call stacks.node.build "$TEST_WS"
        The status should be success
        The stdout should be present
        The stderr should include "build completed successfully"
      End
    End

    Describe "with mock npm, no node_modules (auto-install)"
      setup_auto() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        printf '{"name":"test","version":"1.0.0","scripts":{"build":"echo ok"}}\n' > "${TEST_WS}/package.json"
        mock.create_script "npm" 'if [ "$1" = "install" ] || [ "$1" = "ci" ]; then
  mkdir -p node_modules
fi
printf "mock-npm %s\n" "$*"
exit 0'
        mock.create_exit "node" 0
        mock.activate
      }
      cleanup_auto() {
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_auto'
      After 'cleanup_auto'

      It "auto-installs dependencies then builds"
        When call stacks.node.build "$TEST_WS"
        The status should be success
        The stdout should be present
        The stderr should include "installing dependencies"
        The stderr should include "build completed"
      End
    End

    Describe "with failing build"
      setup_fail_build() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        printf '{"name":"test","version":"1.0.0","scripts":{"build":"exit 1"}}\n' > "${TEST_WS}/package.json"
        mkdir -p "${TEST_WS}/node_modules"
        mock.create_script "npm" 'if [ "$1" = "run" ]; then exit 1; fi
exit 0'
        mock.create_exit "node" 0
        mock.activate
      }
      cleanup_fail_build() {
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_fail_build'
      After 'cleanup_fail_build'

      It "returns 5 when build fails"
        When call stacks.node.build "$TEST_WS"
        The status should equal 5
        The stderr should include "build failed"
      End
    End
  End
End
Describe "test/node.sh"
  Include "$BRIK_PIPELINE_LIB/logging.sh"
  Include "$BRIK_PIPELINE_LIB/tools.sh"
  Include "$BRIK_STACKS_LIB/node.sh"
  Include "$BRIK_HOME/spec/support/mock_helper.sh"

  Describe "stacks.node.test_cmd"
    It "returns npx jest for jest framework"
      When call stacks.node.test_cmd "jest" "/workspace" ""
      The output should equal "npx jest"
    End

    It "adds jest-junit reporters when report_dir is provided"
      When call stacks.node.test_cmd "jest" "/workspace" "/reports"
      The output should equal "npx jest --reporters=default --reporters=jest-junit"
    End

    It "returns npx vitest run for vitest framework"
      When call stacks.node.test_cmd "vitest" "/workspace" ""
      The output should equal "npx vitest run"
    End

    It "returns npm test for npm framework"
      When call stacks.node.test_cmd "npm" "/workspace" ""
      The output should equal "npm test"
    End

    It "returns 7 for unsupported framework"
      When call stacks.node.test_cmd "unknown" "/workspace" ""
      The status should equal 7
      The stderr should include "unsupported Node.js test framework"
    End

    Describe "with BRIK_TEST_REPORTS_ENABLED=true"
      setup_reports_on() { export BRIK_TEST_REPORTS_ENABLED=true; }
      cleanup_reports_on() {
        unset BRIK_TEST_REPORTS_ENABLED BRIK_TEST_COVERAGE_DIR BRIK_TEST_JUNIT_PATH
      }
      Before 'setup_reports_on'
      After 'cleanup_reports_on'

      It "injects coverage and jest-junit flags for jest"
        When call stacks.node.test_cmd "jest" "/workspace" ""
        The output should include "JEST_JUNIT_OUTPUT_FILE='brik-artifacts/test/junit.xml'"
        The output should include "npx jest"
        The output should include "--coverage"
        The output should include "--coverageDirectory='brik-artifacts/test/coverage'"
        The output should include "--coverageReporters=cobertura"
        The output should include "--reporters=default"
        The output should include "--reporters=jest-junit"
      End

      It "renames cobertura-coverage.xml to coverage.xml post-test"
        When call stacks.node.test_cmd "jest" "/workspace" ""
        The output should include "cp -f 'brik-artifacts/test/coverage/cobertura-coverage.xml' 'brik-artifacts/test/coverage/coverage.xml'"
        The output should include "exit \$_rc"
      End

      It "honours BRIK_TEST_COVERAGE_DIR override"
        export BRIK_TEST_COVERAGE_DIR="custom/cov"
        When call stacks.node.test_cmd "jest" "/workspace" ""
        The output should include "--coverageDirectory='custom/cov'"
      End

      It "honours BRIK_TEST_JUNIT_PATH override"
        export BRIK_TEST_JUNIT_PATH="custom/junit.xml"
        When call stacks.node.test_cmd "jest" "/workspace" ""
        The output should include "JEST_JUNIT_OUTPUT_FILE='custom/junit.xml'"
      End

      It "ignores legacy report_dir argument when reports.enabled is true"
        When call stacks.node.test_cmd "jest" "/workspace" "/legacy/reports"
        The output should include "--coverage"
        The output should include "JEST_JUNIT_OUTPUT_FILE='brik-artifacts/test/junit.xml'"
      End

      It "leaves npm framework untouched"
        When call stacks.node.test_cmd "npm" "/workspace" ""
        The output should equal "npm test"
      End

      It "injects coverage and junit flags for vitest with reports enabled"
        When call stacks.node.test_cmd "vitest" "/workspace" ""
        The output should include "npx vitest run"
        The output should include "--reporter=junit"
        The output should include "--coverage.reporter=cobertura"
        The output should include "cp -f"
        The output should include "exit \$_rc"
      End
    End
  End

  Describe "stacks.node.test"
    Describe "with scripts.test in package.json"
      setup_with_test_script() {
        TEST_WS="$(mktemp -d)"
        printf '{"name":"test","scripts":{"test":"echo ok"}}\n' > "${TEST_WS}/package.json"
      }
      cleanup_with_test_script() { rm -rf "$TEST_WS"; }
      Before 'setup_with_test_script'
      After 'cleanup_with_test_script'

      It "prefers npm test when scripts.test exists"
        When call stacks.node.test "$TEST_WS" ""
        The output should equal "npm test"
      End
    End

    Describe "without scripts.test and with npx"
      setup_no_test_script() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        printf '{"name":"test"}\n' > "${TEST_WS}/package.json"
        mock.create_exit "npx" 0
        mock.activate
      }
      cleanup_no_test_script() {
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_no_test_script'
      After 'cleanup_no_test_script'

      It "falls back to npx jest when no scripts.test"
        When call stacks.node.test "$TEST_WS" ""
        The output should equal "npx jest"
      End

      It "includes report flags when report_dir is provided"
        When call stacks.node.test "$TEST_WS" "/reports"
        The output should equal "npx jest --reporters=default --reporters=jest-junit"
      End
    End

    Describe "without scripts.test and without npx"
      setup_no_npx() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        printf '{"name":"test"}\n' > "${TEST_WS}/package.json"
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
        When call stacks.node.test "$TEST_WS" ""
        The output should equal "npm test"
      End
    End
  End
End
