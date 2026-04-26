Describe "stages.test"
  Include "$BRIK_PIPELINE_LIB/logging.sh"
  Include "$BRIK_PIPELINE_LIB/tools.sh"
  Include "$BRIK_HOME/lib/pipeline/stage.sh"
  Include "$BRIK_HOME/lib/pipeline/loader.sh"
  Include "$BRIK_HOME/lib/transverse/config.sh"
  Include "$BRIK_HOME/lib/stages/test.sh"

  setup_env() {
    export BRIK_CONFIG_FILE
    BRIK_CONFIG_FILE="$(mktemp)"
    printf 'version: 1\nproject:\n  name: test\n  stack: node\n' > "$BRIK_CONFIG_FILE"
    export BRIK_WORKSPACE
    BRIK_WORKSPACE="$(mktemp -d)"
    export BRIK_PROJECT_DIR="$BRIK_WORKSPACE"
    export BRIK_PLATFORM="gitlab"
    config.read "$BRIK_CONFIG_FILE" >/dev/null 2>&1 || true
  }
  cleanup_env() {
    rm -f "$BRIK_CONFIG_FILE"
    rm -rf "$BRIK_WORKSPACE"
  }
  Before 'setup_env'
  After 'cleanup_env'

  It "is callable as a function"
    callable_check() { declare -f stages.test >/dev/null; }
    When call callable_check
    The status should be success
  End

  _stub_leaf_success() {
    brik.use() { :; }
    stacks.detect_from_framework() { printf 'node'; return 0; }
    stacks.detect() { printf 'node'; return 0; }
    stacks.node.test_cmd() { printf 'true'; return 0; }
    stacks.node.test() { printf 'true'; return 0; }
    stacks.install_deps() { :; }
  }

  _stub_leaf_failure() {
    brik.use() { :; }
    stacks.detect_from_framework() { printf 'node'; return 0; }
    stacks.detect() { printf 'node'; return 0; }
    stacks.node.test_cmd() { printf 'false'; return 0; }
    stacks.node.test() { printf 'false'; return 0; }
    stacks.install_deps() { :; }
  }

  It "returns 0 when the stack test cmd succeeds"
    run_test_success() {
      _stub_leaf_success
      local ctx
      ctx="$(context.create "test")" 2>/dev/null || ctx="$(mktemp)"
      stages.test "$ctx" >/dev/null 2>&1
    }
    When call run_test_success
    The status should be success
  End

  It "returns non-zero when the stack test cmd fails"
    run_test_failure() {
      _stub_leaf_failure
      local ctx
      ctx="$(context.create "test")" 2>/dev/null || ctx="$(mktemp)"
      stages.test "$ctx" >/dev/null 2>&1
    }
    When call run_test_failure
    The status should be failure
  End

  It "exports BRIK_TEST_FRAMEWORK from config"
    run_test_framework() {
      _stub_leaf_success
      local ctx
      ctx="$(context.create "test")" 2>/dev/null || ctx="$(mktemp)"
      stages.test "$ctx" >/dev/null 2>&1
      printf '%s' "${BRIK_TEST_FRAMEWORK:-}"
    }
    When call run_test_framework
    The output should equal "jest"
  End

  It "runs BRIK_TEST_COMMAND override when set"
    run_test_override() {
      cat > "$BRIK_CONFIG_FILE" <<'YAML'
version: 1
project:
  name: test
  stack: node
test:
  command: "printf 'override-ran'"
YAML
      config.read "$BRIK_CONFIG_FILE" >/dev/null 2>&1 || true
      _stub_leaf_success
      local ctx
      ctx="$(context.create "test")" 2>/dev/null || ctx="$(mktemp)"
      stages.test "$ctx" 2>/dev/null
    }
    When call run_test_override
    The output should include "override-ran"
  End

  It "returns IO_FAILURE when BRIK_WORKSPACE does not exist"
    run_test_no_workspace() {
      _stub_leaf_success
      export BRIK_WORKSPACE="/nonexistent/brik-ws-$$"
      local ctx
      ctx="$(context.create "test")" 2>/dev/null || ctx="$(mktemp)"
      stages.test "$ctx" 2>/dev/null
      printf '%s' "$?"
    }
    When call run_test_no_workspace
    The output should equal "6"
  End

  It "runs BRIK_TEST_COMMAND override and reports success"
    run_test_cmd_success() {
      cat > "$BRIK_CONFIG_FILE" <<'YAML'
version: 1
project:
  name: test
  stack: node
test:
  command: "true"
YAML
      config.read "$BRIK_CONFIG_FILE" >/dev/null 2>&1 || true
      _stub_leaf_success
      local ctx
      ctx="$(context.create "test")" 2>/dev/null || ctx="$(mktemp)"
      stages.test "$ctx" 2>/dev/null
      printf '%s' "$?"
    }
    When call run_test_cmd_success
    The output should equal "0"
  End

  It "returns CHECK_FAILED when BRIK_TEST_COMMAND override fails"
    run_test_cmd_failure() {
      cat > "$BRIK_CONFIG_FILE" <<'YAML'
version: 1
project:
  name: test
  stack: node
test:
  command: "false"
YAML
      config.read "$BRIK_CONFIG_FILE" >/dev/null 2>&1 || true
      _stub_leaf_success
      local ctx
      ctx="$(context.create "test")" 2>/dev/null || ctx="$(mktemp)"
      stages.test "$ctx" 2>/dev/null
      printf '%s' "$?"
    }
    When call run_test_cmd_failure
    The output should equal "10"
  End

  It "returns CONFIG_ERROR when test framework is unsupported"
    run_test_bad_framework() {
      cat > "$BRIK_CONFIG_FILE" <<'YAML'
version: 1
project:
  name: test
  stack: node
test:
  framework: cobol-test
YAML
      config.read "$BRIK_CONFIG_FILE" >/dev/null 2>&1 || true
      brik.use() { :; }
      stacks.detect_from_framework() { return 1; }
      stacks.install_deps() { :; }
      local ctx
      ctx="$(context.create "test")" 2>/dev/null || ctx="$(mktemp)"
      stages.test "$ctx" 2>/dev/null
      printf '%s' "$?"
    }
    When call run_test_bad_framework
    The output should equal "7"
  End

  It "returns MISSING_DEP when stack cannot be auto-detected"
    run_test_auto_fail() {
      cat > "$BRIK_CONFIG_FILE" <<'YAML'
version: 1
project:
  name: test
YAML
      config.read "$BRIK_CONFIG_FILE" >/dev/null 2>&1 || true
      brik.use() { :; }
      stacks.detect() { return 1; }
      stacks.install_deps() { :; }
      local ctx
      ctx="$(context.create "test")" 2>/dev/null || ctx="$(mktemp)"
      stages.test "$ctx" 2>/dev/null
      printf '%s' "$?"
    }
    When call run_test_auto_fail
    The output should equal "3"
  End

  It "returns CONFIG_ERROR when stack module cannot be loaded"
    run_test_unsupported_stack() {
      brik.use() {
        case "$1" in
          stacks.node) return 1 ;;
          *) return 0 ;;
        esac
      }
      stacks.detect() { printf 'node'; return 0; }
      stacks.install_deps() { :; }
      local ctx
      ctx="$(context.create "test")" 2>/dev/null || ctx="$(mktemp)"
      stages.test "$ctx" 2>/dev/null
      printf '%s' "$?"
    }
    When call run_test_unsupported_stack
    The output should equal "7"
  End

  Describe "with test commands configured"
    setup_test_cmds() {
      cat > "$BRIK_CONFIG_FILE" <<'YAML'
version: 1
project:
  name: test
  stack: node
test:
  framework: jest
  commands:
    unit: npm test -- --unit
    integration: npm test -- --integration
YAML
      config.read "$BRIK_CONFIG_FILE" >/dev/null 2>&1 || true
    }
    Before 'setup_test_cmds'

    It "logs unit test command"
      run_test_log_unit() {
        _stub_leaf_success
        local ctx
        ctx="$(context.create "test")" 2>/dev/null || ctx="$(mktemp)"
        stages.test "$ctx"
      }
      When call run_test_log_unit
      The error should include "unit test command"
    End
  End
End

Describe "stacks.install_deps (test mode)"
  Include "$BRIK_HOME/lib/pipeline/stage.sh"
  Include "$BRIK_HOME/lib/pipeline/loader.sh"
  Include "$BRIK_HOME/lib/stages/test.sh"
  Include "$BRIK_HOME/spec/support/mock_helper.sh"

  setup_deps_env() {
    mock.setup
    DEPS_WS="$(mktemp -d)"
    MOCK_LOG="${DEPS_WS}/mock.log"
  }
  cleanup_deps_env() {
    mock.cleanup
    rm -rf "$DEPS_WS"
    unset BRIK_BUILD_STACK
  }
  Before 'setup_deps_env'
  After 'cleanup_deps_env'

  Describe "node stack"
    It "runs npm ci when node_modules is missing"
      run_node_install() {
        export BRIK_BUILD_STACK="node"
        printf '{"name":"t","version":"0.0.0"}\n' > "$DEPS_WS/package.json"
        mock.create_logging "npm" "$MOCK_LOG"
        mock.activate
        stacks.install_deps "$DEPS_WS" test 2>/dev/null
        grep -q "npm ci" "$MOCK_LOG"
      }
      When call run_node_install
      The status should be success
    End

    It "skips npm ci when node_modules exists"
      run_node_skip() {
        export BRIK_BUILD_STACK="node"
        mkdir -p "${DEPS_WS}/node_modules"
        mock.create_exit "npm" 1
        mock.activate
        stacks.install_deps "$DEPS_WS" test 2>/dev/null
      }
      When call run_node_skip
      The status should be success
    End
  End

  Describe "python stack"
    It "installs from pyproject.toml with dev extras"
      run_python_pyproject() {
        export BRIK_BUILD_STACK="python"
        printf '[project]\nname = "test"\n' > "${DEPS_WS}/pyproject.toml"
        mock.create_logging "pip" "$MOCK_LOG"
        mock.activate
        stacks.install_deps "$DEPS_WS" test 2>/dev/null
        grep -q 'pip install -e' "$MOCK_LOG"
      }
      When call run_python_pyproject
      The status should be success
    End

    It "installs from requirements.txt"
      run_python_req() {
        export BRIK_BUILD_STACK="python"
        rm -f "${DEPS_WS}/pyproject.toml"
        printf 'pytest\n' > "${DEPS_WS}/requirements.txt"
        mock.create_logging "pip" "$MOCK_LOG"
        mock.activate
        stacks.install_deps "$DEPS_WS" test 2>/dev/null
        grep -q 'pip install -r requirements.txt' "$MOCK_LOG"
      }
      When call run_python_req
      The status should be success
    End

    It "does nothing when no python project files exist"
      run_python_noop() {
        export BRIK_BUILD_STACK="python"
        rm -f "${DEPS_WS}/pyproject.toml" "${DEPS_WS}/requirements.txt"
        rm -f "$MOCK_LOG"
        stacks.install_deps "$DEPS_WS" test 2>/dev/null
        [[ ! -f "$MOCK_LOG" ]]
      }
      When call run_python_noop
      The status should be success
    End
  End

  Describe "java stack"
    It "does nothing (Maven/Gradle handle deps)"
      run_java_noop() {
        export BRIK_BUILD_STACK="java"
        rm -f "$MOCK_LOG"
        stacks.install_deps "$DEPS_WS" test 2>/dev/null
        [[ ! -f "$MOCK_LOG" ]]
      }
      When call run_java_noop
      The status should be success
    End
  End

  Describe "rust stack"
    It "does nothing (Cargo handles deps)"
      run_rust_noop() {
        export BRIK_BUILD_STACK="rust"
        rm -f "$MOCK_LOG"
        stacks.install_deps "$DEPS_WS" test 2>/dev/null
        [[ ! -f "$MOCK_LOG" ]]
      }
      When call run_rust_noop
      The status should be success
    End
  End

  Describe "dotnet stack"
    It "runs dotnet restore"
      run_dotnet_restore() {
        export BRIK_BUILD_STACK="dotnet"
        mock.create_logging "dotnet" "$MOCK_LOG"
        mock.activate
        stacks.install_deps "$DEPS_WS" test 2>/dev/null
        grep -q "dotnet restore" "$MOCK_LOG"
      }
      When call run_dotnet_restore
      The status should be success
    End
  End

  Describe "unknown stack"
    It "does nothing for unrecognized stack"
      run_unknown_stack() {
        export BRIK_BUILD_STACK="go"
        rm -f "$MOCK_LOG"
        stacks.install_deps "$DEPS_WS" test 2>/dev/null
        [[ ! -f "$MOCK_LOG" ]]
      }
      When call run_unknown_stack
      The status should be success
    End

    It "does nothing when BRIK_BUILD_STACK is empty"
      run_empty_stack() {
        unset BRIK_BUILD_STACK
        rm -f "$MOCK_LOG"
        stacks.install_deps "$DEPS_WS" test 2>/dev/null
        [[ ! -f "$MOCK_LOG" ]]
      }
      When call run_empty_stack
      The status should be success
    End
  End
End
