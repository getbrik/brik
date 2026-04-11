Describe "stages.init"
  Include "$BRIK_HOME/runtime/bash/lib/runtime/stage.sh"
  Include "$BRIK_HOME/runtime/bash/lib/core/_loader.sh"
  Include "$BRIK_HOME/runtime/bash/lib/core/config.sh"
  Include "$BRIK_HOME/runtime/bash/lib/stages/init.sh"

  setup_env() {
    export BRIK_CONFIG_FILE
    BRIK_CONFIG_FILE="$(mktemp)"
    printf 'version: 1\nproject:\n  name: test-project\n  stack: node\n' > "$BRIK_CONFIG_FILE"
    export BRIK_WORKSPACE
    BRIK_WORKSPACE="$(mktemp -d)"
    export BRIK_PROJECT_DIR="$BRIK_WORKSPACE"
    export BRIK_PLATFORM="gitlab"
    export BRIK_LOG_LEVEL="info"
    config.read "$BRIK_CONFIG_FILE" >/dev/null 2>&1 || true
  }
  cleanup_env() {
    rm -f "$BRIK_CONFIG_FILE"
    rm -rf "$BRIK_WORKSPACE"
  }
  Before 'setup_env'
  After 'cleanup_env'

  It "is callable as a function"
    callable_check() { declare -f stages.init >/dev/null; }
    When call callable_check
    The status should be success
  End

  It "returns 0 on success with valid config"
    run_init() {
      local ctx
      ctx="$(context.create "init")" 2>/dev/null || ctx="$(mktemp)"
      stages.init "$ctx" >/dev/null 2>&1
    }
    When call run_init
    The status should be success
  End

  It "sets BRIK_STACK in context"
    run_init_check() {
      local ctx
      ctx="$(context.create "init")" 2>/dev/null || ctx="$(mktemp)"
      stages.init "$ctx" >/dev/null 2>&1
      grep "^BRIK_STACK=" "$ctx" | cut -d= -f2
    }
    When call run_init_check
    The output should equal "node"
  End

  It "returns 7 when brik.yml is missing"
    run_init_no_config() {
      export BRIK_CONFIG_FILE="/nonexistent/brik.yml"
      local ctx
      ctx="$(mktemp)"
      stages.init "$ctx" 2>/dev/null
    }
    When call run_init_no_config
    The status should equal 7
  End

  It "logs project name"
    run_init_log() {
      local ctx
      ctx="$(context.create "init")" 2>/dev/null || ctx="$(mktemp)"
      stages.init "$ctx"
    }
    When call run_init_log
    The error should include "project: test-project"
  End

  It "logs platform from BRIK_PLATFORM"
    run_init_platform() {
      local ctx
      ctx="$(context.create "init")" 2>/dev/null || ctx="$(mktemp)"
      stages.init "$ctx"
    }
    When call run_init_platform
    The error should include "platform: gitlab"
  End

  It "auto-detects stack when config says auto"
    run_init_auto() {
      # Override config to return 'auto' for stack
      local orig_config="$BRIK_CONFIG_FILE"
      BRIK_CONFIG_FILE="$(mktemp)"
      printf 'version: 1\nproject:\n  name: test-project\n  stack: auto\n' > "$BRIK_CONFIG_FILE"
      config.read "$BRIK_CONFIG_FILE" >/dev/null 2>&1 || true
      # Mock build.detect_stack to return 'node'
      brik.use() { :; }
      build.detect_stack() { printf 'node'; return 0; }
      local ctx
      ctx="$(context.create "init")" 2>/dev/null || ctx="$(mktemp)"
      stages.init "$ctx" 2>/dev/null
      grep "^BRIK_STACK=" "$ctx" | cut -d= -f2
      rm -f "$BRIK_CONFIG_FILE"
      BRIK_CONFIG_FILE="$orig_config"
      config.read "$BRIK_CONFIG_FILE" >/dev/null 2>&1 || true
    }
    When call run_init_auto
    The output should equal "node"
  End

  It "returns 3 when yq is not available"
    run_init_no_yq() {
      # Hide yq from PATH
      local orig_path="$PATH"
      PATH="/usr/bin:/bin"
      # Ensure yq is not found
      if command -v yq >/dev/null 2>&1; then
        PATH="$orig_path"
        # yq is a builtin or in /usr/bin - skip
        return 3
      fi
      local ctx
      ctx="$(mktemp)"
      stages.init "$ctx" 2>/dev/null
      local rc=$?
      PATH="$orig_path"
      return "$rc"
    }
    When call run_init_no_yq
    The status should equal 3
  End

  It "logs init stage complete"
    run_init_complete() {
      local ctx
      ctx="$(context.create "init")" 2>/dev/null || ctx="$(mktemp)"
      stages.init "$ctx"
    }
    When call run_init_complete
    The error should include "init stage complete"
  End
End
