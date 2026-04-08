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

Describe "_security.install_deps"
  Include "$BRIK_HOME/runtime/bash/lib/runtime/stage.sh"
  Include "$BRIK_HOME/runtime/bash/lib/stages/security.sh"

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
        _security.install_deps "$DEPS_WS" 2>/dev/null
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
        _security.install_deps "$DEPS_WS" 2>/dev/null
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
        _security.install_deps "$DEPS_WS" 2>/dev/null
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
        _security.install_deps "$DEPS_WS" 2>/dev/null
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
        _security.install_deps "$DEPS_WS" 2>/dev/null
        [[ ! -f "$MOCK_LOG" ]]
      }
      When call run_python_noop
      The status should be success
    End
  End

  Describe "java stack"
    It "does nothing (security tools work with lock files)"
      run_java_noop() {
        export BRIK_BUILD_STACK="java"
        rm -f "$MOCK_LOG"
        _security.install_deps "$DEPS_WS" 2>/dev/null
        [[ ! -f "$MOCK_LOG" ]]
      }
      When call run_java_noop
      The status should be success
    End
  End

  Describe "unknown stack"
    It "does nothing for unrecognized stack"
      run_unknown_stack() {
        export BRIK_BUILD_STACK="go"
        rm -f "$MOCK_LOG"
        _security.install_deps "$DEPS_WS" 2>/dev/null
        [[ ! -f "$MOCK_LOG" ]]
      }
      When call run_unknown_stack
      The status should be success
    End

    It "does nothing when BRIK_BUILD_STACK is empty"
      run_empty_stack() {
        unset BRIK_BUILD_STACK
        rm -f "$MOCK_LOG"
        _security.install_deps "$DEPS_WS" 2>/dev/null
        [[ ! -f "$MOCK_LOG" ]]
      }
      When call run_empty_stack
      The status should be success
    End
  End
End
