Describe "build/node.sh"
  Include "$BRIK_RUNTIME_LIB/logging.sh"
  Include "$BRIK_RUNTIME_LIB/tools.sh"
  Include "$BRIK_CORE_LIB/build/node.sh"
  Include "$BRIK_HOME/runtime/bash/spec/support/mock_helper.sh"

  Describe "_build.node._detect_pm"
    It "detects yarn from yarn.lock"
      When call _build.node._detect_pm "$WORKSPACES/node-yarn"
      The output should equal "yarn"
    End

    It "detects pnpm from pnpm-lock.yaml"
      When call _build.node._detect_pm "$WORKSPACES/node-pnpm"
      The output should equal "pnpm"
    End

    It "defaults to npm"
      When call _build.node._detect_pm "$WORKSPACES/node-simple"
      The output should equal "npm"
    End
  End

  Describe "build.node.install"
    It "returns 6 if package.json is missing"
      When call build.node.install "$WORKSPACES/unknown"
      The status should equal 6
      The stderr should be present
    End

    It "returns 2 for unknown option"
      When call build.node.install "$WORKSPACES/node-simple" --badopt foo
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
          build.node.install "$TEST_WS" 2>/dev/null
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
          build.node.install "$TEST_WS" 2>/dev/null
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
          build.node.install "$TEST_WS" --package-manager yarn 2>/dev/null
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
        When call build.node.install "$TEST_WS"
        The status should equal 5
        The stderr should include "dependency installation failed"
      End
    End
  End

  Describe "build.node.run"
    It "returns 6 if package.json is missing"
      When call build.node.run "$WORKSPACES/unknown"
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
        When call build.node.run "$TEST_WS"
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
        When call build.node.run "$TEST_WS"
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
        When call build.node.run "$TEST_WS"
        The status should equal 5
        The stderr should include "build failed"
      End
    End
  End
End
