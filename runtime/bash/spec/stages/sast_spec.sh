Describe "stages.sast"
  Include "$BRIK_HOME/runtime/bash/lib/runtime/stage.sh"
  Include "$BRIK_HOME/runtime/bash/lib/core/_loader.sh"
  Include "$BRIK_HOME/runtime/bash/lib/core/config.sh"
  Include "$BRIK_HOME/runtime/bash/lib/core/security.sh"
  Include "$BRIK_HOME/runtime/bash/lib/stages/sast.sh"

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
    unset BRIK_SECURITY_SAST_TOOL BRIK_SECURITY_SAST_COMMAND \
          BRIK_SECURITY_SAST_RULESET BRIK_SECURITY_LICENSE_ALLOWED \
          BRIK_SECURITY_LICENSE_DENIED BRIK_SECURITY_IAC_TOOL \
          BRIK_SECURITY_IAC_COMMAND BRIK_SECURITY_SEVERITY_THRESHOLD \
          2>/dev/null || true
  }
  Before 'setup_env'
  After 'cleanup_env'

  It "is callable as a function"
    callable_check() { declare -f stages.sast >/dev/null; }
    When call callable_check
    The status should be success
  End

  Describe "with default tools (no explicit security config)"
    setup_no_scans() {
      cat > "$BRIK_CONFIG_FILE" <<'YAML'
version: 1
project:
  name: test
  stack: node
YAML
      config.read "$BRIK_CONFIG_FILE" >/dev/null 2>&1 || true
    }
    Before 'setup_no_scans'

    It "defaults to semgrep and returns success"
      run_sast_defaults() {
        security.sast.run() { return 0; }
        local ctx
        ctx="$(context.create "sast")" 2>/dev/null || ctx="$(mktemp)"
        stages.sast "$ctx" >/dev/null 2>&1
        grep "^BRIK_SAST_STATUS=" "$ctx" | cut -d= -f2
      }
      When call run_sast_defaults
      The output should equal "success"
    End
  End

  Describe "with SAST configured"
    setup_sast() {
      cat > "$BRIK_CONFIG_FILE" <<'YAML'
version: 1
project:
  name: test
  stack: node
security:
  sast:
    tool: semgrep
    ruleset: p/security-audit
YAML
      config.read "$BRIK_CONFIG_FILE" >/dev/null 2>&1 || true
    }
    Before 'setup_sast'

    It "runs SAST scan and sets status to success"
      run_sast() {
        brik.use() { :; }
        security.sast.run() { return 0; }
        local ctx
        ctx="$(context.create "sast")" 2>/dev/null || ctx="$(mktemp)"
        stages.sast "$ctx" >/dev/null 2>&1
        grep "^BRIK_SAST_STATUS=" "$ctx" | cut -d= -f2
      }
      When call run_sast
      The output should equal "success"
    End

    It "sets status to failed when SAST fails"
      run_sast_fail() {
        brik.use() { :; }
        security.sast.run() { return 1; }
        local ctx
        ctx="$(context.create "sast")" 2>/dev/null || ctx="$(mktemp)"
        stages.sast "$ctx" >/dev/null 2>&1 || true
        grep "^BRIK_SAST_STATUS=" "$ctx" | cut -d= -f2
      }
      When call run_sast_fail
      The output should equal "failed"
    End
  End

  Describe "with license configured"
    setup_license() {
      cat > "$BRIK_CONFIG_FILE" <<'YAML'
version: 1
project:
  name: test
  stack: node
security:
  license:
    allowed: MIT,Apache-2.0
YAML
      config.read "$BRIK_CONFIG_FILE" >/dev/null 2>&1 || true
    }
    Before 'setup_license'

    It "runs license scan and sets status to success"
      run_license() {
        brik.use() { :; }
        security.sast.run() { return 0; }
        security.license.run() { return 0; }
        local ctx
        ctx="$(context.create "sast")" 2>/dev/null || ctx="$(mktemp)"
        stages.sast "$ctx" >/dev/null 2>&1
        grep "^BRIK_SAST_STATUS=" "$ctx" | cut -d= -f2
      }
      When call run_license
      The output should equal "success"
    End
  End

  Describe "with IaC configured"
    setup_iac() {
      cat > "$BRIK_CONFIG_FILE" <<'YAML'
version: 1
project:
  name: test
  stack: node
security:
  iac:
    tool: checkov
YAML
      config.read "$BRIK_CONFIG_FILE" >/dev/null 2>&1 || true
    }
    Before 'setup_iac'

    It "runs IaC scan and sets status to success"
      run_iac() {
        brik.use() { :; }
        security.sast.run() { return 0; }
        security.iac.run() { return 0; }
        local ctx
        ctx="$(context.create "sast")" 2>/dev/null || ctx="$(mktemp)"
        stages.sast "$ctx" >/dev/null 2>&1
        grep "^BRIK_SAST_STATUS=" "$ctx" | cut -d= -f2
      }
      When call run_iac
      The output should equal "success"
    End
  End

  Describe "with multiple scans configured"
    setup_multi() {
      cat > "$BRIK_CONFIG_FILE" <<'YAML'
version: 1
project:
  name: test
  stack: node
security:
  sast:
    tool: semgrep
  license:
    allowed: MIT
YAML
      config.read "$BRIK_CONFIG_FILE" >/dev/null 2>&1 || true
    }
    Before 'setup_multi'

    It "runs all configured scans"
      run_multi() {
        brik.use() { :; }
        security.sast.run() { return 0; }
        security.license.run() { return 0; }
        local ctx
        ctx="$(context.create "sast")" 2>/dev/null || ctx="$(mktemp)"
        stages.sast "$ctx" >/dev/null 2>&1
        grep "^BRIK_SAST_STATUS=" "$ctx" | cut -d= -f2
      }
      When call run_multi
      The output should equal "success"
    End

    It "fails if any scan fails"
      run_multi_fail() {
        brik.use() { :; }
        security.sast.run() { return 0; }
        security.license.run() { return 1; }
        local ctx
        ctx="$(context.create "sast")" 2>/dev/null || ctx="$(mktemp)"
        stages.sast "$ctx" >/dev/null 2>&1 || true
        grep "^BRIK_SAST_STATUS=" "$ctx" | cut -d= -f2
      }
      When call run_multi_fail
      The output should equal "failed"
    End
  End
End
