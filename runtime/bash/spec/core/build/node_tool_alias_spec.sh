Describe "build/node.sh - --tool alias for --package-manager"
  Include "$BRIK_RUNTIME_LIB/logging.sh"
  Include "$BRIK_RUNTIME_LIB/tools.sh"
  Include "$BRIK_CORE_LIB/build/node.sh"
  Include "$BRIK_HOME/runtime/bash/spec/support/mock_helper.sh"

  Describe "build.node.run with --tool"
    setup_tool_alias() {
      mock.setup
      TEST_WS="$(mktemp -d)"
      MOCK_LOG="${TEST_WS}/mock_yarn.log"
      printf '{"name":"test","version":"1.0.0","scripts":{"build":"echo ok"}}\n' > "${TEST_WS}/package.json"
      mkdir -p "${TEST_WS}/node_modules"
      mock.create_logging "yarn" "$MOCK_LOG"
      mock.create_exit "node" 0
      mock.activate
    }
    cleanup_tool_alias() {
      mock.cleanup
      rm -rf "$TEST_WS"
    }
    Before 'setup_tool_alias'
    After 'cleanup_tool_alias'

    It "accepts --tool as alias for --package-manager"
      invoke_tool_alias() {
        build.node.run "$TEST_WS" --tool yarn 2>/dev/null || return 1
        grep -q "^yarn " "$MOCK_LOG"
      }
      When call invoke_tool_alias
      The status should be success
    End
  End

  Describe "build.node.install with --tool"
    setup_install_tool() {
      mock.setup
      TEST_WS="$(mktemp -d)"
      MOCK_LOG="${TEST_WS}/mock_pnpm.log"
      printf '{"name":"test","version":"1.0.0"}\n' > "${TEST_WS}/package.json"
      mock.create_logging "pnpm" "$MOCK_LOG"
      mock.activate
    }
    cleanup_install_tool() {
      mock.cleanup
      rm -rf "$TEST_WS"
    }
    Before 'setup_install_tool'
    After 'cleanup_install_tool'

    It "accepts --tool as alias for --package-manager in install"
      invoke_install_tool() {
        build.node.install "$TEST_WS" --tool pnpm 2>/dev/null || return 1
        grep -q "^pnpm " "$MOCK_LOG"
      }
      When call invoke_install_tool
      The status should be success
    End
  End
End
