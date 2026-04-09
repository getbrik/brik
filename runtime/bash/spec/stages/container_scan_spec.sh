Describe "stages.container_scan"
  Include "$BRIK_HOME/runtime/bash/lib/runtime/stage.sh"
  Include "$BRIK_HOME/runtime/bash/lib/core/_loader.sh"
  Include "$BRIK_HOME/runtime/bash/lib/core/config.sh"
  Include "$BRIK_HOME/runtime/bash/lib/stages/container_scan.sh"

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
    unset BRIK_SECURITY_CONTAINER_IMAGE BRIK_SECURITY_CONTAINER_SEVERITY \
          BRIK_SECURITY_SEVERITY_THRESHOLD 2>/dev/null || true
  }
  Before 'setup_env'
  After 'cleanup_env'

  It "is callable as a function"
    callable_check() { declare -f stages.container_scan >/dev/null; }
    When call callable_check
    The status should be success
  End

  Describe "with no container image configured"
    setup_no_image() {
      cat > "$BRIK_CONFIG_FILE" <<'YAML'
version: 1
project:
  name: test
  stack: node
YAML
      config.read "$BRIK_CONFIG_FILE" >/dev/null 2>&1 || true
    }
    Before 'setup_no_image'

    It "returns 0 and status skipped"
      run_no_image() {
        local ctx
        ctx="$(context.create "container_scan")" 2>/dev/null || ctx="$(mktemp)"
        stages.container_scan "$ctx" >/dev/null 2>&1
        grep "^BRIK_CONTAINER_SCAN_STATUS=" "$ctx" | cut -d= -f2
      }
      When call run_no_image
      The output should equal "skipped"
    End
  End

  Describe "with container image configured"
    setup_container() {
      cat > "$BRIK_CONFIG_FILE" <<'YAML'
version: 1
project:
  name: test
  stack: node
security:
  container:
    image: myapp:latest
    severity: critical
YAML
      config.read "$BRIK_CONFIG_FILE" >/dev/null 2>&1 || true
    }
    Before 'setup_container'

    It "runs container scan and sets status to success"
      run_container() {
        security.container.run() { return 0; }
        local ctx
        ctx="$(context.create "container_scan")" 2>/dev/null || ctx="$(mktemp)"
        stages.container_scan "$ctx" >/dev/null 2>&1
        grep "^BRIK_CONTAINER_SCAN_STATUS=" "$ctx" | cut -d= -f2
      }
      When call run_container
      The output should equal "success"
    End

    It "sets status to failed when container scan fails"
      run_container_fail() {
        security.container.run() { return 1; }
        local ctx
        ctx="$(context.create "container_scan")" 2>/dev/null || ctx="$(mktemp)"
        stages.container_scan "$ctx" >/dev/null 2>&1 || true
        grep "^BRIK_CONTAINER_SCAN_STATUS=" "$ctx" | cut -d= -f2
      }
      When call run_container_fail
      The output should equal "failed"
    End

    It "passes image and severity to security.container.run"
      run_container_args() {
        security.container.run() { printf '%s ' "$@"; printf '\n'; return 0; }
        local ctx
        ctx="$(context.create "container_scan")" 2>/dev/null || ctx="$(mktemp)"
        stages.container_scan "$ctx" 2>/dev/null
      }
      When call run_container_args
      The output should include "--image myapp:latest"
      The output should include "--severity critical"
    End
  End

  Describe "with container image but no severity"
    setup_no_severity() {
      cat > "$BRIK_CONFIG_FILE" <<'YAML'
version: 1
project:
  name: test
  stack: node
security:
  container:
    image: myapp:latest
YAML
      config.read "$BRIK_CONFIG_FILE" >/dev/null 2>&1 || true
    }
    Before 'setup_no_severity'

    It "uses default severity threshold"
      run_default_severity() {
        security.container.run() { printf '%s ' "$@"; printf '\n'; return 0; }
        local ctx
        ctx="$(context.create "container_scan")" 2>/dev/null || ctx="$(mktemp)"
        stages.container_scan "$ctx" 2>/dev/null
      }
      When call run_default_severity
      The output should include "--severity high"
    End
  End
End
