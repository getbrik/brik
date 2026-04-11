Describe "stages.lint"
  Include "$BRIK_HOME/runtime/bash/lib/runtime/stage.sh"
  Include "$BRIK_HOME/runtime/bash/lib/core/_loader.sh"
  Include "$BRIK_HOME/runtime/bash/lib/core/config.sh"
  Include "$BRIK_HOME/runtime/bash/lib/core/quality.sh"
  Include "$BRIK_HOME/runtime/bash/lib/stages/lint.sh"

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
    unset BRIK_QUALITY_LINT_TOOL BRIK_QUALITY_FORMAT_TOOL \
          BRIK_QUALITY_TYPE_CHECK_TOOL BRIK_QUALITY_LINT_COMMAND \
          BRIK_QUALITY_FORMAT_COMMAND BRIK_QUALITY_TYPE_CHECK_COMMAND \
          BRIK_QUALITY_LINT_FIX BRIK_QUALITY_LINT_CONFIG \
          BRIK_LINT_ENABLED 2>/dev/null || true
  }
  Before 'setup_env'
  After 'cleanup_env'

  It "is callable as a function"
    callable_check() { declare -f stages.lint >/dev/null; }
    When call callable_check
    The status should be success
  End

  Describe "with no lint checks configured"
    setup_no_checks() {
      cat > "$BRIK_CONFIG_FILE" <<'YAML'
version: 1
project:
  name: test
  stack: auto
YAML
      config.read "$BRIK_CONFIG_FILE" >/dev/null 2>&1 || true
    }
    Before 'setup_no_checks'

    It "returns 0 and status skipped"
      run_lint_no_checks() {
        brik.use() { :; }
        local ctx
        ctx="$(context.create "lint")" 2>/dev/null || ctx="$(mktemp)"
        stages.lint "$ctx" >/dev/null 2>&1
        grep "^BRIK_LINT_STATUS=" "$ctx" | cut -d= -f2
      }
      When call run_lint_no_checks
      The output should equal "skipped"
    End
  End

  Describe "with lint configured"
    setup_lint() {
      cat > "$BRIK_CONFIG_FILE" <<'YAML'
version: 1
project:
  name: test
  stack: node
quality:
  lint:
    enabled: true
    tool: eslint
    config: .eslintrc.json
    fix: "true"
YAML
      config.read "$BRIK_CONFIG_FILE" >/dev/null 2>&1 || true
    }
    Before 'setup_lint'

    It "runs lint check and sets status to success"
      run_lint() {
        brik.use() { :; }
        quality.lint.run() { return 0; }
        local ctx
        ctx="$(context.create "lint")" 2>/dev/null || ctx="$(mktemp)"
        stages.lint "$ctx" >/dev/null 2>&1
        grep "^BRIK_LINT_STATUS=" "$ctx" | cut -d= -f2
      }
      When call run_lint
      The output should equal "success"
    End

    It "sets status to failed when lint fails"
      run_lint_fail() {
        brik.use() { :; }
        quality.lint.run() { return 1; }
        local ctx
        ctx="$(context.create "lint")" 2>/dev/null || ctx="$(mktemp)"
        stages.lint "$ctx" >/dev/null 2>&1 || true
        grep "^BRIK_LINT_STATUS=" "$ctx" | cut -d= -f2
      }
      When call run_lint_fail
      The output should equal "failed"
    End

    It "logs lint checks being run"
      run_lint_log() {
        brik.use() { :; }
        quality.lint.run() { return 0; }
        local ctx
        ctx="$(context.create "lint")" 2>/dev/null || ctx="$(mktemp)"
        stages.lint "$ctx"
      }
      When call run_lint_log
      The error should include "running quality check: lint"
    End
  End

  Describe "with lint disabled"
    setup_disabled() {
      cat > "$BRIK_CONFIG_FILE" <<'YAML'
version: 1
project:
  name: test
  stack: node
quality:
  lint:
    enabled: false
YAML
      config.read "$BRIK_CONFIG_FILE" >/dev/null 2>&1 || true
    }
    Before 'setup_disabled'

    It "skips when lint is disabled"
      run_lint_disabled() {
        local ctx
        ctx="$(context.create "lint")" 2>/dev/null || ctx="$(mktemp)"
        stages.lint "$ctx" >/dev/null 2>&1
        grep "^BRIK_LINT_STATUS=" "$ctx" | cut -d= -f2
      }
      When call run_lint_disabled
      The output should equal "skipped"
    End

    It "logs that lint is disabled"
      run_lint_disabled_log() {
        local ctx
        ctx="$(context.create "lint")" 2>/dev/null || ctx="$(mktemp)"
        stages.lint "$ctx"
      }
      When call run_lint_disabled_log
      The error should include "lint disabled"
    End
  End

  Describe "with format configured"
    setup_format() {
      cat > "$BRIK_CONFIG_FILE" <<'YAML'
version: 1
project:
  name: test
  stack: node
quality:
  enabled: true
  format:
    tool: prettier
YAML
      config.read "$BRIK_CONFIG_FILE" >/dev/null 2>&1 || true
    }
    Before 'setup_format'

    It "runs format check and sets status to success"
      run_format() {
        brik.use() { :; }
        quality.format.run() { return 0; }
        local ctx
        ctx="$(context.create "lint")" 2>/dev/null || ctx="$(mktemp)"
        stages.lint "$ctx" >/dev/null 2>&1
        grep "^BRIK_LINT_STATUS=" "$ctx" | cut -d= -f2
      }
      When call run_format
      The output should equal "success"
    End
  End

  Describe "with type_check configured"
    setup_typecheck() {
      cat > "$BRIK_CONFIG_FILE" <<'YAML'
version: 1
project:
  name: test
  stack: node
quality:
  enabled: true
  type_check:
    tool: tsc
YAML
      config.read "$BRIK_CONFIG_FILE" >/dev/null 2>&1 || true
    }
    Before 'setup_typecheck'

    It "runs type_check check"
      run_typecheck() {
        brik.use() { :; }
        quality.type_check.run() { return 0; }
        local ctx
        ctx="$(context.create "lint")" 2>/dev/null || ctx="$(mktemp)"
        stages.lint "$ctx" >/dev/null 2>&1
        grep "^BRIK_LINT_STATUS=" "$ctx" | cut -d= -f2
      }
      When call run_typecheck
      The output should equal "success"
    End
  End

  Describe "with multiple checks configured"
    setup_multi() {
      cat > "$BRIK_CONFIG_FILE" <<'YAML'
version: 1
project:
  name: test
  stack: node
quality:
  lint:
    enabled: true
    tool: eslint
  format:
    tool: prettier
YAML
      config.read "$BRIK_CONFIG_FILE" >/dev/null 2>&1 || true
    }
    Before 'setup_multi'

    It "runs all configured checks"
      run_multi() {
        brik.use() { :; }
        quality.lint.run() { return 0; }
        quality.format.run() { return 0; }
        local ctx
        ctx="$(context.create "lint")" 2>/dev/null || ctx="$(mktemp)"
        stages.lint "$ctx" >/dev/null 2>&1
        grep "^BRIK_LINT_STATUS=" "$ctx" | cut -d= -f2
      }
      When call run_multi
      The output should equal "success"
    End

    It "fails if any check fails"
      run_multi_fail() {
        brik.use() { :; }
        quality.lint.run() { return 0; }
        quality.format.run() { return 1; }
        local ctx
        ctx="$(context.create "lint")" 2>/dev/null || ctx="$(mktemp)"
        stages.lint "$ctx" >/dev/null 2>&1 || true
        grep "^BRIK_LINT_STATUS=" "$ctx" | cut -d= -f2
      }
      When call run_multi_fail
      The output should equal "failed"
    End
  End
End

Describe "_brik.install_deps (dev mode)"
  Include "$BRIK_HOME/runtime/bash/lib/runtime/stage.sh"
  Include "$BRIK_HOME/runtime/bash/lib/core/_loader.sh"
  Include "$BRIK_HOME/runtime/bash/lib/stages/lint.sh"
  Include "$BRIK_HOME/runtime/bash/spec/support/mock_helper.sh"

  setup_deps_env() {
    mock.setup
    DEPS_WS="$(mktemp -d)"
    MOCK_LOG="${DEPS_WS}/mock.log"
  }
  cleanup_deps_env() {
    mock.cleanup
    rm -rf "$DEPS_WS"
    unset BRIK_BUILD_STACK
  }
  Before 'setup_deps_env'
  After 'cleanup_deps_env'

  Describe "node stack"
    It "runs npm ci when node_modules is missing"
      run_node_install() {
        export BRIK_BUILD_STACK="node"
        mock.create_logging "npm" "$MOCK_LOG"
        mock.activate
        _brik.install_deps "$DEPS_WS" dev 2>/dev/null
        grep -q "npm ci" "$MOCK_LOG"
      }
      When call run_node_install
      The status should be success
    End

    It "skips npm ci when node_modules exists"
      run_node_skip() {
        export BRIK_BUILD_STACK="node"
        mkdir -p "${DEPS_WS}/node_modules"
        mock.create_exit "npm" 1
        mock.activate
        _brik.install_deps "$DEPS_WS" dev 2>/dev/null
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
        mock.create_logging "pip" "$MOCK_LOG"
        mock.activate
        _brik.install_deps "$DEPS_WS" dev 2>/dev/null
        grep -q 'pip install -e' "$MOCK_LOG"
      }
      When call run_python_pyproject
      The status should be success
    End

    It "installs from requirements-dev.txt"
      run_python_reqdev() {
        export BRIK_BUILD_STACK="python"
        rm -f "${DEPS_WS}/pyproject.toml"
        printf 'pytest\n' > "${DEPS_WS}/requirements-dev.txt"
        mock.create_logging "pip" "$MOCK_LOG"
        mock.activate
        _brik.install_deps "$DEPS_WS" dev 2>/dev/null
        grep -q 'pip install -r requirements-dev.txt' "$MOCK_LOG"
      }
      When call run_python_reqdev
      The status should be success
    End

    It "does nothing when no python project files exist"
      run_python_noop() {
        export BRIK_BUILD_STACK="python"
        rm -f "${DEPS_WS}/pyproject.toml" "${DEPS_WS}/requirements-dev.txt"
        rm -f "$MOCK_LOG"
        _brik.install_deps "$DEPS_WS" dev 2>/dev/null
        [[ ! -f "$MOCK_LOG" ]]
      }
      When call run_python_noop
      The status should be success
    End
  End

  Describe "rust stack"
    It "installs clippy when missing"
      run_rust_clippy() {
        export BRIK_BUILD_STACK="rust"
        mock.create_logging "rustup" "$MOCK_LOG"
        export PATH="${MOCK_BIN}:/usr/bin:/bin"
        _brik.install_deps "$DEPS_WS" dev 2>/dev/null
        grep -q "rustup component add clippy" "$MOCK_LOG"
      }
      When call run_rust_clippy
      The status should be success
    End

    It "installs rustfmt when missing"
      run_rust_rustfmt() {
        export BRIK_BUILD_STACK="rust"
        mock.create_logging "rustup" "$MOCK_LOG"
        export PATH="${MOCK_BIN}:/usr/bin:/bin"
        _brik.install_deps "$DEPS_WS" dev 2>/dev/null
        grep -q "rustup component add rustfmt" "$MOCK_LOG"
      }
      When call run_rust_rustfmt
      The status should be success
    End

    It "skips when rustup is not available"
      run_rust_no_rustup() {
        export BRIK_BUILD_STACK="rust"
        rm -f "$MOCK_LOG"
        export PATH="${MOCK_BIN}:/usr/bin:/bin"
        _brik.install_deps "$DEPS_WS" dev 2>/dev/null
        [[ ! -f "$MOCK_LOG" ]]
      }
      When call run_rust_no_rustup
      The status should be success
    End
  End

  Describe "unknown stack"
    It "does nothing for unrecognized stack"
      run_unknown_stack() {
        export BRIK_BUILD_STACK="go"
        rm -f "$MOCK_LOG"
        _brik.install_deps "$DEPS_WS" dev 2>/dev/null
        [[ ! -f "$MOCK_LOG" ]]
      }
      When call run_unknown_stack
      The status should be success
    End

    It "does nothing when BRIK_BUILD_STACK is empty"
      run_empty_stack() {
        unset BRIK_BUILD_STACK
        rm -f "$MOCK_LOG"
        _brik.install_deps "$DEPS_WS" dev 2>/dev/null
        [[ ! -f "$MOCK_LOG" ]]
      }
      When call run_empty_stack
      The status should be success
    End
  End
End
