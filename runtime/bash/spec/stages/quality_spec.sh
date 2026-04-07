Describe "stages.quality"
  Include "$BRIK_HOME/runtime/bash/lib/runtime/stage.sh"
  Include "$BRIK_HOME/runtime/bash/lib/core/_loader.sh"
  Include "$BRIK_HOME/runtime/bash/lib/core/config.sh"
  Include "$BRIK_HOME/runtime/bash/lib/core/quality.sh"
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
    unset BRIK_QUALITY_LINT_TOOL BRIK_QUALITY_FORMAT_TOOL BRIK_QUALITY_SAST_TOOL \
          BRIK_QUALITY_DEPS_TOOL BRIK_QUALITY_COVERAGE_THRESHOLD \
          BRIK_QUALITY_LICENSE_ALLOWED BRIK_QUALITY_CONTAINER_IMAGE \
          BRIK_QUALITY_LINT_FIX BRIK_QUALITY_LINT_CONFIG \
          BRIK_QUALITY_ENABLED 2>/dev/null || true
  }
  Before 'setup_env'
  After 'cleanup_env'

  It "is callable as a function"
    callable_check() { declare -f stages.quality >/dev/null; }
    When call callable_check
    The status should be success
  End

  Describe "with no quality checks configured"
    setup_no_checks() {
      # Use stack=auto so no stack defaults are applied
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
      run_quality_no_checks() {
        brik.use() { :; }
        local ctx
        ctx="$(context.create "quality")" 2>/dev/null || ctx="$(mktemp)"
        stages.quality "$ctx" >/dev/null 2>&1
        grep "^BRIK_QUALITY_STATUS=" "$ctx" | cut -d= -f2
      }
      When call run_quality_no_checks
      The output should equal "skipped"
    End
  End

  Describe "with lint configured"
    setup_quality_lint() {
      cat > "$BRIK_CONFIG_FILE" <<'YAML'
version: 1
project:
  name: test
  stack: node
quality:
  enabled: true
  lint:
    tool: eslint
    config: .eslintrc.json
    fix: "true"
YAML
      config.read "$BRIK_CONFIG_FILE" >/dev/null 2>&1 || true
    }
    Before 'setup_quality_lint'

    It "runs lint check and sets status to success"
      run_quality_lint() {
        brik.use() { :; }
        quality.lint.run() { return 0; }
        local ctx
        ctx="$(context.create "quality")" 2>/dev/null || ctx="$(mktemp)"
        stages.quality "$ctx" >/dev/null 2>&1
        grep "^BRIK_QUALITY_STATUS=" "$ctx" | cut -d= -f2
      }
      When call run_quality_lint
      The output should equal "success"
    End

    It "sets status to failed when lint fails"
      run_quality_lint_fail() {
        brik.use() { :; }
        quality.lint.run() { return 1; }
        local ctx
        ctx="$(context.create "quality")" 2>/dev/null || ctx="$(mktemp)"
        stages.quality "$ctx" >/dev/null 2>&1 || true
        grep "^BRIK_QUALITY_STATUS=" "$ctx" | cut -d= -f2
      }
      When call run_quality_lint_fail
      The output should equal "failed"
    End

    It "logs quality checks being run"
      run_quality_lint_log() {
        brik.use() { :; }
        quality.lint.run() { return 0; }
        local ctx
        ctx="$(context.create "quality")" 2>/dev/null || ctx="$(mktemp)"
        stages.quality "$ctx"
      }
      When call run_quality_lint_log
      The error should include "running quality check: lint"
    End
  End

  Describe "with coverage configured"
    setup_quality_cov() {
      cat > "$BRIK_CONFIG_FILE" <<'YAML'
version: 1
project:
  name: test
  stack: auto
quality:
  enabled: true
  coverage:
    threshold: 80
    report: lcov
YAML
      config.read "$BRIK_CONFIG_FILE" >/dev/null 2>&1 || true
    }
    Before 'setup_quality_cov'

    It "runs coverage check"
      run_quality_cov() {
        brik.use() { :; }
        quality.coverage.run() { return 0; }
        local ctx
        ctx="$(context.create "quality")" 2>/dev/null || ctx="$(mktemp)"
        stages.quality "$ctx" >/dev/null 2>&1
        grep "^BRIK_QUALITY_STATUS=" "$ctx" | cut -d= -f2
      }
      When call run_quality_cov
      The output should equal "success"
    End
  End

  Describe "with quality disabled"
    setup_disabled() {
      cat > "$BRIK_CONFIG_FILE" <<'YAML'
version: 1
project:
  name: test
  stack: node
quality:
  enabled: false
YAML
      config.read "$BRIK_CONFIG_FILE" >/dev/null 2>&1 || true
    }
    Before 'setup_disabled'

    It "skips when quality is disabled"
      run_quality_disabled() {
        local ctx
        ctx="$(context.create "quality")" 2>/dev/null || ctx="$(mktemp)"
        stages.quality "$ctx" >/dev/null 2>&1
        grep "^BRIK_QUALITY_STATUS=" "$ctx" | cut -d= -f2
      }
      When call run_quality_disabled
      The output should equal "skipped"
    End

    It "logs that quality is disabled"
      run_quality_disabled_log() {
        local ctx
        ctx="$(context.create "quality")" 2>/dev/null || ctx="$(mktemp)"
        stages.quality "$ctx"
      }
      When call run_quality_disabled_log
      The error should include "quality stage disabled"
    End
  End

  Describe "with format configured"
    setup_quality_format() {
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
    Before 'setup_quality_format'

    It "runs format check and sets status to success"
      run_quality_format() {
        brik.use() { :; }
        quality.format.run() { return 0; }
        local ctx
        ctx="$(context.create "quality")" 2>/dev/null || ctx="$(mktemp)"
        stages.quality "$ctx" >/dev/null 2>&1
        grep "^BRIK_QUALITY_STATUS=" "$ctx" | cut -d= -f2
      }
      When call run_quality_format
      The output should equal "success"
    End
  End

  Describe "with deps configured"
    setup_quality_deps() {
      cat > "$BRIK_CONFIG_FILE" <<'YAML'
version: 1
project:
  name: test
  stack: node
quality:
  enabled: true
  deps:
    tool: npm-audit
YAML
      config.read "$BRIK_CONFIG_FILE" >/dev/null 2>&1 || true
    }
    Before 'setup_quality_deps'

    It "runs deps check"
      run_quality_deps() {
        brik.use() { :; }
        quality.deps.run() { return 0; }
        local ctx
        ctx="$(context.create "quality")" 2>/dev/null || ctx="$(mktemp)"
        stages.quality "$ctx" >/dev/null 2>&1
        grep "^BRIK_QUALITY_STATUS=" "$ctx" | cut -d= -f2
      }
      When call run_quality_deps
      The output should equal "success"
    End
  End

  Describe "with type_check configured"
    setup_quality_typecheck() {
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
    Before 'setup_quality_typecheck'

    It "runs type_check check"
      run_quality_typecheck() {
        brik.use() { :; }
        quality.type_check.run() { return 0; }
        local ctx
        ctx="$(context.create "quality")" 2>/dev/null || ctx="$(mktemp)"
        stages.quality "$ctx" >/dev/null 2>&1
        grep "^BRIK_QUALITY_STATUS=" "$ctx" | cut -d= -f2
      }
      When call run_quality_typecheck
      The output should equal "success"
    End
  End

  Describe "with license configured"
    setup_quality_license() {
      cat > "$BRIK_CONFIG_FILE" <<'YAML'
version: 1
project:
  name: test
  stack: auto
quality:
  enabled: true
  license:
    allowed: MIT,Apache-2.0
YAML
      config.read "$BRIK_CONFIG_FILE" >/dev/null 2>&1 || true
    }
    Before 'setup_quality_license'

    It "runs license check"
      run_quality_license() {
        brik.use() { :; }
        quality.license.run() { return 0; }
        local ctx
        ctx="$(context.create "quality")" 2>/dev/null || ctx="$(mktemp)"
        stages.quality "$ctx" >/dev/null 2>&1
        grep "^BRIK_QUALITY_STATUS=" "$ctx" | cut -d= -f2
      }
      When call run_quality_license
      The output should equal "success"
    End
  End

  Describe "with container configured"
    setup_quality_container() {
      cat > "$BRIK_CONFIG_FILE" <<'YAML'
version: 1
project:
  name: test
  stack: auto
quality:
  enabled: true
  container:
    image: myapp:latest
YAML
      config.read "$BRIK_CONFIG_FILE" >/dev/null 2>&1 || true
    }
    Before 'setup_quality_container'

    It "runs container check"
      run_quality_container() {
        brik.use() { :; }
        quality.container.run() { return 0; }
        local ctx
        ctx="$(context.create "quality")" 2>/dev/null || ctx="$(mktemp)"
        stages.quality "$ctx" >/dev/null 2>&1
        grep "^BRIK_QUALITY_STATUS=" "$ctx" | cut -d= -f2
      }
      When call run_quality_container
      The output should equal "success"
    End
  End

  Describe "with SAST configured"
    setup_quality_sast() {
      cat > "$BRIK_CONFIG_FILE" <<'YAML'
version: 1
project:
  name: test
  stack: auto
quality:
  enabled: true
  sast:
    tool: semgrep
    ruleset: p/security-audit
YAML
      config.read "$BRIK_CONFIG_FILE" >/dev/null 2>&1 || true
    }
    Before 'setup_quality_sast'

    It "runs SAST check"
      run_quality_sast() {
        brik.use() { :; }
        quality.sast.run() { return 0; }
        local ctx
        ctx="$(context.create "quality")" 2>/dev/null || ctx="$(mktemp)"
        stages.quality "$ctx" >/dev/null 2>&1
        grep "^BRIK_QUALITY_STATUS=" "$ctx" | cut -d= -f2
      }
      When call run_quality_sast
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
  enabled: true
  lint:
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
        ctx="$(context.create "quality")" 2>/dev/null || ctx="$(mktemp)"
        stages.quality "$ctx" >/dev/null 2>&1
        grep "^BRIK_QUALITY_STATUS=" "$ctx" | cut -d= -f2
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
        ctx="$(context.create "quality")" 2>/dev/null || ctx="$(mktemp)"
        stages.quality "$ctx" >/dev/null 2>&1 || true
        grep "^BRIK_QUALITY_STATUS=" "$ctx" | cut -d= -f2
      }
      When call run_multi_fail
      The output should equal "failed"
    End
  End
End

Describe "_quality.install_deps"
  Include "$BRIK_HOME/runtime/bash/lib/runtime/stage.sh"
  Include "$BRIK_HOME/runtime/bash/lib/stages/quality.sh"

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
        _quality.install_deps "$DEPS_WS" 2>/dev/null
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
        _quality.install_deps "$DEPS_WS" 2>/dev/null
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
        _quality.install_deps "$DEPS_WS" 2>/dev/null
        grep -q 'pip install -e' "$MOCK_LOG"
      }
      When call run_python_pyproject
      The status should be success
    End

    It "installs from requirements-dev.txt"
      run_python_reqdev() {
        export BRIK_BUILD_STACK="python"
        # Make sure no pyproject.toml
        rm -f "${DEPS_WS}/pyproject.toml"
        printf 'pytest\n' > "${DEPS_WS}/requirements-dev.txt"
        cat > "${MOCK_BIN}/pip" << MOCKEOF
#!/usr/bin/env bash
printf 'pip %s\n' "\$*" >> "$MOCK_LOG"
exit 0
MOCKEOF
        chmod +x "${MOCK_BIN}/pip"
        export PATH="${MOCK_BIN}:${ORIG_PATH}"
        _quality.install_deps "$DEPS_WS" 2>/dev/null
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
        _quality.install_deps "$DEPS_WS" 2>/dev/null
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
        cat > "${MOCK_BIN}/rustup" << MOCKEOF
#!/usr/bin/env bash
printf 'rustup %s\n' "\$*" >> "$MOCK_LOG"
exit 0
MOCKEOF
        chmod +x "${MOCK_BIN}/rustup"
        # cargo-clippy and rustfmt not in MOCK_BIN, so command -v fails
        export PATH="${MOCK_BIN}:/usr/bin:/bin"
        _quality.install_deps "$DEPS_WS" 2>/dev/null
        grep -q "rustup component add clippy" "$MOCK_LOG"
      }
      When call run_rust_clippy
      The status should be success
    End

    It "installs rustfmt when missing"
      run_rust_rustfmt() {
        export BRIK_BUILD_STACK="rust"
        cat > "${MOCK_BIN}/rustup" << MOCKEOF
#!/usr/bin/env bash
printf 'rustup %s\n' "\$*" >> "$MOCK_LOG"
exit 0
MOCKEOF
        chmod +x "${MOCK_BIN}/rustup"
        export PATH="${MOCK_BIN}:/usr/bin:/bin"
        _quality.install_deps "$DEPS_WS" 2>/dev/null
        grep -q "rustup component add rustfmt" "$MOCK_LOG"
      }
      When call run_rust_rustfmt
      The status should be success
    End

    It "skips when rustup is not available"
      run_rust_no_rustup() {
        export BRIK_BUILD_STACK="rust"
        # No rustup in PATH
        rm -f "${MOCK_BIN}/rustup" "$MOCK_LOG"
        export PATH="${MOCK_BIN}:/usr/bin:/bin"
        _quality.install_deps "$DEPS_WS" 2>/dev/null
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
        _quality.install_deps "$DEPS_WS" 2>/dev/null
        [[ ! -f "$MOCK_LOG" ]]
      }
      When call run_unknown_stack
      The status should be success
    End

    It "does nothing when BRIK_BUILD_STACK is empty"
      run_empty_stack() {
        unset BRIK_BUILD_STACK
        rm -f "$MOCK_LOG"
        _quality.install_deps "$DEPS_WS" 2>/dev/null
        [[ ! -f "$MOCK_LOG" ]]
      }
      When call run_empty_stack
      The status should be success
    End
  End
End
