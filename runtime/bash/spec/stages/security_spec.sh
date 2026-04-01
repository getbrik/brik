Describe "stages.security"
  Include "$BRIK_HOME/runtime/bash/lib/runtime/stage.sh"
  Include "$BRIK_HOME/runtime/bash/lib/core/_loader.sh"
  Include "$BRIK_HOME/runtime/bash/lib/core/config.sh"
  Include "$BRIK_HOME/runtime/bash/lib/stages/security.sh"

  setup_env() {
    export BRIK_CONFIG_FILE
    BRIK_CONFIG_FILE="$(mktemp)"
    cat > "$BRIK_CONFIG_FILE" <<'YAML'
version: 1
project:
  name: test
  stack: node
security:
  enabled: true
  severity_threshold: high
  dependency_scan: "true"
  secret_scan: "true"
  container_scan: "false"
YAML
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

  It "returns 0 when security.run succeeds"
    run_security() {
      brik.use() { :; }
      security.run() { return 0; }
      local ctx
      ctx="$(context.create "security")" 2>/dev/null || ctx="$(mktemp)"
      stages.security "$ctx" >/dev/null 2>&1
    }
    When call run_security
    The status should be success
  End

  It "sets BRIK_SECURITY_STATUS to success"
    run_security_ctx() {
      brik.use() { :; }
      security.run() { return 0; }
      local ctx
      ctx="$(context.create "security")" 2>/dev/null || ctx="$(mktemp)"
      stages.security "$ctx" >/dev/null 2>&1
      grep "^BRIK_SECURITY_STATUS=" "$ctx" | cut -d= -f2
    }
    When call run_security_ctx
    The output should equal "success"
  End

  It "sets BRIK_SECURITY_STATUS to failed when security.run fails"
    run_security_fail() {
      brik.use() { :; }
      security.run() { return 1; }
      local ctx
      ctx="$(context.create "security")" 2>/dev/null || ctx="$(mktemp)"
      stages.security "$ctx" >/dev/null 2>&1 || true
      grep "^BRIK_SECURITY_STATUS=" "$ctx" | cut -d= -f2
    }
    When call run_security_fail
    The output should equal "failed"
  End

  It "passes workspace and scan flags to security.run"
    run_security_args() {
      brik.use() { :; }
      security.run() { printf '%s ' "$@"; printf '\n'; return 0; }
      local ctx
      ctx="$(context.create "security")" 2>/dev/null || ctx="$(mktemp)"
      stages.security "$ctx" 2>/dev/null
    }
    When call run_security_args
    The output should include "$BRIK_WORKSPACE"
    The output should include "--dependency-scan true"
    The output should include "--secret-scan true"
    The output should include "--container-scan false"
    The output should include "--severity high"
  End

  It "exports security config vars"
    run_security_export() {
      brik.use() { :; }
      security.run() { return 0; }
      local ctx
      ctx="$(context.create "security")" 2>/dev/null || ctx="$(mktemp)"
      stages.security "$ctx" >/dev/null 2>&1
      printf '%s' "${BRIK_SECURITY_DEPENDENCY_SCAN:-}"
    }
    When call run_security_export
    The output should equal "true"
  End
End
