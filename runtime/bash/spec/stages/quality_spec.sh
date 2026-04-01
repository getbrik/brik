Describe "stages.quality"
  Include "$BRIK_HOME/runtime/bash/lib/runtime/stage.sh"
  Include "$BRIK_HOME/runtime/bash/lib/core/_loader.sh"
  Include "$BRIK_HOME/runtime/bash/lib/core/config.sh"
  Include "$BRIK_HOME/runtime/bash/lib/stages/quality.sh"

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
    callable_check() { declare -f stages.quality >/dev/null; }
    When call callable_check
    The status should be success
  End

  It "returns 0 (stub)"
    run_quality() {
      local ctx
      ctx="$(context.create "quality")" 2>/dev/null || ctx="$(mktemp)"
      stages.quality "$ctx" >/dev/null 2>&1
    }
    When call run_quality
    The status should be success
  End

  It "sets BRIK_QUALITY_STATUS to skipped"
    run_quality_check() {
      local ctx
      ctx="$(context.create "quality")" 2>/dev/null || ctx="$(mktemp)"
      stages.quality "$ctx" >/dev/null 2>&1
      grep "^BRIK_QUALITY_STATUS=" "$ctx" | cut -d= -f2
    }
    When call run_quality_check
    The output should equal "skipped"
  End
End
