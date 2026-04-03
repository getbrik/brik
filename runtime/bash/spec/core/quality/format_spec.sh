Describe "quality/format.sh"
  Include "$BRIK_RUNTIME_LIB/logging.sh"
  Include "$BRIK_RUNTIME_LIB/tools.sh"
  Include "$BRIK_CORE_LIB/quality/format.sh"

  Describe "quality.format.run"
    It "returns 6 for nonexistent workspace"
      When call quality.format.run "/nonexistent/workspace"
      The status should equal 6
      The stderr should include "required directory not found"
    End

    Describe "unknown option"
      setup_ws() { TEST_WS="$(mktemp -d)"; }
      cleanup_ws() { rm -rf "$TEST_WS"; }
      Before 'setup_ws'
      After 'cleanup_ws'

      It "returns 2 for unknown option"
        When call quality.format.run "$TEST_WS" --badopt
        The status should equal 2
        The stderr should include "unknown option"
      End
    End

    Describe "Tier 1: BRIK_QUALITY_FORMAT_COMMAND override"
      setup_cmd_override() {
        TEST_WS="$(mktemp -d)"
        MOCK_BIN="$(mktemp -d)"
        cat > "${MOCK_BIN}/prettier" << 'EOF'
#!/usr/bin/env bash
printf "prettier %s\n" "$*"
exit 0
EOF
        chmod +x "${MOCK_BIN}/prettier"
        ORIG_PATH="$PATH"
        export PATH="${MOCK_BIN}:${PATH}"
        export BRIK_QUALITY_FORMAT_COMMAND="prettier --check ."
      }
      cleanup_cmd_override() {
        export PATH="$ORIG_PATH"
        unset BRIK_QUALITY_FORMAT_COMMAND
        rm -rf "$TEST_WS" "$MOCK_BIN"
      }
      Before 'setup_cmd_override'
      After 'cleanup_cmd_override'

      It "uses BRIK_QUALITY_FORMAT_COMMAND as Tier 1 override"
        When call quality.format.run "$TEST_WS"
        The status should be success
        The stdout should be present
        The stderr should include "format check passed"
      End
    End

    Describe "Tier 2: BRIK_QUALITY_FORMAT_TOOL selection"
      setup_tool_selection() {
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock.log"
        printf '{"name":"test"}\n' > "${TEST_WS}/package.json"
        MOCK_BIN="$(mktemp -d)"
        cat > "${MOCK_BIN}/npx" << MOCKEOF
#!/usr/bin/env bash
printf 'npx %s\n' "\$*" >> "$MOCK_LOG"
exit 0
MOCKEOF
        chmod +x "${MOCK_BIN}/npx"
        ORIG_PATH="$PATH"
        export PATH="${MOCK_BIN}:${PATH}"
        export BRIK_QUALITY_FORMAT_TOOL="prettier"
      }
      cleanup_tool_selection() {
        export PATH="$ORIG_PATH"
        unset BRIK_QUALITY_FORMAT_TOOL
        rm -rf "$TEST_WS" "$MOCK_BIN"
      }
      Before 'setup_tool_selection'
      After 'cleanup_tool_selection'

      It "uses prettier when BRIK_QUALITY_FORMAT_TOOL=prettier"
        invoke_check() {
          quality.format.run "$TEST_WS" 2>/dev/null || return 1
          grep -q "prettier" "$MOCK_LOG"
        }
        When call invoke_check
        The status should be success
      End
    End

    Describe "Tier 3: auto-detect for Node.js"
      setup_node_fmt() {
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock.log"
        printf '{"name":"test"}\n' > "${TEST_WS}/package.json"
        MOCK_BIN="$(mktemp -d)"
        cat > "${MOCK_BIN}/npx" << MOCKEOF
#!/usr/bin/env bash
printf 'npx %s\n' "\$*" >> "$MOCK_LOG"
exit 0
MOCKEOF
        chmod +x "${MOCK_BIN}/npx"
        ORIG_PATH="$PATH"
        export PATH="${MOCK_BIN}:${PATH}"
      }
      cleanup_node_fmt() {
        export PATH="$ORIG_PATH"
        rm -rf "$TEST_WS" "$MOCK_BIN"
      }
      Before 'setup_node_fmt'
      After 'cleanup_node_fmt'

      It "auto-detects prettier for Node.js"
        invoke_auto() {
          quality.format.run "$TEST_WS" 2>/dev/null || return 1
          grep -q "prettier" "$MOCK_LOG"
        }
        When call invoke_auto
        The status should be success
      End
    End

    Describe "Tier 3: auto-detect for Python"
      setup_py_fmt() {
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock.log"
        printf '[project]\nname = "test"\n' > "${TEST_WS}/pyproject.toml"
        MOCK_BIN="$(mktemp -d)"
        cat > "${MOCK_BIN}/ruff" << MOCKEOF
#!/usr/bin/env bash
printf 'ruff %s\n' "\$*" >> "$MOCK_LOG"
exit 0
MOCKEOF
        chmod +x "${MOCK_BIN}/ruff"
        ORIG_PATH="$PATH"
        export PATH="${MOCK_BIN}:${PATH}"
      }
      cleanup_py_fmt() {
        export PATH="$ORIG_PATH"
        rm -rf "$TEST_WS" "$MOCK_BIN"
      }
      Before 'setup_py_fmt'
      After 'cleanup_py_fmt'

      It "auto-detects ruff format for Python"
        invoke_py_auto() {
          quality.format.run "$TEST_WS" 2>/dev/null || return 1
          grep -q "ruff format" "$MOCK_LOG"
        }
        When call invoke_py_auto
        The status should be success
      End
    End

    Describe "Tier 3: auto-detect for Rust"
      setup_rust_fmt() {
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock.log"
        printf '[package]\nname = "test"\n' > "${TEST_WS}/Cargo.toml"
        MOCK_BIN="$(mktemp -d)"
        cat > "${MOCK_BIN}/cargo" << MOCKEOF
#!/usr/bin/env bash
printf 'cargo %s\n' "\$*" >> "$MOCK_LOG"
exit 0
MOCKEOF
        chmod +x "${MOCK_BIN}/cargo"
        ORIG_PATH="$PATH"
        export PATH="${MOCK_BIN}:${PATH}"
      }
      cleanup_rust_fmt() {
        export PATH="$ORIG_PATH"
        rm -rf "$TEST_WS" "$MOCK_BIN"
      }
      Before 'setup_rust_fmt'
      After 'cleanup_rust_fmt'

      It "auto-detects rustfmt via cargo for Rust"
        invoke_rust_fmt() {
          quality.format.run "$TEST_WS" 2>/dev/null || return 1
          grep -q "cargo fmt" "$MOCK_LOG"
        }
        When call invoke_rust_fmt
        The status should be success
      End
    End

    Describe "with failing formatter"
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

      It "returns 10 when format check fails"
        When call quality.format.run "$TEST_WS"
        The status should equal 10
        The stderr should include "format violations found"
      End
    End
  End
End
