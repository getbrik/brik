Describe "stages.security"
  Include "$BRIK_HOME/runtime/bash/lib/runtime/stage.sh"
  Include "$BRIK_HOME/runtime/bash/lib/core/_loader.sh"
  Include "$BRIK_HOME/runtime/bash/lib/core/config.sh"
  Include "$BRIK_HOME/runtime/bash/lib/stages/security.sh"

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
    callable_check() { declare -f stages.security >/dev/null; }
    When call callable_check
    The status should be success
  End

  It "returns 0 (stub)"
    run_security() {
      local ctx
      ctx="$(context.create "security")" 2>/dev/null || ctx="$(mktemp)"
      stages.security "$ctx" >/dev/null 2>&1
    }
    When call run_security
    The status should be success
  End

  It "sets BRIK_SECURITY_STATUS to skipped"
    run_security_check() {
      local ctx
      ctx="$(context.create "security")" 2>/dev/null || ctx="$(mktemp)"
      stages.security "$ctx" >/dev/null 2>&1
      grep "^BRIK_SECURITY_STATUS=" "$ctx" | cut -d= -f2
    }
    When call run_security_check
    The output should equal "skipped"
  End
End
