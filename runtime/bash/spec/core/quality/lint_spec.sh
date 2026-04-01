Describe "quality/lint.sh"
  Include "$BRIK_RUNTIME_LIB/logging.sh"
  Include "$BRIK_RUNTIME_LIB/tools.sh"
  Include "$BRIK_CORE_LIB/quality/lint.sh"

  Describe "quality.lint.run"
    It "returns 6 for nonexistent workspace"
      When call quality.lint.run "/nonexistent/workspace"
      The status should equal 6
      The stderr should include "required directory not found"
    End

    Describe "unknown option"
      setup_ws() { TEST_WS="$(mktemp -d)"; }
      cleanup_ws() { rm -rf "$TEST_WS"; }
      Before 'setup_ws'
      After 'cleanup_ws'

      It "returns 2 for unknown option"
        When call quality.lint.run "$TEST_WS" --badopt
        The status should equal 2
        The stderr should include "unknown option"
      End
    End

    Describe "with Node.js workspace and mock npx"
      setup_node_lint() {
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_npx.log"
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
      cleanup_node_lint() {
        export PATH="$ORIG_PATH"
        rm -rf "$TEST_WS" "$MOCK_BIN"
      }
      Before 'setup_node_lint'
      After 'cleanup_node_lint'

      It "runs eslint for Node.js projects"
        invoke_eslint() {
          quality.lint.run "$TEST_WS" 2>/dev/null || return 1
          grep -q "^npx eslint" "$MOCK_LOG"
        }
        When call invoke_eslint
        The status should be success
      End

      It "passes --fix flag to eslint"
        invoke_fix() {
          quality.lint.run "$TEST_WS" --fix 2>/dev/null || return 1
          grep -q "\-\-fix" "$MOCK_LOG"
        }
        When call invoke_fix
        The status should be success
      End

      It "succeeds and reports lint passed"
        When call quality.lint.run "$TEST_WS"
        The status should be success
        The stderr should include "lint passed"
      End
    End

    Describe "Node.js npx not found"
      setup_no_npx() {
        TEST_WS="$(mktemp -d)"
        printf '{"name":"test"}\n' > "${TEST_WS}/package.json"
        MOCK_BIN="$(mktemp -d)"
        ORIG_PATH="$PATH"
        export PATH="${MOCK_BIN}"
      }
      cleanup_no_npx() {
        export PATH="$ORIG_PATH"
        rm -rf "$TEST_WS" "$MOCK_BIN"
      }
      Before 'setup_no_npx'
      After 'cleanup_no_npx'

      It "returns 3 when npx is not available"
        When call quality.lint.run "$TEST_WS"
        The status should equal 3
        The stderr should include "npx not found"
      End
    End

    Describe "with Python workspace and mock ruff"
      setup_py_lint() {
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_ruff.log"
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
      cleanup_py_lint() {
        export PATH="$ORIG_PATH"
        rm -rf "$TEST_WS" "$MOCK_BIN"
      }
      Before 'setup_py_lint'
      After 'cleanup_py_lint'

      It "runs ruff check for Python projects"
        invoke_ruff() {
          quality.lint.run "$TEST_WS" 2>/dev/null || return 1
          grep -q "^ruff check" "$MOCK_LOG"
        }
        When call invoke_ruff
        The status should be success
      End

      It "passes --fix flag to ruff"
        invoke_ruff_fix() {
          quality.lint.run "$TEST_WS" --fix 2>/dev/null || return 1
          grep -q "\-\-fix" "$MOCK_LOG"
        }
        When call invoke_ruff_fix
        The status should be success
      End
    End

    Describe "Python ruff not found"
      setup_no_ruff() {
        TEST_WS="$(mktemp -d)"
        printf '[project]\nname = "test"\n' > "${TEST_WS}/pyproject.toml"
        MOCK_BIN="$(mktemp -d)"
        ORIG_PATH="$PATH"
        export PATH="${MOCK_BIN}"
      }
      cleanup_no_ruff() {
        export PATH="$ORIG_PATH"
        rm -rf "$TEST_WS" "$MOCK_BIN"
      }
      Before 'setup_no_ruff'
      After 'cleanup_no_ruff'

      It "returns 3 when ruff is not available"
        When call quality.lint.run "$TEST_WS"
        The status should equal 3
        The stderr should include "ruff not found"
      End
    End

    Describe "with Rust workspace and mock cargo"
      setup_rust_lint() {
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_cargo.log"
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
      cleanup_rust_lint() {
        export PATH="$ORIG_PATH"
        rm -rf "$TEST_WS" "$MOCK_BIN"
      }
      Before 'setup_rust_lint'
      After 'cleanup_rust_lint'

      It "runs cargo clippy for Rust projects"
        invoke_clippy() {
          quality.lint.run "$TEST_WS" 2>/dev/null || return 1
          grep -q "^cargo clippy" "$MOCK_LOG"
        }
        When call invoke_clippy
        The status should be success
      End
    End

    Describe "with Java workspace"
      setup_java_lint() {
        TEST_WS="$(mktemp -d)"
        printf '<project/>\n' > "${TEST_WS}/pom.xml"
      }
      cleanup_java_lint() { rm -rf "$TEST_WS"; }
      Before 'setup_java_lint'
      After 'cleanup_java_lint'

      It "skips Java with warning"
        When call quality.lint.run "$TEST_WS"
        The status should be success
        The stderr should include "not yet supported"
      End
    End

    Describe "with unknown workspace"
      setup_empty() { TEST_WS="$(mktemp -d)"; }
      cleanup_empty() { rm -rf "$TEST_WS"; }
      Before 'setup_empty'
      After 'cleanup_empty'

      It "returns 3 when no stack detected"
        When call quality.lint.run "$TEST_WS"
        The status should equal 3
        The stderr should include "cannot detect stack"
      End
    End

    Describe "with failing linter"
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

      It "returns 10 when lint fails"
        When call quality.lint.run "$TEST_WS"
        The status should equal 10
        The stderr should include "lint violations found"
      End
    End
  End
End
