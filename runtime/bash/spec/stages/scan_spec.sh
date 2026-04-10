Describe "stages.scan"
  Include "$BRIK_HOME/runtime/bash/lib/runtime/stage.sh"
  Include "$BRIK_HOME/runtime/bash/lib/core/_loader.sh"
  Include "$BRIK_HOME/runtime/bash/lib/core/config.sh"
  Include "$BRIK_HOME/runtime/bash/lib/stages/scan.sh"

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
    unset BRIK_SECURITY_DEPS_TOOL BRIK_SECURITY_DEPS_COMMAND \
          BRIK_SECURITY_DEPS_SEVERITY BRIK_SECURITY_SECRETS_TOOL \
          BRIK_SECURITY_SECRETS_COMMAND BRIK_SECURITY_SEVERITY_THRESHOLD \
          2>/dev/null || true
  }
  Before 'setup_env'
  After 'cleanup_env'

  It "is callable as a function"
    callable_check() { declare -f stages.scan >/dev/null; }
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

    It "defaults to osv-scanner and gitleaks and returns success"
      run_scan_defaults() {
        security.deps.run() { return 0; }
        security.secret_scan.run() { return 0; }
        local ctx
        ctx="$(context.create "scan")" 2>/dev/null || ctx="$(mktemp)"
        stages.scan "$ctx" >/dev/null 2>&1
        grep "^BRIK_SCAN_STATUS=" "$ctx" | cut -d= -f2
      }
      When call run_scan_defaults
      The output should equal "success"
    End
  End

  Describe "with deps configured"
    setup_deps() {
      cat > "$BRIK_CONFIG_FILE" <<'YAML'
version: 1
project:
  name: test
  stack: node
security:
  deps:
    severity: high
YAML
      config.read "$BRIK_CONFIG_FILE" >/dev/null 2>&1 || true
    }
    Before 'setup_deps'

    It "runs dependency scan and sets status to success"
      run_deps() {
        security.deps.run() { return 0; }
        security.secret_scan.run() { return 0; }
        local ctx
        ctx="$(context.create "scan")" 2>/dev/null || ctx="$(mktemp)"
        stages.scan "$ctx" >/dev/null 2>&1
        grep "^BRIK_SCAN_STATUS=" "$ctx" | cut -d= -f2
      }
      When call run_deps
      The output should equal "success"
    End

    It "sets status to failed when deps scan fails"
      run_deps_fail() {
        security.deps.run() { return 1; }
        security.secret_scan.run() { return 0; }
        local ctx
        ctx="$(context.create "scan")" 2>/dev/null || ctx="$(mktemp)"
        stages.scan "$ctx" >/dev/null 2>&1 || true
        grep "^BRIK_SCAN_STATUS=" "$ctx" | cut -d= -f2
      }
      When call run_deps_fail
      The output should equal "failed"
    End
  End

  Describe "with secrets configured"
    setup_secrets() {
      cat > "$BRIK_CONFIG_FILE" <<'YAML'
version: 1
project:
  name: test
  stack: node
security:
  secrets:
    tool: gitleaks
YAML
      config.read "$BRIK_CONFIG_FILE" >/dev/null 2>&1 || true
    }
    Before 'setup_secrets'

    It "runs secret scan and sets status to success"
      run_secrets() {
        security.deps.run() { return 0; }
        security.secret_scan.run() { return 0; }
        local ctx
        ctx="$(context.create "scan")" 2>/dev/null || ctx="$(mktemp)"
        stages.scan "$ctx" >/dev/null 2>&1
        grep "^BRIK_SCAN_STATUS=" "$ctx" | cut -d= -f2
      }
      When call run_secrets
      The output should equal "success"
    End

    It "sets status to failed when secret scan fails"
      run_secrets_fail() {
        security.deps.run() { return 0; }
        security.secret_scan.run() { return 1; }
        local ctx
        ctx="$(context.create "scan")" 2>/dev/null || ctx="$(mktemp)"
        stages.scan "$ctx" >/dev/null 2>&1 || true
        grep "^BRIK_SCAN_STATUS=" "$ctx" | cut -d= -f2
      }
      When call run_secrets_fail
      The output should equal "failed"
    End
  End

  Describe "with deps and secrets configured"
    setup_both() {
      cat > "$BRIK_CONFIG_FILE" <<'YAML'
version: 1
project:
  name: test
  stack: node
security:
  deps:
    severity: high
  secrets:
    tool: gitleaks
YAML
      config.read "$BRIK_CONFIG_FILE" >/dev/null 2>&1 || true
    }
    Before 'setup_both'

    It "runs both scans"
      run_both() {
        security.deps.run() { return 0; }
        security.secret_scan.run() { return 0; }
        local ctx
        ctx="$(context.create "scan")" 2>/dev/null || ctx="$(mktemp)"
        stages.scan "$ctx" >/dev/null 2>&1
        grep "^BRIK_SCAN_STATUS=" "$ctx" | cut -d= -f2
      }
      When call run_both
      The output should equal "success"
    End

    It "fails if any scan fails"
      run_both_fail() {
        security.deps.run() { return 0; }
        security.secret_scan.run() { return 1; }
        local ctx
        ctx="$(context.create "scan")" 2>/dev/null || ctx="$(mktemp)"
        stages.scan "$ctx" >/dev/null 2>&1 || true
        grep "^BRIK_SCAN_STATUS=" "$ctx" | cut -d= -f2
      }
      When call run_both_fail
      The output should equal "failed"
    End
  End
End

Describe "_brik.install_deps (scan mode)"
  Include "$BRIK_HOME/runtime/bash/lib/runtime/stage.sh"
  Include "$BRIK_HOME/runtime/bash/lib/core/_loader.sh"
  Include "$BRIK_HOME/runtime/bash/lib/stages/scan.sh"

  setup_deps_env() {
    export BRIK_LOG_DIR
    BRIK_LOG_DIR="$(mktemp -d)"
    DEPS_WS="$(mktemp -d)"
    MOCK_BIN="$(mktemp -d)"
    MOCK_LOG="${DEPS_WS}/mock.log"
    ORIG_PATH="$PATH"
  }
  cleanup_deps_env() {
    export PATH="$ORIG_PATH"
    rm -rf "$BRIK_LOG_DIR" "$DEPS_WS" "$MOCK_BIN"
    unset BRIK_BUILD_STACK
  }
  Before 'setup_deps_env'
  After 'cleanup_deps_env'

  Describe "node stack"
    It "runs npm ci when node_modules is missing"
      run_node_install() {
        export BRIK_BUILD_STACK="node"
        cat > "${MOCK_BIN}/npm" << MOCKEOF
#!/usr/bin/env bash
printf 'npm %s\n' "\$*" >> "$MOCK_LOG"
exit 0
MOCKEOF
        chmod +x "${MOCK_BIN}/npm"
        export PATH="${MOCK_BIN}:${ORIG_PATH}"
        _brik.install_deps "$DEPS_WS" scan 2>/dev/null
        grep -q "npm ci" "$MOCK_LOG"
      }
      When call run_node_install
      The status should be success
    End

    It "skips npm ci when node_modules exists"
      run_node_skip() {
        export BRIK_BUILD_STACK="node"
        mkdir -p "${DEPS_WS}/node_modules"
        cat > "${MOCK_BIN}/npm" << 'MOCKEOF'
#!/usr/bin/env bash
echo "npm should not be called" >&2
exit 1
MOCKEOF
        chmod +x "${MOCK_BIN}/npm"
        export PATH="${MOCK_BIN}:${ORIG_PATH}"
        _brik.install_deps "$DEPS_WS" scan 2>/dev/null
      }
      When call run_node_skip
      The status should be success
    End
  End

  Describe "python stack"
    It "installs from pyproject.toml"
      run_python_pyproject() {
        export BRIK_BUILD_STACK="python"
        printf '[project]\nname = "test"\n' > "${DEPS_WS}/pyproject.toml"
        cat > "${MOCK_BIN}/pip" << MOCKEOF
#!/usr/bin/env bash
printf 'pip %s\n' "\$*" >> "$MOCK_LOG"
exit 0
MOCKEOF
        chmod +x "${MOCK_BIN}/pip"
        export PATH="${MOCK_BIN}:${ORIG_PATH}"
        _brik.install_deps "$DEPS_WS" scan 2>/dev/null
        grep -q 'pip install .' "$MOCK_LOG"
      }
      When call run_python_pyproject
      The status should be success
    End

    It "installs from requirements.txt"
      run_python_req() {
        export BRIK_BUILD_STACK="python"
        rm -f "${DEPS_WS}/pyproject.toml"
        printf 'requests\n' > "${DEPS_WS}/requirements.txt"
        cat > "${MOCK_BIN}/pip" << MOCKEOF
#!/usr/bin/env bash
printf 'pip %s\n' "\$*" >> "$MOCK_LOG"
exit 0
MOCKEOF
        chmod +x "${MOCK_BIN}/pip"
        export PATH="${MOCK_BIN}:${ORIG_PATH}"
        _brik.install_deps "$DEPS_WS" scan 2>/dev/null
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
        _brik.install_deps "$DEPS_WS" scan 2>/dev/null
        [[ ! -f "$MOCK_LOG" ]]
      }
      When call run_python_noop
      The status should be success
    End
  End

  Describe "unknown stack"
    It "does nothing for unrecognized stack"
      run_unknown_stack() {
        export BRIK_BUILD_STACK="java"
        rm -f "$MOCK_LOG"
        _brik.install_deps "$DEPS_WS" scan 2>/dev/null
        [[ ! -f "$MOCK_LOG" ]]
      }
      When call run_unknown_stack
      The status should be success
    End

    It "does nothing when BRIK_BUILD_STACK is empty"
      run_empty_stack() {
        unset BRIK_BUILD_STACK
        rm -f "$MOCK_LOG"
        _brik.install_deps "$DEPS_WS" scan 2>/dev/null
        [[ ! -f "$MOCK_LOG" ]]
      }
      When call run_empty_stack
      The status should be success
    End
  End
End
