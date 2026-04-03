Describe "build/node.sh - --tool alias for --package-manager"
  Include "$BRIK_RUNTIME_LIB/logging.sh"
  Include "$BRIK_RUNTIME_LIB/tools.sh"
  Include "$BRIK_CORE_LIB/build/node.sh"

  Describe "build.node.run with --tool"
    setup_tool_alias() {
      TEST_WS="$(mktemp -d)"
      MOCK_LOG="${TEST_WS}/mock_yarn.log"
      printf '{"name":"test","version":"1.0.0","scripts":{"build":"echo ok"}}\n' > "${TEST_WS}/package.json"
      mkdir -p "${TEST_WS}/node_modules"
      MOCK_BIN="$(mktemp -d)"
      cat > "${MOCK_BIN}/yarn" << MOCKEOF
#!/usr/bin/env bash
printf 'yarn %s\n' "\$*" >> "$MOCK_LOG"
exit 0
MOCKEOF
      chmod +x "${MOCK_BIN}/yarn"
      cat > "${MOCK_BIN}/node" << 'EOF'
#!/usr/bin/env bash
exit 0
EOF
      chmod +x "${MOCK_BIN}/node"
      ORIG_PATH="$PATH"
      export PATH="${MOCK_BIN}:${PATH}"
    }
    cleanup_tool_alias() {
      export PATH="$ORIG_PATH"
      rm -rf "$TEST_WS" "$MOCK_BIN"
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
      TEST_WS="$(mktemp -d)"
      MOCK_LOG="${TEST_WS}/mock_pnpm.log"
      printf '{"name":"test","version":"1.0.0"}\n' > "${TEST_WS}/package.json"
      MOCK_BIN="$(mktemp -d)"
      cat > "${MOCK_BIN}/pnpm" << MOCKEOF
#!/usr/bin/env bash
printf 'pnpm %s\n' "\$*" >> "$MOCK_LOG"
exit 0
MOCKEOF
      chmod +x "${MOCK_BIN}/pnpm"
      ORIG_PATH="$PATH"
      export PATH="${MOCK_BIN}:${PATH}"
    }
    cleanup_install_tool() {
      export PATH="$ORIG_PATH"
      rm -rf "$TEST_WS" "$MOCK_BIN"
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
