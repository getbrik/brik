Describe "stages.quality"
  Include "$BRIK_HOME/runtime/bash/lib/runtime/stage.sh"
  Include "$BRIK_HOME/runtime/bash/lib/core/_loader.sh"
  Include "$BRIK_HOME/runtime/bash/lib/core/config.sh"
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

    It "logs lint tool name"
      run_quality_lint_log() {
        brik.use() { :; }
        quality.lint.run() { return 0; }
        local ctx
        ctx="$(context.create "quality")" 2>/dev/null || ctx="$(mktemp)"
        stages.quality "$ctx"
      }
      When call run_quality_lint_log
      The error should include "running lint: eslint"
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
End
