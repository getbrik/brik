Describe "quality/lint.sh"
  Include "$BRIK_RUNTIME_LIB/logging.sh"
  Include "$BRIK_RUNTIME_LIB/tools.sh"
  Include "$BRIK_CORE_LIB/quality/lint.sh"
  Include "$BRIK_HOME/runtime/bash/spec/support/mock_helper.sh"

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
        mock.setup
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_npx.log"
        printf '{"name":"test"}\n' > "${TEST_WS}/package.json"
        printf 'export default [];\n' > "${TEST_WS}/eslint.config.js"
        mock.create_logging "npx" "$MOCK_LOG"
        mock.activate
      }
      cleanup_node_lint() {
        mock.cleanup
        rm -rf "$TEST_WS"
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
        mock.setup
        TEST_WS="$(mktemp -d)"
        printf '{"name":"test"}\n' > "${TEST_WS}/package.json"
        printf 'export default [];\n' > "${TEST_WS}/eslint.config.js"
        mock.isolate
      }
      cleanup_no_npx() {
        mock.cleanup
        rm -rf "$TEST_WS"
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
        mock.setup
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_ruff.log"
        printf '[project]\nname = "test"\n' > "${TEST_WS}/pyproject.toml"
        mock.create_logging "ruff" "$MOCK_LOG"
        mock.activate
      }
      cleanup_py_lint() {
        mock.cleanup
        rm -rf "$TEST_WS"
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
        mock.setup
        TEST_WS="$(mktemp -d)"
        printf '[project]\nname = "test"\n' > "${TEST_WS}/pyproject.toml"
        mock.isolate
      }
      cleanup_no_ruff() {
        mock.cleanup
        rm -rf "$TEST_WS"
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
        mock.setup
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_cargo.log"
        printf '[package]\nname = "test"\n' > "${TEST_WS}/Cargo.toml"
        mock.create_logging "cargo" "$MOCK_LOG"
        mock.activate
      }
      cleanup_rust_lint() {
        mock.cleanup
        rm -rf "$TEST_WS"
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

    Describe "with Java workspace and no mvn"
      setup_java_lint() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        printf '<project/>\n' > "${TEST_WS}/pom.xml"
        mock.isolate
      }
      cleanup_java_lint() {
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_java_lint'
      After 'cleanup_java_lint'

      It "skips Java when mvn not found"
        When call quality.lint.run "$TEST_WS"
        The status should be success
        The stderr should include "mvn not found"
      End
    End

    Describe "Node.js without eslint config"
      setup_no_eslint_cfg() {
        TEST_WS="$(mktemp -d)"
        printf '{"name":"test"}\n' > "${TEST_WS}/package.json"
      }
      cleanup_no_eslint_cfg() { rm -rf "$TEST_WS"; }
      Before 'setup_no_eslint_cfg'
      After 'cleanup_no_eslint_cfg'

      It "skips lint when no eslint config found"
        When call quality.lint.run "$TEST_WS"
        The status should be success
        The stderr should include "no eslint config found"
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
  End
End
