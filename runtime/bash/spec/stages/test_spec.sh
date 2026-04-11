Describe "stages.test"
  Include "$BRIK_HOME/runtime/bash/lib/runtime/stage.sh"
  Include "$BRIK_HOME/runtime/bash/lib/core/_loader.sh"
  Include "$BRIK_HOME/runtime/bash/lib/core/config.sh"
  Include "$BRIK_HOME/runtime/bash/lib/stages/test.sh"

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

  It "returns 0 when test.run succeeds"
    run_test_success() {
      brik.use() { :; }
      test.run() { return 0; }
      local ctx
      ctx="$(context.create "test")" 2>/dev/null || ctx="$(mktemp)"
      stages.test "$ctx" >/dev/null 2>&1
    }
    When call run_test_success
    The status should be success
  End

  It "sets BRIK_TEST_STATUS to success on success"
    run_test_ctx_success() {
      brik.use() { :; }
      test.run() { return 0; }
      local ctx
      ctx="$(context.create "test")" 2>/dev/null || ctx="$(mktemp)"
      stages.test "$ctx" >/dev/null 2>&1
      grep "^BRIK_TEST_STATUS=" "$ctx" | cut -d= -f2
    }
    When call run_test_ctx_success
    The output should equal "success"
  End

  It "returns non-zero when test.run fails"
    run_test_failure() {
      brik.use() { :; }
      test.run() { return 1; }
      local ctx
      ctx="$(context.create "test")" 2>/dev/null || ctx="$(mktemp)"
      stages.test "$ctx" >/dev/null 2>&1
    }
    When call run_test_failure
    The status should be failure
  End

  It "sets BRIK_TEST_STATUS to failed on failure"
    run_test_ctx_failure() {
      brik.use() { :; }
      test.run() { return 1; }
      local ctx
      ctx="$(context.create "test")" 2>/dev/null || ctx="$(mktemp)"
      stages.test "$ctx" >/dev/null 2>&1 || true
      grep "^BRIK_TEST_STATUS=" "$ctx" | cut -d= -f2
    }
    When call run_test_ctx_failure
    The output should equal "failed"
  End

  It "exports BRIK_TEST_FRAMEWORK from config"
    run_test_framework() {
      brik.use() { :; }
      test.run() { return 0; }
      local ctx
      ctx="$(context.create "test")" 2>/dev/null || ctx="$(mktemp)"
      stages.test "$ctx" >/dev/null 2>&1
      printf '%s' "${BRIK_TEST_FRAMEWORK:-}"
    }
    When call run_test_framework
    The output should equal "jest"
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
        brik.use() { :; }
        test.run() { return 0; }
        local ctx
        ctx="$(context.create "test")" 2>/dev/null || ctx="$(mktemp)"
        stages.test "$ctx"
      }
      When call run_test_log_unit
      The error should include "unit test command"
    End
  End
End

Describe "_brik.install_deps (test mode)"
  Include "$BRIK_HOME/runtime/bash/lib/runtime/stage.sh"
  Include "$BRIK_HOME/runtime/bash/lib/core/_loader.sh"
  Include "$BRIK_HOME/runtime/bash/lib/stages/test.sh"
  Include "$BRIK_HOME/runtime/bash/spec/support/mock_helper.sh"

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
        mock.create_logging "npm" "$MOCK_LOG"
        mock.activate
        _brik.install_deps "$DEPS_WS" test 2>/dev/null
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
        _brik.install_deps "$DEPS_WS" test 2>/dev/null
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
        _brik.install_deps "$DEPS_WS" test 2>/dev/null
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
        _brik.install_deps "$DEPS_WS" test 2>/dev/null
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
        _brik.install_deps "$DEPS_WS" test 2>/dev/null
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
        _brik.install_deps "$DEPS_WS" test 2>/dev/null
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
        _brik.install_deps "$DEPS_WS" test 2>/dev/null
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
        _brik.install_deps "$DEPS_WS" test 2>/dev/null
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
        _brik.install_deps "$DEPS_WS" test 2>/dev/null
        [[ ! -f "$MOCK_LOG" ]]
      }
      When call run_unknown_stack
      The status should be success
    End

    It "does nothing when BRIK_BUILD_STACK is empty"
      run_empty_stack() {
        unset BRIK_BUILD_STACK
        rm -f "$MOCK_LOG"
        _brik.install_deps "$DEPS_WS" test 2>/dev/null
        [[ ! -f "$MOCK_LOG" ]]
      }
      When call run_empty_stack
      The status should be success
    End
  End
End
