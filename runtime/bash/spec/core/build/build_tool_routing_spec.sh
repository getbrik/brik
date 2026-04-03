Describe "build.sh - BRIK_BUILD_TOOL routing"
  Include "$BRIK_RUNTIME_LIB/logging.sh"
  Include "$BRIK_RUNTIME_LIB/tools.sh"
  Include "$BRIK_CORE_LIB/_loader.sh"
  Include "$BRIK_CORE_LIB/build.sh"

  Describe "build.run passes BRIK_BUILD_TOOL to stack module"
    Describe "with node stack and --tool from BRIK_BUILD_TOOL"
      setup_node_tool() {
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_tool.log"
        printf '{"name":"test","version":"1.0.0","scripts":{"build":"echo ok"}}\n' > "${TEST_WS}/package.json"
        mkdir -p "${TEST_WS}/node_modules"
        MOCK_BIN="$(mktemp -d)"
        # Mock yarn to capture calls
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
        export BRIK_BUILD_TOOL="yarn"
      }
      cleanup_node_tool() {
        export PATH="$ORIG_PATH"
        unset BRIK_BUILD_TOOL
        rm -rf "$TEST_WS" "$MOCK_BIN"
      }
      Before 'setup_node_tool'
      After 'cleanup_node_tool'

      It "uses yarn when BRIK_BUILD_TOOL=yarn"
        invoke_tool_check() {
          build.run "$TEST_WS" 2>/dev/null || return 1
          grep -q "^yarn " "$MOCK_LOG"
        }
        When call invoke_tool_check
        The status should be success
      End
    End

    Describe "with python stack and --tool from BRIK_BUILD_TOOL"
      setup_python_tool() {
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_uv.log"
        printf '[project]\nname = "test"\n' > "${TEST_WS}/pyproject.toml"
        MOCK_BIN="$(mktemp -d)"
        cat > "${MOCK_BIN}/uv" << MOCKEOF
#!/usr/bin/env bash
printf 'uv %s\n' "\$*" >> "$MOCK_LOG"
exit 0
MOCKEOF
        chmod +x "${MOCK_BIN}/uv"
        ORIG_PATH="$PATH"
        export PATH="${MOCK_BIN}:${PATH}"
        export BRIK_BUILD_TOOL="uv"
      }
      cleanup_python_tool() {
        export PATH="$ORIG_PATH"
        unset BRIK_BUILD_TOOL
        rm -rf "$TEST_WS" "$MOCK_BIN"
      }
      Before 'setup_python_tool'
      After 'cleanup_python_tool'

      It "uses uv when BRIK_BUILD_TOOL=uv"
        invoke_uv_check() {
          build.run "$TEST_WS" 2>/dev/null || return 1
          grep -q "^uv " "$MOCK_LOG"
        }
        When call invoke_uv_check
        The status should be success
      End
    End
  End

  Describe "BRIK_BUILD_COMMAND takes priority over BRIK_BUILD_TOOL"
    setup_cmd_priority() {
      TEST_WS="$(mktemp -d)"
      printf '{"name":"test","version":"1.0.0"}\n' > "${TEST_WS}/package.json"
      mkdir -p "${TEST_WS}/node_modules"
      MOCK_BIN="$(mktemp -d)"
      cat > "${MOCK_BIN}/node" << 'EOF'
#!/usr/bin/env bash
exit 0
EOF
      chmod +x "${MOCK_BIN}/node"
      cat > "${MOCK_BIN}/npm" << 'EOF'
#!/usr/bin/env bash
exit 0
EOF
      chmod +x "${MOCK_BIN}/npm"
      ORIG_PATH="$PATH"
      export PATH="${MOCK_BIN}:${PATH}"
      export BRIK_BUILD_COMMAND="echo custom-build"
      export BRIK_BUILD_TOOL="yarn"
    }
    cleanup_cmd_priority() {
      export PATH="$ORIG_PATH"
      unset BRIK_BUILD_COMMAND BRIK_BUILD_TOOL
      rm -rf "$TEST_WS" "$MOCK_BIN"
    }
    Before 'setup_cmd_priority'
    After 'cleanup_cmd_priority'

    It "uses BRIK_BUILD_COMMAND over BRIK_BUILD_TOOL"
      When call build.run "$TEST_WS"
      The status should be success
      The stdout should include "custom-build"
      The stderr should include "using custom build command"
    End
  End

  Describe "BRIK_BUILD_TOOL=auto falls through to stack default"
    setup_auto_tool() {
      TEST_WS="$(mktemp -d)"
      printf '{"name":"test","version":"1.0.0","scripts":{"build":"echo ok"}}\n' > "${TEST_WS}/package.json"
      mkdir -p "${TEST_WS}/node_modules"
      MOCK_BIN="$(mktemp -d)"
      cat > "${MOCK_BIN}/npm" << 'EOF'
#!/usr/bin/env bash
printf "mock-npm %s\n" "$*"
exit 0
EOF
      chmod +x "${MOCK_BIN}/npm"
      cat > "${MOCK_BIN}/node" << 'EOF'
#!/usr/bin/env bash
exit 0
EOF
      chmod +x "${MOCK_BIN}/node"
      ORIG_PATH="$PATH"
      export PATH="${MOCK_BIN}:${PATH}"
      export BRIK_BUILD_TOOL="auto"
    }
    cleanup_auto_tool() {
      export PATH="$ORIG_PATH"
      unset BRIK_BUILD_TOOL
      rm -rf "$TEST_WS" "$MOCK_BIN"
    }
    Before 'setup_auto_tool'
    After 'cleanup_auto_tool'

    It "ignores 'auto' and uses stack detection"
      When call build.run "$TEST_WS"
      The status should be success
      The stdout should be present
      The stderr should include "build completed successfully"
    End
  End
End
