Describe "stages.lint"
  Include "$BRIK_HOME/lib/pipeline/stage.sh"
  Include "$BRIK_HOME/lib/pipeline/loader.sh"
  Include "$BRIK_HOME/lib/pipeline/report.sh"
  Include "$BRIK_HOME/lib/transverse/config.sh"
  Include "$BRIK_HOME/lib/transverse/csv.sh"
  Include "$BRIK_HOME/lib/stages/verify/verify.sh"
  Include "$BRIK_HOME/lib/stages/lint.sh"

  setup_env() {
    export BRIK_CONFIG_FILE
    BRIK_CONFIG_FILE="$(mktemp)"
    printf 'version: 1\nproject:\n  name: test\n  stack: node\n' > "$BRIK_CONFIG_FILE"
    export BRIK_WORKSPACE
    BRIK_WORKSPACE="$(mktemp -d)"
    export BRIK_LOG_DIR
    BRIK_LOG_DIR="$(mktemp -d)"
    export BRIK_PROJECT_DIR="$BRIK_WORKSPACE"
    export BRIK_PLATFORM="gitlab"
    export BRIK_RUN_ID="lint-spec-fixture"
    config.read "$BRIK_CONFIG_FILE" >/dev/null 2>&1 || true
    report.init >/dev/null 2>&1 || true
  }
  cleanup_env() {
    rm -f "$BRIK_CONFIG_FILE"
    rm -rf "$BRIK_WORKSPACE" "$BRIK_LOG_DIR"
    unset BRIK_QUALITY_LINT_TOOL BRIK_QUALITY_FORMAT_TOOL \
          BRIK_QUALITY_TYPE_CHECK_TOOL BRIK_QUALITY_LINT_COMMAND \
          BRIK_QUALITY_FORMAT_COMMAND BRIK_QUALITY_TYPE_CHECK_COMMAND \
          BRIK_QUALITY_LINT_FIX BRIK_QUALITY_LINT_CONFIG \
          BRIK_LINT_ENABLED BRIK_RUN_ID 2>/dev/null || true
  }
  Before 'setup_env'
  After 'cleanup_env'

  # Read the recorded tech.status for the lint stage from the pipeline report.
  # Prints the status (or empty string if none) on stdout.
  read_lint_status() {
    jq -r '.stages[] | select(.name == "lint") | .tech.status // empty' \
      "$BRIK_LOG_DIR/pipeline-report.json" 2>/dev/null
  }

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

    It "returns 0 and records status skipped in the report"
      run_lint_no_checks() {
        brik.use() { :; }
        local ctx
        ctx="$(context.create "lint")" 2>/dev/null || ctx="$(mktemp)"
        stages.lint "$ctx" >/dev/null 2>&1 || return $?
        read_lint_status
      }
      When call run_lint_no_checks
      The status should be success
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

    It "returns 0 when the lint check succeeds"
      run_lint() {
        brik.use() { :; }
        verify.lint.run() { return 0; }
        local ctx
        ctx="$(context.create "lint")" 2>/dev/null || ctx="$(mktemp)"
        stages.lint "$ctx"
      }
      When call run_lint
      The status should be success
      The error should be present
    End

    It "returns non-zero when the lint check fails"
      run_lint_fail() {
        brik.use() { :; }
        verify.lint.run() { return 1; }
        local ctx
        ctx="$(context.create "lint")" 2>/dev/null || ctx="$(mktemp)"
        stages.lint "$ctx"
      }
      When call run_lint_fail
      The status should equal 10
      The error should be present
    End

    It "logs lint checks being run"
      run_lint_log() {
        brik.use() { :; }
        verify.lint.run() { return 0; }
        local ctx
        ctx="$(context.create "lint")" 2>/dev/null || ctx="$(mktemp)"
        stages.lint "$ctx"
      }
      When call run_lint_log
      The status should be success
      The error should include "running verify check: lint"
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

    It "skips when lint is disabled and records status skipped"
      run_lint_disabled() {
        local ctx
        ctx="$(context.create "lint")" 2>/dev/null || ctx="$(mktemp)"
        stages.lint "$ctx" >/dev/null 2>&1 || return $?
        read_lint_status
      }
      When call run_lint_disabled
      The status should be success
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

    It "returns 0 when the format check succeeds"
      run_format() {
        brik.use() { :; }
        verify.format.run() { return 0; }
        local ctx
        ctx="$(context.create "lint")" 2>/dev/null || ctx="$(mktemp)"
        stages.lint "$ctx"
      }
      When call run_format
      The status should be success
      The error should be present
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

    It "returns 0 when the type_check succeeds"
      run_typecheck() {
        brik.use() { :; }
        verify.type_check.run() { return 0; }
        local ctx
        ctx="$(context.create "lint")" 2>/dev/null || ctx="$(mktemp)"
        stages.lint "$ctx"
      }
      When call run_typecheck
      The status should be success
      The error should be present
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

    It "returns 0 when all configured checks pass"
      run_multi() {
        brik.use() { :; }
        verify.lint.run() { return 0; }
        verify.format.run() { return 0; }
        local ctx
        ctx="$(context.create "lint")" 2>/dev/null || ctx="$(mktemp)"
        stages.lint "$ctx"
      }
      When call run_multi
      The status should be success
      The error should be present
    End

    It "returns non-zero if any check fails"
      run_multi_fail() {
        brik.use() { :; }
        verify.lint.run() { return 0; }
        verify.format.run() { return 1; }
        local ctx
        ctx="$(context.create "lint")" 2>/dev/null || ctx="$(mktemp)"
        stages.lint "$ctx"
      }
      When call run_multi_fail
      The status should equal 10
      The error should be present
    End
  End
End

Describe "stacks.install_deps (dev mode)"
  Include "$BRIK_HOME/lib/pipeline/stage.sh"
  Include "$BRIK_HOME/lib/pipeline/loader.sh"
  Include "$BRIK_HOME/lib/stages/lint.sh"
  Include "$BRIK_HOME/spec/support/mock_helper.sh"

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
        stacks.install_deps "$DEPS_WS" dev 2>/dev/null
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
        stacks.install_deps "$DEPS_WS" dev 2>/dev/null
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
        stacks.install_deps "$DEPS_WS" dev 2>/dev/null
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
        stacks.install_deps "$DEPS_WS" dev 2>/dev/null
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
        stacks.install_deps "$DEPS_WS" dev 2>/dev/null
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
        stacks.install_deps "$DEPS_WS" dev 2>/dev/null
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
        stacks.install_deps "$DEPS_WS" dev 2>/dev/null
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
        stacks.install_deps "$DEPS_WS" dev 2>/dev/null
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
        stacks.install_deps "$DEPS_WS" dev 2>/dev/null
        [[ ! -f "$MOCK_LOG" ]]
      }
      When call run_unknown_stack
      The status should be success
    End

    It "does nothing when BRIK_BUILD_STACK is empty"
      run_empty_stack() {
        unset BRIK_BUILD_STACK
        rm -f "$MOCK_LOG"
        stacks.install_deps "$DEPS_WS" dev 2>/dev/null
        [[ ! -f "$MOCK_LOG" ]]
      }
      When call run_empty_stack
      The status should be success
    End
  End
End
