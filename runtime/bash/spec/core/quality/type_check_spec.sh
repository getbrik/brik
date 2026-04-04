Describe "quality/type_check.sh"
  Include "$BRIK_RUNTIME_LIB/logging.sh"
  Include "$BRIK_RUNTIME_LIB/tools.sh"
  Include "$BRIK_CORE_LIB/quality/type_check.sh"

  Describe "quality.type_check.run"
    It "returns 6 for nonexistent workspace"
      When call quality.type_check.run "/nonexistent/workspace"
      The status should equal 6
      The stderr should include "required directory not found"
    End

    Describe "unknown option"
      setup_ws() { TEST_WS="$(mktemp -d)"; }
      cleanup_ws() { rm -rf "$TEST_WS"; }
      Before 'setup_ws'
      After 'cleanup_ws'

      It "returns 2 for unknown option"
        When call quality.type_check.run "$TEST_WS" --badopt
        The status should equal 2
        The stderr should include "unknown option"
      End
    End

    Describe "Tier 1: command override success"
      setup_cmd() {
        TEST_WS="$(mktemp -d)"
        MOCK_BIN="$(mktemp -d)"
        cat > "${MOCK_BIN}/my-checker" << 'EOF'
#!/usr/bin/env bash
exit 0
EOF
        chmod +x "${MOCK_BIN}/my-checker"
        ORIG_PATH="$PATH"
        export PATH="${MOCK_BIN}:${PATH}"
        export BRIK_QUALITY_TYPE_CHECK_COMMAND="my-checker"
      }
      cleanup_cmd() {
        export PATH="$ORIG_PATH"
        unset BRIK_QUALITY_TYPE_CHECK_COMMAND
        rm -rf "$TEST_WS" "$MOCK_BIN"
      }
      Before 'setup_cmd'
      After 'cleanup_cmd'

      It "runs command override and passes"
        When call quality.type_check.run "$TEST_WS"
        The status should be success
        The stderr should include "type check passed"
      End
    End

    Describe "Tier 1: command override failure"
      setup_cmd_fail() {
        TEST_WS="$(mktemp -d)"
        MOCK_BIN="$(mktemp -d)"
        cat > "${MOCK_BIN}/failing-checker" << 'EOF'
#!/usr/bin/env bash
exit 1
EOF
        chmod +x "${MOCK_BIN}/failing-checker"
        ORIG_PATH="$PATH"
        export PATH="${MOCK_BIN}:${PATH}"
        export BRIK_QUALITY_TYPE_CHECK_COMMAND="failing-checker"
      }
      cleanup_cmd_fail() {
        export PATH="$ORIG_PATH"
        unset BRIK_QUALITY_TYPE_CHECK_COMMAND
        rm -rf "$TEST_WS" "$MOCK_BIN"
      }
      Before 'setup_cmd_fail'
      After 'cleanup_cmd_fail'

      It "returns 10 when command fails"
        When call quality.type_check.run "$TEST_WS"
        The status should equal 10
        The stderr should include "type check violations found"
      End
    End

    Describe "Tier 2: tsc with npx"
      setup_tsc() {
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock.log"
        MOCK_BIN="$(mktemp -d)"
        cat > "${MOCK_BIN}/npx" << MOCKEOF
#!/usr/bin/env bash
printf 'npx %s\n' "\$*" >> "$MOCK_LOG"
exit 0
MOCKEOF
        chmod +x "${MOCK_BIN}/npx"
        ORIG_PATH="$PATH"
        export PATH="${MOCK_BIN}:${PATH}"
        export BRIK_QUALITY_TYPE_CHECK_TOOL="tsc"
      }
      cleanup_tsc() {
        export PATH="$ORIG_PATH"
        unset BRIK_QUALITY_TYPE_CHECK_TOOL
        rm -rf "$TEST_WS" "$MOCK_BIN"
      }
      Before 'setup_tsc'
      After 'cleanup_tsc'

      It "runs npx tsc --noEmit"
        invoke_tsc() {
          quality.type_check.run "$TEST_WS" 2>/dev/null || return 1
          grep -q "tsc --noEmit" "$MOCK_LOG"
        }
        When call invoke_tsc
        The status should be success
      End
    End

    Describe "Tier 2: tsc without npx"
      setup_tsc_no_npx() {
        TEST_WS="$(mktemp -d)"
        MOCK_BIN="$(mktemp -d)"
        ORIG_PATH="$PATH"
        export PATH="${MOCK_BIN}"
        export BRIK_QUALITY_TYPE_CHECK_TOOL="tsc"
      }
      cleanup_tsc_no_npx() {
        export PATH="$ORIG_PATH"
        unset BRIK_QUALITY_TYPE_CHECK_TOOL
        rm -rf "$TEST_WS" "$MOCK_BIN"
      }
      Before 'setup_tsc_no_npx'
      After 'cleanup_tsc_no_npx'

      It "returns 3 when npx not found"
        When call quality.type_check.run "$TEST_WS"
        The status should equal 3
        The stderr should include "npx not found"
      End
    End

    Describe "Tier 2: mypy present"
      setup_mypy() {
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock.log"
        MOCK_BIN="$(mktemp -d)"
        cat > "${MOCK_BIN}/mypy" << MOCKEOF
#!/usr/bin/env bash
printf 'mypy %s\n' "\$*" >> "$MOCK_LOG"
exit 0
MOCKEOF
        chmod +x "${MOCK_BIN}/mypy"
        ORIG_PATH="$PATH"
        export PATH="${MOCK_BIN}:${PATH}"
        export BRIK_QUALITY_TYPE_CHECK_TOOL="mypy"
      }
      cleanup_mypy() {
        export PATH="$ORIG_PATH"
        unset BRIK_QUALITY_TYPE_CHECK_TOOL
        rm -rf "$TEST_WS" "$MOCK_BIN"
      }
      Before 'setup_mypy'
      After 'cleanup_mypy'

      It "runs mypy ."
        invoke_mypy() {
          quality.type_check.run "$TEST_WS" 2>/dev/null || return 1
          grep -q "^mypy" "$MOCK_LOG"
        }
        When call invoke_mypy
        The status should be success
      End
    End

    Describe "Tier 2: mypy missing"
      setup_no_mypy() {
        TEST_WS="$(mktemp -d)"
        MOCK_BIN="$(mktemp -d)"
        ORIG_PATH="$PATH"
        export PATH="${MOCK_BIN}"
        export BRIK_QUALITY_TYPE_CHECK_TOOL="mypy"
      }
      cleanup_no_mypy() {
        export PATH="$ORIG_PATH"
        unset BRIK_QUALITY_TYPE_CHECK_TOOL
        rm -rf "$TEST_WS" "$MOCK_BIN"
      }
      Before 'setup_no_mypy'
      After 'cleanup_no_mypy'

      It "returns 3 when mypy not found"
        When call quality.type_check.run "$TEST_WS"
        The status should equal 3
        The stderr should include "mypy not found"
      End
    End

    Describe "Tier 2: pyright without npx"
      setup_pyright_no_npx() {
        TEST_WS="$(mktemp -d)"
        MOCK_BIN="$(mktemp -d)"
        ORIG_PATH="$PATH"
        export PATH="${MOCK_BIN}"
        export BRIK_QUALITY_TYPE_CHECK_TOOL="pyright"
      }
      cleanup_pyright_no_npx() {
        export PATH="$ORIG_PATH"
        unset BRIK_QUALITY_TYPE_CHECK_TOOL
        rm -rf "$TEST_WS" "$MOCK_BIN"
      }
      Before 'setup_pyright_no_npx'
      After 'cleanup_pyright_no_npx'

      It "returns 3 when npx not found for pyright"
        When call quality.type_check.run "$TEST_WS"
        The status should equal 3
        The stderr should include "npx not found"
      End
    End

    Describe "Tier 3: auto-detect tsconfig.json"
      setup_ts_auto() {
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock.log"
        printf '{"compilerOptions":{}}\n' > "${TEST_WS}/tsconfig.json"
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
      cleanup_ts_auto() {
        export PATH="$ORIG_PATH"
        rm -rf "$TEST_WS" "$MOCK_BIN"
      }
      Before 'setup_ts_auto'
      After 'cleanup_ts_auto'

      It "auto-detects tsc from tsconfig.json"
        invoke_ts_auto() {
          quality.type_check.run "$TEST_WS" 2>/dev/null || return 1
          grep -q "tsc --noEmit" "$MOCK_LOG"
        }
        When call invoke_ts_auto
        The status should be success
      End
    End

    Describe "Tier 3: auto-detect mypy.ini"
      setup_mypy_auto() {
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock.log"
        printf '[mypy]\nstrict = True\n' > "${TEST_WS}/mypy.ini"
        MOCK_BIN="$(mktemp -d)"
        cat > "${MOCK_BIN}/mypy" << MOCKEOF
#!/usr/bin/env bash
printf 'mypy %s\n' "\$*" >> "$MOCK_LOG"
exit 0
MOCKEOF
        chmod +x "${MOCK_BIN}/mypy"
        ORIG_PATH="$PATH"
        export PATH="${MOCK_BIN}:${PATH}"
      }
      cleanup_mypy_auto() {
        export PATH="$ORIG_PATH"
        rm -rf "$TEST_WS" "$MOCK_BIN"
      }
      Before 'setup_mypy_auto'
      After 'cleanup_mypy_auto'

      It "auto-detects mypy from mypy.ini"
        invoke_mypy_auto() {
          quality.type_check.run "$TEST_WS" 2>/dev/null || return 1
          grep -q "^mypy" "$MOCK_LOG"
        }
        When call invoke_mypy_auto
        The status should be success
      End
    End

    Describe "Tier 3: auto-detect [tool.mypy] in pyproject.toml"
      setup_mypy_pyproject() {
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock.log"
        printf '[project]\nname = "test"\n\n[tool.mypy]\nstrict = true\n' > "${TEST_WS}/pyproject.toml"
        MOCK_BIN="$(mktemp -d)"
        cat > "${MOCK_BIN}/mypy" << MOCKEOF
#!/usr/bin/env bash
printf 'mypy %s\n' "\$*" >> "$MOCK_LOG"
exit 0
MOCKEOF
        chmod +x "${MOCK_BIN}/mypy"
        ORIG_PATH="$PATH"
        export PATH="${MOCK_BIN}:${PATH}"
      }
      cleanup_mypy_pyproject() {
        export PATH="$ORIG_PATH"
        rm -rf "$TEST_WS" "$MOCK_BIN"
      }
      Before 'setup_mypy_pyproject'
      After 'cleanup_mypy_pyproject'

      It "auto-detects mypy from pyproject.toml [tool.mypy]"
        invoke_mypy_pyproject() {
          quality.type_check.run "$TEST_WS" 2>/dev/null || return 1
          grep -q "^mypy" "$MOCK_LOG"
        }
        When call invoke_mypy_pyproject
        The status should be success
      End
    End

    Describe "Tier 3: no type checker detected"
      setup_empty() { TEST_WS="$(mktemp -d)"; }
      cleanup_empty() { rm -rf "$TEST_WS"; }
      Before 'setup_empty'
      After 'cleanup_empty'

      It "skips when no type checker detected"
        When call quality.type_check.run "$TEST_WS"
        The status should be success
        The stderr should include "no type checker detected"
      End
    End

    Describe "Tier 2: unknown tool as raw command"
      setup_raw() {
        TEST_WS="$(mktemp -d)"
        MOCK_BIN="$(mktemp -d)"
        cat > "${MOCK_BIN}/my-type-checker" << 'EOF'
#!/usr/bin/env bash
exit 0
EOF
        chmod +x "${MOCK_BIN}/my-type-checker"
        ORIG_PATH="$PATH"
        export PATH="${MOCK_BIN}:${PATH}"
        export BRIK_QUALITY_TYPE_CHECK_TOOL="my-type-checker"
      }
      cleanup_raw() {
        export PATH="$ORIG_PATH"
        unset BRIK_QUALITY_TYPE_CHECK_TOOL
        rm -rf "$TEST_WS" "$MOCK_BIN"
      }
      Before 'setup_raw'
      After 'cleanup_raw'

      It "uses unknown tool name as raw command"
        When call quality.type_check.run "$TEST_WS"
        The status should be success
        The stderr should include "type check passed"
      End
    End

    Describe "with failing type checker"
      setup_fail() {
        TEST_WS="$(mktemp -d)"
        printf '{"compilerOptions":{}}\n' > "${TEST_WS}/tsconfig.json"
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

      It "returns 10 when type check fails"
        When call quality.type_check.run "$TEST_WS"
        The status should equal 10
        The stderr should include "type check violations found"
      End
    End
  End
End
