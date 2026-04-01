Describe "stages.test"
  Include "$BRIK_HOME/runtime/bash/lib/runtime/stage.sh"
  Include "$BRIK_HOME/runtime/bash/lib/core/_loader.sh"
  Include "$BRIK_HOME/runtime/bash/lib/core/config.sh"
  Include "$BRIK_HOME/runtime/bash/lib/stages/test.sh"

  setup_env() {
    export BRIK_CONFIG_FILE
    BRIK_CONFIG_FILE="$(mktemp)"
    printf 'version: 1\nproject:\n  name: test\n  stack: node\n' > "$BRIK_CONFIG_FILE"
    export BRIK_LOG_DIR
    BRIK_LOG_DIR="$(mktemp -d)"
    export BRIK_WORKSPACE
    BRIK_WORKSPACE="$(mktemp -d)"
    export BRIK_PROJECT_DIR="$BRIK_WORKSPACE"
    export BRIK_PLATFORM="gitlab"
    config.read "$BRIK_CONFIG_FILE" >/dev/null 2>&1 || true
  }
  cleanup_env() {
    rm -f "$BRIK_CONFIG_FILE"
    rm -rf "$BRIK_LOG_DIR" "$BRIK_WORKSPACE"
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
