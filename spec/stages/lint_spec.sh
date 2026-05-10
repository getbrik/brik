#shellcheck shell=bash disable=SC2148,SC2317,SC2329

Describe "stages.lint"
  Include "$BRIK_HOME/lib/pipeline/stage.sh"
  Include "$BRIK_HOME/lib/pipeline/loader.sh"
  Include "$BRIK_HOME/lib/pipeline/report.sh"
  Include "$BRIK_HOME/lib/transverse/config.sh"
  Include "$BRIK_HOME/lib/transverse/csv.sh"
  Include "$BRIK_HOME/lib/transverse/sarif.sh"
  Include "$BRIK_HOME/lib/stages/verify/verify.sh"
  Include "$BRIK_HOME/lib/stages/lint.sh"
  Include "$BRIK_HOME/spec/support/mock_helper.sh"

  setup_env() {
    export BRIK_CONFIG_FILE
    BRIK_CONFIG_FILE="$(mktemp)"
    printf 'version: 1\nproject:\n  name: test\n  stack: node\n' > "$BRIK_CONFIG_FILE"
    mock.workspace.setup
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
    rm -rf "$BRIK_LOG_DIR"
    mock.workspace.teardown
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
      "$BRIK_LOG_DIR/aggregate-report.json" 2>/dev/null
  }

  read_lint_tech_json() {
    local key="$1"
    jq -c --arg k "$key" \
      '.stages[] | select(.name == "lint") | .tech[$k] // empty' \
      "$BRIK_LOG_DIR/aggregate-report.json" 2>/dev/null
  }

  It "is callable as a function"
    callable_check() { declare -f stages.lint >/dev/null; }
    When call callable_check
    The status should be success
  End

  Describe "C.3 enrichment with multiple checks configured"
    setup_lint_full() {
      cat > "$BRIK_CONFIG_FILE" <<'YAML'
version: 1
project:
  name: test
  stack: node
quality:
  lint:
    enabled: true
    tool: eslint
    command: "eslint --max-warnings 0"
  format:
    tool: prettier
  type_check:
    command: "tsc --noEmit"
YAML
      config.read "$BRIK_CONFIG_FILE" >/dev/null 2>&1 || true
    }
    Before 'setup_lint_full'

    It "records lint.tech.checks as an array of configured check names"
      run_lint_checks() {
        brik.use() { :; }
        verify.run() { return 0; }
        local ctx
        ctx="$(context.create "lint")" 2>/dev/null || ctx="$(mktemp)"
        stages.lint "$ctx" >/dev/null 2>&1
        read_lint_tech_json "checks"
      }
      When call run_lint_checks
      The output should equal '["lint","format","type_check"]'
    End

    It "records lint.tech.tools as an object keyed by check"
      run_lint_tools() {
        brik.use() { :; }
        verify.run() { return 0; }
        local ctx
        ctx="$(context.create "lint")" 2>/dev/null || ctx="$(mktemp)"
        stages.lint "$ctx" >/dev/null 2>&1
        read_lint_tech_json "tools"
      }
      When call run_lint_tools
      The output should equal '{"lint":"eslint","format":"prettier"}'
    End

    It "records lint.tech.commands as an object keyed by check"
      run_lint_commands() {
        brik.use() { :; }
        verify.run() { return 0; }
        local ctx
        ctx="$(context.create "lint")" 2>/dev/null || ctx="$(mktemp)"
        stages.lint "$ctx" >/dev/null 2>&1
        read_lint_tech_json "commands"
      }
      When call run_lint_commands
      The output should equal '{"lint":"eslint --max-warnings 0","type_check":"tsc --noEmit"}'
    End
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

    It "returns 0 and records tech.status=skipped in the report"
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

    It "records tech.kind=not-applicable for the stage"
      run_lint_kind() {
        brik.use() { :; }
        local ctx
        ctx="$(context.create "lint")" 2>/dev/null || ctx="$(mktemp)"
        stages.lint "$ctx" >/dev/null 2>&1 || return $?
        jq -r '.stages[] | select(.name=="lint") | .tech.kind // empty' \
          "$BRIK_LOG_DIR/aggregate-report.json"
      }
      When call run_lint_kind
      The output should equal "not-applicable"
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

  Describe "with legacy quality.lint.enabled=false (no other lint config)"
    setup_legacy_disabled() {
      # stack=auto avoids triggering per-stack auto-detection of a lint
      # tool; this isolates the assertion to "the legacy enabled=false key
      # no longer short-circuits the stage" without needing to mock the
      # downstream verify / install_deps machinery.
      cat > "$BRIK_CONFIG_FILE" <<'YAML'
version: 1
project:
  name: test
  stack: auto
quality:
  lint:
    enabled: false
YAML
      config.read "$BRIK_CONFIG_FILE" >/dev/null 2>&1 || true
      unset BRIK_COMMIT_TAG
    }
    Before 'setup_legacy_disabled'

    It "ignores the legacy key and lets the stage run to completion"
      run_lint_legacy() {
        brik.use() { :; }
        local ctx
        ctx="$(context.create "lint")" 2>/dev/null || ctx="$(mktemp)"
        stages.lint "$ctx" >/dev/null 2>&1
      }
      When call run_lint_legacy
      The status should be success
    End

    It "records tech.status=skipped (auto, not lint.enabled-driven)"
      run_lint_legacy_status() {
        brik.use() { :; }
        local ctx
        ctx="$(context.create "lint")" 2>/dev/null || ctx="$(mktemp)"
        stages.lint "$ctx" >/dev/null 2>&1 || true
        read_lint_status
      }
      When call run_lint_legacy_status
      The output should equal "skipped"
    End

    It "records tech.kind=not-applicable (no checks configured)"
      run_lint_legacy_kind() {
        brik.use() { :; }
        local ctx
        ctx="$(context.create "lint")" 2>/dev/null || ctx="$(mktemp)"
        stages.lint "$ctx" >/dev/null 2>&1 || true
        jq -r '.stages[] | select(.name=="lint") | .tech.kind // empty' \
          "$BRIK_LOG_DIR/aggregate-report.json"
      }
      When call run_lint_legacy_kind
      The output should equal "not-applicable"
    End
  End

  Describe "with legacy quality.lint.enabled=false AND a lint tool configured"
    setup_legacy_disabled_with_tool() {
      cat > "$BRIK_CONFIG_FILE" <<'YAML'
version: 1
project:
  name: test
  stack: node
quality:
  lint:
    enabled: false
    tool: eslint
    command: "eslint --max-warnings 0"
YAML
      config.read "$BRIK_CONFIG_FILE" >/dev/null 2>&1 || true
      unset BRIK_COMMIT_TAG
    }
    Before 'setup_legacy_disabled_with_tool'

    It "runs the configured tool anyway (legacy enabled=false is ignored)"
      run_lint_legacy_runs() {
        brik.use() { :; }
        verify.run() { echo "verify-ran"; return 0; }
        local ctx
        ctx="$(context.create "lint")" 2>/dev/null || ctx="$(mktemp)"
        stages.lint "$ctx" 2>/dev/null
      }
      When call run_lint_legacy_runs
      The status should be success
      The output should include "verify-ran"
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

  Describe "business.* aggregation from brik-artifacts/lint/<check>.sarif"
    read_lint_business_json() {
      local key="$1"
      jq -c --arg k "$key" \
        '.stages[] | select(.name == "lint") | .business[$k] // empty' \
        "$BRIK_LOG_DIR/aggregate-report.json" 2>/dev/null
    }

    setup_lint_with_sarif() {
      cat > "$BRIK_CONFIG_FILE" <<'YAML'
version: 1
project:
  name: test
  stack: node
quality:
  lint:
    enabled: true
    tool: eslint
    command: "true"
  format:
    tool: prettier
    command: "true"
YAML
      config.read "$BRIK_CONFIG_FILE" >/dev/null 2>&1 || true
      mkdir -p "$BRIK_WORKSPACE/brik-artifacts/lint"
    }
    Before 'setup_lint_with_sarif'

    It "records business.violations.total summed across present per-check files"
      run_total() {
        cp "${BRIK_HOME}/spec/fixtures/sarif/eslint.sarif"   "$BRIK_WORKSPACE/brik-artifacts/lint/lint.sarif"
        cp "${BRIK_HOME}/spec/fixtures/sarif/eslint.sarif"   "$BRIK_WORKSPACE/brik-artifacts/lint/format.sarif"
        brik.use() { :; }
        verify.run() { return 0; }
        local ctx
        ctx="$(context.create "lint")" 2>/dev/null || ctx="$(mktemp)"
        stages.lint "$ctx" >/dev/null 2>&1
        read_lint_business_json "violations" | jq -r '.total'
      }
      When call run_total
      The output should equal "10"
    End

    It "records business.violations.by_severity summed across files"
      run_sev() {
        cp "${BRIK_HOME}/spec/fixtures/sarif/eslint.sarif" "$BRIK_WORKSPACE/brik-artifacts/lint/lint.sarif"
        brik.use() { :; }
        verify.run() { return 0; }
        local ctx
        ctx="$(context.create "lint")" 2>/dev/null || ctx="$(mktemp)"
        stages.lint "$ctx" >/dev/null 2>&1
        read_lint_business_json "violations" | jq -c '.by_severity'
      }
      When call run_sev
      The output should equal '{"critical":0,"high":3,"medium":2,"low":0,"info":0}'
    End

    It "records business.violations.by_check keyed by configured checks"
      run_by_check() {
        cp "${BRIK_HOME}/spec/fixtures/sarif/eslint.sarif" "$BRIK_WORKSPACE/brik-artifacts/lint/lint.sarif"
        cp "${BRIK_HOME}/spec/fixtures/sarif/ruff.sarif"   "$BRIK_WORKSPACE/brik-artifacts/lint/format.sarif"
        brik.use() { :; }
        verify.run() { return 0; }
        local ctx
        ctx="$(context.create "lint")" 2>/dev/null || ctx="$(mktemp)"
        stages.lint "$ctx" >/dev/null 2>&1
        read_lint_business_json "violations" | jq -c '.by_check'
      }
      When call run_by_check
      The output should equal '{"lint":5,"format":6}'
    End

    It "records business.report = {format, path}"
      run_report() {
        cp "${BRIK_HOME}/spec/fixtures/sarif/eslint.sarif" "$BRIK_WORKSPACE/brik-artifacts/lint/lint.sarif"
        brik.use() { :; }
        verify.run() { return 0; }
        local ctx
        ctx="$(context.create "lint")" 2>/dev/null || ctx="$(mktemp)"
        stages.lint "$ctx" >/dev/null 2>&1
        read_lint_business_json "report"
      }
      When call run_report
      The output should equal '{"format":"sarif","path":"brik-artifacts/lint/lint.sarif"}'
    End

    It "records business.fix_applied=false by default"
      run_fix_default() {
        cp "${BRIK_HOME}/spec/fixtures/sarif/eslint.sarif" "$BRIK_WORKSPACE/brik-artifacts/lint/lint.sarif"
        brik.use() { :; }
        verify.run() { return 0; }
        local ctx
        ctx="$(context.create "lint")" 2>/dev/null || ctx="$(mktemp)"
        stages.lint "$ctx" >/dev/null 2>&1
        jq -r '.stages[] | select(.name == "lint") | (.business.fix_applied | tostring)' \
          "$BRIK_LOG_DIR/aggregate-report.json" 2>/dev/null
      }
      When call run_fix_default
      The output should equal "false"
    End

    It "records business.fix_applied=true when BRIK_QUALITY_LINT_FIX=true"
      run_fix_set() {
        export BRIK_QUALITY_LINT_FIX=true
        cp "${BRIK_HOME}/spec/fixtures/sarif/eslint.sarif" "$BRIK_WORKSPACE/brik-artifacts/lint/lint.sarif"
        brik.use() { :; }
        verify.run() { return 0; }
        local ctx
        ctx="$(context.create "lint")" 2>/dev/null || ctx="$(mktemp)"
        stages.lint "$ctx" >/dev/null 2>&1
        jq -r '.stages[] | select(.name == "lint") | (.business.fix_applied | tostring)' \
          "$BRIK_LOG_DIR/aggregate-report.json" 2>/dev/null
      }
      When call run_fix_set
      The output should equal "true"
    End

    It "omits business.* entirely when no SARIF outputs were produced"
      run_no_sarif() {
        brik.use() { :; }
        verify.run() { return 0; }
        local ctx
        ctx="$(context.create "lint")" 2>/dev/null || ctx="$(mktemp)"
        stages.lint "$ctx" >/dev/null 2>&1
        jq -c '.stages[] | select(.name == "lint") | .business // {}' \
          "$BRIK_LOG_DIR/aggregate-report.json" 2>/dev/null
      }
      When call run_no_sarif
      The output should equal "{}"
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
        printf '{"name":"t","version":"0.0.0"}\n' > "$DEPS_WS/package.json"
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
