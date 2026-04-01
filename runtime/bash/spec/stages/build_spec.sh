Describe "stages.build"
  Include "$BRIK_HOME/runtime/bash/lib/runtime/stage.sh"
  Include "$BRIK_HOME/runtime/bash/lib/core/_loader.sh"
  Include "$BRIK_HOME/runtime/bash/lib/core/config.sh"
  Include "$BRIK_HOME/runtime/bash/lib/stages/build.sh"

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
    callable_check() { declare -f stages.build >/dev/null; }
    When call callable_check
    The status should be success
  End

  It "returns 0 when build.run succeeds"
    run_build_success() {
      brik.use() { :; }
      build.run() { return 0; }
      local ctx
      ctx="$(context.create "build")" 2>/dev/null || ctx="$(mktemp)"
      stages.build "$ctx" >/dev/null 2>&1
    }
    When call run_build_success
    The status should be success
  End

  It "sets BRIK_BUILD_STATUS to success on success"
    run_build_ctx_success() {
      brik.use() { :; }
      build.run() { return 0; }
      local ctx
      ctx="$(context.create "build")" 2>/dev/null || ctx="$(mktemp)"
      stages.build "$ctx" >/dev/null 2>&1
      grep "^BRIK_BUILD_STATUS=" "$ctx" | cut -d= -f2
    }
    When call run_build_ctx_success
    The output should equal "success"
  End

  It "returns non-zero when build.run fails"
    run_build_failure() {
      brik.use() { :; }
      build.run() { return 1; }
      local ctx
      ctx="$(context.create "build")" 2>/dev/null || ctx="$(mktemp)"
      stages.build "$ctx" >/dev/null 2>&1
    }
    When call run_build_failure
    The status should be failure
  End

  It "sets BRIK_BUILD_STATUS to failed on failure"
    run_build_ctx_failure() {
      brik.use() { :; }
      build.run() { return 1; }
      local ctx
      ctx="$(context.create "build")" 2>/dev/null || ctx="$(mktemp)"
      stages.build "$ctx" >/dev/null 2>&1 || true
      grep "^BRIK_BUILD_STATUS=" "$ctx" | cut -d= -f2
    }
    When call run_build_ctx_failure
    The output should equal "failed"
  End

  It "logs stack name"
    run_build_log_stack() {
      brik.use() { :; }
      build.run() { return 0; }
      local ctx
      ctx="$(context.create "build")" 2>/dev/null || ctx="$(mktemp)"
      stages.build "$ctx"
    }
    When call run_build_log_stack
    The error should include "running build (stack=node)"
  End
End
