Describe "stages.build"
  Include "$BRIK_PIPELINE_LIB/logging.sh"
  Include "$BRIK_PIPELINE_LIB/tools.sh"
  Include "$BRIK_HOME/lib/pipeline/stage.sh"
  Include "$BRIK_HOME/lib/pipeline/loader.sh"
  Include "$BRIK_HOME/lib/transverse/config.sh"
  Include "$BRIK_HOME/lib/stages/build.sh"

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
    callable_check() { declare -f stages.build >/dev/null; }
    When call callable_check
    The status should be success
  End

  It "returns 0 when the stack build fn succeeds"
    run_build_success() {
      brik.use() { :; }
      stacks.node.build() { return 0; }
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
      stacks.node.build() { return 0; }
      local ctx
      ctx="$(context.create "build")" 2>/dev/null || ctx="$(mktemp)"
      stages.build "$ctx" >/dev/null 2>&1
      grep "^BRIK_BUILD_STATUS=" "$ctx" | cut -d= -f2
    }
    When call run_build_ctx_success
    The output should equal "success"
  End

  It "returns non-zero when the stack build fn fails"
    run_build_failure() {
      brik.use() { :; }
      stacks.node.build() { return 1; }
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
      stacks.node.build() { return 1; }
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
      stacks.node.build() { return 0; }
      local ctx
      ctx="$(context.create "build")" 2>/dev/null || ctx="$(mktemp)"
      stages.build "$ctx"
    }
    When call run_build_log_stack
    The error should include "running build (stack=node)"
  End

  It "calls config.export_build_vars to export BRIK_BUILD_STACK"
    run_build_check_export() {
      brik.use() { :; }
      stacks.node.build() { return 0; }
      local ctx
      ctx="$(context.create "build")" 2>/dev/null || ctx="$(mktemp)"
      stages.build "$ctx" >/dev/null 2>&1
      printf '%s' "${BRIK_BUILD_STACK:-}"
    }
    When call run_build_check_export
    The output should equal "node"
  End

  It "runs build.command override instead of the stack module"
    run_build_override() {
      cat > "$BRIK_CONFIG_FILE" <<'YAML'
version: 1
project:
  name: test
  stack: node
build:
  command: "printf 'override-ran'"
YAML
      config.read "$BRIK_CONFIG_FILE" >/dev/null 2>&1 || true
      brik.use() { :; }
      local ctx
      ctx="$(context.create "build")" 2>/dev/null || ctx="$(mktemp)"
      stages.build "$ctx" 2>/dev/null
    }
    When call run_build_override
    The output should include "override-ran"
  End

  It "returns config error when stack module does not provide a build fn"
    run_build_missing_fn() {
      brik.use() { :; }
      unset -f stacks.node.build 2>/dev/null
      local ctx
      ctx="$(context.create "build")" 2>/dev/null || ctx="$(mktemp)"
      stages.build "$ctx" 2>/dev/null
      local rc=$?
      printf '%s' "$rc"
    }
    When call run_build_missing_fn
    The output should equal "7"
  End

  Describe "with java stack"
    setup_java() {
      cat > "$BRIK_CONFIG_FILE" <<'YAML'
version: 1
project:
  name: test
  stack: java
YAML
      config.read "$BRIK_CONFIG_FILE" >/dev/null 2>&1 || true
    }
    Before 'setup_java'

    It "loads java stack module"
      run_build_java() {
        local loaded_modules=""
        brik.use() { loaded_modules="${loaded_modules} $1"; }
        stacks.java.build() { return 0; }
        local ctx
        ctx="$(context.create "build")" 2>/dev/null || ctx="$(mktemp)"
        stages.build "$ctx" >/dev/null 2>&1
        printf '%s' "$loaded_modules"
      }
      When call run_build_java
      The output should include "stacks.java"
    End
  End
End
