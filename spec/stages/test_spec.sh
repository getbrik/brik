Describe "stages.test"
  Include "$BRIK_PIPELINE_LIB/logging.sh"
  Include "$BRIK_PIPELINE_LIB/tools.sh"
  Include "$BRIK_HOME/lib/pipeline/stage.sh"
  Include "$BRIK_HOME/lib/pipeline/loader.sh"
  Include "$BRIK_HOME/lib/transverse/config.sh"
  Include "$BRIK_HOME/lib/transverse/junit.sh"
  Include "$BRIK_HOME/lib/stages/test.sh"

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
    export BRIK_RUN_ID="test-spec-fixture"
    config.read "$BRIK_CONFIG_FILE" >/dev/null 2>&1 || true
    report.init >/dev/null 2>&1 || true
  }
  cleanup_env() {
    rm -f "$BRIK_CONFIG_FILE"
    rm -rf "$BRIK_WORKSPACE" "$BRIK_LOG_DIR"
    unset BRIK_RUN_ID 2>/dev/null || true
  }

  read_test_tech() {
    local key="$1"
    jq -r --arg k "$key" \
      '.stages[] | select(.name == "test") | .tech[$k] // empty' \
      "$BRIK_LOG_DIR/aggregate-report.json" 2>/dev/null
  }

  read_test_coverage_pct() {
    jq -r '.stages[] | select(.name == "test") | .business.coverage.line_pct // empty' \
      "$BRIK_LOG_DIR/aggregate-report.json" 2>/dev/null
  }
  Before 'setup_env'
  After 'cleanup_env'

  It "is callable as a function"
    callable_check() { declare -f stages.test >/dev/null; }
    When call callable_check
    The status should be success
  End

  _stub_leaf_success() {
    brik.use() { :; }
    stacks.detect_from_framework() { printf 'node'; return 0; }
    stacks.detect() { printf 'node'; return 0; }
    stacks.node.test_cmd() { printf 'true'; return 0; }
    stacks.node.test() { printf 'true'; return 0; }
    stacks.install_deps() { :; }
  }

  _stub_leaf_failure() {
    brik.use() { :; }
    stacks.detect_from_framework() { printf 'node'; return 0; }
    stacks.detect() { printf 'node'; return 0; }
    stacks.node.test_cmd() { printf 'false'; return 0; }
    stacks.node.test() { printf 'false'; return 0; }
    stacks.install_deps() { :; }
  }

  It "returns 0 when the stack test cmd succeeds"
    run_test_success() {
      _stub_leaf_success
      local ctx
      ctx="$(context.create "test")" 2>/dev/null || ctx="$(mktemp)"
      stages.test "$ctx" >/dev/null 2>&1
    }
    When call run_test_success
    The status should be success
  End

  It "returns non-zero when the stack test cmd fails"
    run_test_failure() {
      _stub_leaf_failure
      local ctx
      ctx="$(context.create "test")" 2>/dev/null || ctx="$(mktemp)"
      stages.test "$ctx" >/dev/null 2>&1
    }
    When call run_test_failure
    The status should be failure
  End

  It "exports BRIK_TEST_FRAMEWORK from config"
    run_test_framework() {
      _stub_leaf_success
      local ctx
      ctx="$(context.create "test")" 2>/dev/null || ctx="$(mktemp)"
      stages.test "$ctx" >/dev/null 2>&1
      printf '%s' "${BRIK_TEST_FRAMEWORK:-}"
    }
    When call run_test_framework
    The output should equal "jest"
  End

  It "records test.tech.framework from .test.framework"
    run_test_records_framework() {
      printf 'version: 1\nproject:\n  name: test\n  stack: node\ntest:\n  framework: pytest\n' \
        > "$BRIK_CONFIG_FILE"
      config.read "$BRIK_CONFIG_FILE" >/dev/null 2>&1 || true
      _stub_leaf_success
      local ctx
      ctx="$(context.create "test")" 2>/dev/null || ctx="$(mktemp)"
      stages.test "$ctx" >/dev/null 2>&1
      read_test_tech "framework"
    }
    When call run_test_records_framework
    The output should equal "pytest"
  End

  It "records test.tech.tool from BRIK_TEST_TOOL when set"
    run_test_records_tool() {
      export BRIK_TEST_TOOL="vitest"
      _stub_leaf_success
      local ctx
      ctx="$(context.create "test")" 2>/dev/null || ctx="$(mktemp)"
      stages.test "$ctx" >/dev/null 2>&1
      read_test_tech "tool"
      unset BRIK_TEST_TOOL
    }
    When call run_test_records_tool
    The output should equal "vitest"
  End

  It "records test.tech.coverage_tool from BRIK_TEST_COVERAGE_FORMAT"
    run_test_records_coverage_tool() {
      export BRIK_TEST_COVERAGE_FORMAT="cobertura"
      _stub_leaf_success
      local ctx
      ctx="$(context.create "test")" 2>/dev/null || ctx="$(mktemp)"
      stages.test "$ctx" >/dev/null 2>&1
      read_test_tech "coverage_tool"
      unset BRIK_TEST_COVERAGE_FORMAT
    }
    When call run_test_records_coverage_tool
    The output should equal "cobertura"
  End

  It "records test.business.coverage.line_pct from a Cobertura report when reports.enabled=true"
    run_test_records_coverage() {
      export BRIK_TEST_REPORTS_ENABLED="true"
      export BRIK_TEST_COVERAGE_DIR="$BRIK_WORKSPACE/brik-artifacts/test/coverage"
      mkdir -p "$BRIK_TEST_COVERAGE_DIR"
      printf '<?xml version="1.0"?>\n<coverage line-rate="0.8542" />\n' \
        > "$BRIK_TEST_COVERAGE_DIR/coverage.xml"
      # Source coverage helpers explicitly: _stub_leaf_success neutralizes
      # brik.use, so stages.test cannot lazy-load transverse.coverage.
      # shellcheck source=/dev/null
      . "$BRIK_HOME/lib/transverse/coverage.sh" 2>/dev/null || true
      _stub_leaf_success
      local ctx
      ctx="$(context.create "test")" 2>/dev/null || ctx="$(mktemp)"
      stages.test "$ctx" >/dev/null 2>&1
      read_test_coverage_pct
      unset BRIK_TEST_REPORTS_ENABLED BRIK_TEST_COVERAGE_DIR
    }
    When call run_test_records_coverage
    The output should equal "85.42"
  End

  It "runs BRIK_TEST_COMMAND override when set"
    run_test_override() {
      cat > "$BRIK_CONFIG_FILE" <<'YAML'
version: 1
project:
  name: test
  stack: node
test:
  command: "printf 'override-ran'"
YAML
      config.read "$BRIK_CONFIG_FILE" >/dev/null 2>&1 || true
      _stub_leaf_success
      local ctx
      ctx="$(context.create "test")" 2>/dev/null || ctx="$(mktemp)"
      stages.test "$ctx" 2>/dev/null
    }
    When call run_test_override
    The output should include "override-ran"
  End

  It "returns IO_FAILURE when BRIK_WORKSPACE does not exist"
    run_test_no_workspace() {
      _stub_leaf_success
      export BRIK_WORKSPACE="/nonexistent/brik-ws-$$"
      local ctx
      ctx="$(context.create "test")" 2>/dev/null || ctx="$(mktemp)"
      stages.test "$ctx" 2>/dev/null
      printf '%s' "$?"
    }
    When call run_test_no_workspace
    The output should equal "6"
  End

  It "runs BRIK_TEST_COMMAND override and reports success"
    run_test_cmd_success() {
      cat > "$BRIK_CONFIG_FILE" <<'YAML'
version: 1
project:
  name: test
  stack: node
test:
  command: "true"
YAML
      config.read "$BRIK_CONFIG_FILE" >/dev/null 2>&1 || true
      _stub_leaf_success
      local ctx
      ctx="$(context.create "test")" 2>/dev/null || ctx="$(mktemp)"
      stages.test "$ctx" 2>/dev/null
      printf '%s' "$?"
    }
    When call run_test_cmd_success
    The output should equal "0"
  End

  It "returns CHECK_FAILED when BRIK_TEST_COMMAND override fails"
    run_test_cmd_failure() {
      cat > "$BRIK_CONFIG_FILE" <<'YAML'
version: 1
project:
  name: test
  stack: node
test:
  command: "false"
YAML
      config.read "$BRIK_CONFIG_FILE" >/dev/null 2>&1 || true
      _stub_leaf_success
      local ctx
      ctx="$(context.create "test")" 2>/dev/null || ctx="$(mktemp)"
      stages.test "$ctx" 2>/dev/null
      printf '%s' "$?"
    }
    When call run_test_cmd_failure
    The output should equal "10"
  End

  It "returns CONFIG_ERROR when test framework is unsupported"
    run_test_bad_framework() {
      cat > "$BRIK_CONFIG_FILE" <<'YAML'
version: 1
project:
  name: test
  stack: node
test:
  framework: cobol-test
YAML
      config.read "$BRIK_CONFIG_FILE" >/dev/null 2>&1 || true
      brik.use() { :; }
      stacks.detect_from_framework() { return 1; }
      stacks.install_deps() { :; }
      local ctx
      ctx="$(context.create "test")" 2>/dev/null || ctx="$(mktemp)"
      stages.test "$ctx" 2>/dev/null
      printf '%s' "$?"
    }
    When call run_test_bad_framework
    The output should equal "7"
  End

  It "returns MISSING_DEP when stack cannot be auto-detected"
    run_test_auto_fail() {
      cat > "$BRIK_CONFIG_FILE" <<'YAML'
version: 1
project:
  name: test
YAML
      config.read "$BRIK_CONFIG_FILE" >/dev/null 2>&1 || true
      brik.use() { :; }
      stacks.detect() { return 1; }
      stacks.install_deps() { :; }
      local ctx
      ctx="$(context.create "test")" 2>/dev/null || ctx="$(mktemp)"
      stages.test "$ctx" 2>/dev/null
      printf '%s' "$?"
    }
    When call run_test_auto_fail
    The output should equal "3"
  End

  It "returns CONFIG_ERROR when stack module cannot be loaded"
    run_test_unsupported_stack() {
      brik.use() {
        case "$1" in
          stacks.node) return 1 ;;
          *) return 0 ;;
        esac
      }
      stacks.detect() { printf 'node'; return 0; }
      stacks.install_deps() { :; }
      local ctx
      ctx="$(context.create "test")" 2>/dev/null || ctx="$(mktemp)"
      stages.test "$ctx" 2>/dev/null
      printf '%s' "$?"
    }
    When call run_test_unsupported_stack
    The output should equal "7"
  End

  Describe "business.coverage.branch_pct recording"
    _stub_test_with_cov() {
      # shellcheck source=/dev/null
      . "$BRIK_HOME/lib/transverse/coverage.sh" 2>/dev/null || true
      brik.use() { :; }
      stacks.detect_from_framework() { printf 'node'; return 0; }
      stacks.detect() { printf 'node'; return 0; }
      stacks.node.test_cmd() { printf 'true'; return 0; }
      stacks.node.test() { printf 'true'; return 0; }
      stacks.install_deps() { :; }
      brik.coverage.summary() { :; }
    }

    _write_cobertura_with_branch() {
      mkdir -p "$BRIK_WORKSPACE/brik-artifacts/test/coverage"
      cat > "$BRIK_WORKSPACE/brik-artifacts/test/coverage/coverage.xml" <<'XML'
<?xml version="1.0" ?>
<coverage line-rate="0.8542" branch-rate="0.72" version="6.0">
</coverage>
XML
    }

    It "records business.coverage.branch_pct when cobertura branch-rate is present"
      run_branch() {
        _stub_test_with_cov
        _write_cobertura_with_branch
        export BRIK_TEST_REPORTS_ENABLED="true"
        local ctx
        ctx="$(context.create "test")" 2>/dev/null || ctx="$(mktemp)"
        stages.test "$ctx" >/dev/null 2>&1
        jq -r '.stages[] | select(.name == "test") | .business.coverage.branch_pct // "<missing>"' \
          "$BRIK_LOG_DIR/aggregate-report.json"
      }
      When call run_branch
      The output should equal "72.00"
    End

    It "still records line_pct when cobertura has both rates"
      run_both() {
        _stub_test_with_cov
        _write_cobertura_with_branch
        export BRIK_TEST_REPORTS_ENABLED="true"
        local ctx
        ctx="$(context.create "test")" 2>/dev/null || ctx="$(mktemp)"
        stages.test "$ctx" >/dev/null 2>&1
        jq -r '.stages[] | select(.name == "test") | .business.coverage.line_pct // "<missing>"' \
          "$BRIK_LOG_DIR/aggregate-report.json"
      }
      When call run_both
      The output should equal "85.42"
    End

    It "omits branch_pct when cobertura lacks branch-rate"
      run_no_branch() {
        _stub_test_with_cov
        mkdir -p "$BRIK_WORKSPACE/brik-artifacts/test/coverage"
        cat > "$BRIK_WORKSPACE/brik-artifacts/test/coverage/coverage.xml" <<'XML'
<?xml version="1.0" ?>
<coverage line-rate="0.8542" version="6.0">
</coverage>
XML
        export BRIK_TEST_REPORTS_ENABLED="true"
        local ctx
        ctx="$(context.create "test")" 2>/dev/null || ctx="$(mktemp)"
        stages.test "$ctx" >/dev/null 2>&1
        jq -r '.stages[] | select(.name == "test") | .business.coverage | has("branch_pct")' \
          "$BRIK_LOG_DIR/aggregate-report.json"
      }
      When call run_no_branch
      The output should equal "false"
    End
  End

  Describe "tech.tool fallback"
    _stub_with_framework() {
      brik.use() { :; }
      stacks.detect_from_framework() { printf 'node'; return 0; }
      stacks.detect() { printf 'node'; return 0; }
      stacks.node.test_cmd() { printf 'true'; return 0; }
      stacks.node.test() { printf 'true'; return 0; }
      stacks.install_deps() { :; }
    }

    It "records tech.tool from BRIK_TEST_TOOL when set"
      run_tool_explicit() {
        _stub_with_framework
        export BRIK_TEST_TOOL="vitest"
        local ctx
        ctx="$(context.create "test")" 2>/dev/null || ctx="$(mktemp)"
        stages.test "$ctx" >/dev/null 2>&1
        unset BRIK_TEST_TOOL
        jq -r '.stages[] | select(.name == "test") | .tech.tool // "<missing>"' \
          "$BRIK_LOG_DIR/aggregate-report.json"
      }
      When call run_tool_explicit
      The output should equal "vitest"
    End

    It "falls back tech.tool to BRIK_TEST_FRAMEWORK when BRIK_TEST_TOOL is empty"
      run_tool_fallback_framework() {
        _stub_with_framework
        unset BRIK_TEST_TOOL
        export BRIK_TEST_FRAMEWORK="jest"
        local ctx
        ctx="$(context.create "test")" 2>/dev/null || ctx="$(mktemp)"
        stages.test "$ctx" >/dev/null 2>&1
        unset BRIK_TEST_FRAMEWORK
        jq -r '.stages[] | select(.name == "test") | .tech.tool // "<missing>"' \
          "$BRIK_LOG_DIR/aggregate-report.json"
      }
      When call run_tool_fallback_framework
      The output should equal "jest"
    End

    It "prefers BRIK_TEST_TOOL over BRIK_TEST_FRAMEWORK when both are set"
      run_tool_priority() {
        _stub_with_framework
        export BRIK_TEST_TOOL="vitest"
        export BRIK_TEST_FRAMEWORK="jest"
        local ctx
        ctx="$(context.create "test")" 2>/dev/null || ctx="$(mktemp)"
        stages.test "$ctx" >/dev/null 2>&1
        unset BRIK_TEST_TOOL BRIK_TEST_FRAMEWORK
        jq -r '.stages[] | select(.name == "test") | .tech.tool // "<missing>"' \
          "$BRIK_LOG_DIR/aggregate-report.json"
      }
      When call run_tool_priority
      The output should equal "vitest"
    End
  End

  Describe "business.tests recording from JUnit XML"
    _stub_test_success() {
      brik.use() { :; }
      stacks.detect_from_framework() { printf 'node'; return 0; }
      stacks.detect() { printf 'node'; return 0; }
      stacks.node.test_cmd() { printf 'true'; return 0; }
      stacks.node.test() { printf 'true'; return 0; }
      stacks.install_deps() { :; }
    }

    _write_junit() {
      mkdir -p "$BRIK_WORKSPACE/reports"
      cat > "$BRIK_WORKSPACE/reports/junit.xml" <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<testsuites>
  <testsuite name="Suite" tests="10" failures="2" errors="0" skipped="1" time="3.456"/>
</testsuites>
XML
      export BRIK_TEST_JUNIT_PATH="reports/junit.xml"
    }

    It "records business.tests.total when JUnit file exists"
      run_total() {
        _stub_test_success
        _write_junit
        local ctx
        ctx="$(context.create "test")" 2>/dev/null || ctx="$(mktemp)"
        stages.test "$ctx" >/dev/null 2>&1
        jq -r '.stages[] | select(.name == "test") | .business.tests.total // "<missing>"' \
          "$BRIK_LOG_DIR/aggregate-report.json"
      }
      When call run_total
      The output should equal "10"
    End

    It "records business.tests.passed = total - failed - skipped"
      run_passed() {
        _stub_test_success
        _write_junit
        local ctx
        ctx="$(context.create "test")" 2>/dev/null || ctx="$(mktemp)"
        stages.test "$ctx" >/dev/null 2>&1
        jq -r '.stages[] | select(.name == "test") | .business.tests.passed // "<missing>"' \
          "$BRIK_LOG_DIR/aggregate-report.json"
      }
      When call run_passed
      The output should equal "7"
    End

    It "records business.tests.failed and skipped"
      run_failed_skipped() {
        _stub_test_success
        _write_junit
        local ctx
        ctx="$(context.create "test")" 2>/dev/null || ctx="$(mktemp)"
        stages.test "$ctx" >/dev/null 2>&1
        jq -c '.stages[] | select(.name == "test") | {f: .business.tests.failed, s: .business.tests.skipped}' \
          "$BRIK_LOG_DIR/aggregate-report.json"
      }
      When call run_failed_skipped
      The output should equal '{"f":2,"s":1}'
    End

    It "records business.tests.duration_ms"
      run_dur() {
        _stub_test_success
        _write_junit
        local ctx
        ctx="$(context.create "test")" 2>/dev/null || ctx="$(mktemp)"
        stages.test "$ctx" >/dev/null 2>&1
        jq -r '.stages[] | select(.name == "test") | .business.tests.duration_ms // "<missing>"' \
          "$BRIK_LOG_DIR/aggregate-report.json"
      }
      When call run_dur
      The output should equal "3456"
    End

    It "omits business.tests when JUnit path does not point to an existing file"
      run_omit() {
        _stub_test_success
        export BRIK_TEST_JUNIT_PATH="reports/missing.xml"
        local ctx
        ctx="$(context.create "test")" 2>/dev/null || ctx="$(mktemp)"
        stages.test "$ctx" >/dev/null 2>&1
        jq -r '[.stages[] | select(.name == "test") | .business.tests // null | select(. != null)] | length' \
          "$BRIK_LOG_DIR/aggregate-report.json"
      }
      When call run_omit
      The output should equal "0"
    End

    It "records business.tests even when tests fail (rc != 0)"
      run_on_failure() {
        brik.use() { :; }
        stacks.detect_from_framework() { printf 'node'; return 0; }
        stacks.detect() { printf 'node'; return 0; }
        stacks.node.test_cmd() { printf 'false'; return 0; }
        stacks.node.test() { printf 'false'; return 0; }
        stacks.install_deps() { :; }
        _write_junit
        local ctx
        ctx="$(context.create "test")" 2>/dev/null || ctx="$(mktemp)"
        stages.test "$ctx" >/dev/null 2>&1
        jq -r '.stages[] | select(.name == "test") | .business.tests.total // "<missing>"' \
          "$BRIK_LOG_DIR/aggregate-report.json"
      }
      When call run_on_failure
      The output should equal "10"
    End
  End

  Describe "with BRIK_TEST_COVERAGE_THRESHOLD"
    # These stubs cover both Tier-2 paths: with and without BRIK_TEST_FRAMEWORK.
    # stacks.node.test_cmd is needed when BRIK_TEST_FRAMEWORK is set (jest default
    # for the node stack). stacks.node.test is needed otherwise.
    _stub_tier2_success_gate() {
      brik.use() { :; }
      stacks.detect_from_framework() { printf 'node'; return 0; }
      stacks.detect() { printf 'node'; return 0; }
      stacks.node.test_cmd() { printf 'true'; return 0; }
      stacks.node.test() { printf 'true'; return 0; }
      stacks.install_deps() { :; }
    }

    _stub_tier2_failure_gate() {
      brik.use() { :; }
      stacks.detect_from_framework() { printf 'node'; return 0; }
      stacks.detect() { printf 'node'; return 0; }
      stacks.node.test_cmd() { printf 'false'; return 0; }
      stacks.node.test() { printf 'false'; return 0; }
      stacks.install_deps() { :; }
    }

    It "(a) calls brik.coverage.gate with threshold when reports enabled and threshold set"
      run_gate_called() {
        _stub_tier2_success_gate
        export BRIK_TEST_REPORTS_ENABLED="true"
        export BRIK_TEST_COVERAGE_THRESHOLD="80"
        # Use a sentinel file to communicate across the subshell boundary.
        local sentinel
        sentinel="$(mktemp)"
        rm -f "$sentinel"
        brik.coverage.summary() { :; }
        brik.coverage.gate() { touch "$sentinel"; return 0; }
        export -f brik.coverage.summary brik.coverage.gate
        export sentinel
        local ctx
        ctx="$(context.create "test")" 2>/dev/null || ctx="$(mktemp)"
        stages.test "$ctx" >/dev/null 2>&1
        if [[ -f "$sentinel" ]]; then
          printf '1'
        else
          printf '0'
        fi
        rm -f "$sentinel"
      }
      When call run_gate_called
      The output should equal "1"
    End

    It "(b) does NOT call brik.coverage.gate when BRIK_TEST_COVERAGE_THRESHOLD is unset"
      run_gate_not_called() {
        _stub_tier2_success_gate
        export BRIK_TEST_REPORTS_ENABLED="true"
        unset BRIK_TEST_COVERAGE_THRESHOLD
        local sentinel
        sentinel="$(mktemp)"
        rm -f "$sentinel"
        brik.coverage.summary() { :; }
        brik.coverage.gate() { touch "$sentinel"; return 0; }
        export -f brik.coverage.summary brik.coverage.gate
        export sentinel
        local ctx
        ctx="$(context.create "test")" 2>/dev/null || ctx="$(mktemp)"
        stages.test "$ctx" >/dev/null 2>&1
        if [[ -f "$sentinel" ]]; then
          printf '1'
        else
          printf '0'
        fi
        rm -f "$sentinel"
      }
      When call run_gate_not_called
      The output should equal "0"
    End

    It "(c) returns CHECK_FAILED (10) when tests pass but gate returns 10"
      run_gate_blocks() {
        _stub_tier2_success_gate
        export BRIK_TEST_REPORTS_ENABLED="true"
        export BRIK_TEST_COVERAGE_THRESHOLD="90"
        brik.coverage.summary() { :; }
        brik.coverage.gate() { return 10; }
        export -f brik.coverage.summary brik.coverage.gate
        local ctx
        ctx="$(context.create "test")" 2>/dev/null || ctx="$(mktemp)"
        stages.test "$ctx" >/dev/null 2>&1
        printf '%s' "$?"
      }
      When call run_gate_blocks
      The output should equal "10"
    End

    It "(d) preserves test failure rc when tests fail and gate also returns 10"
      run_gate_no_override() {
        _stub_tier2_failure_gate
        export BRIK_TEST_REPORTS_ENABLED="true"
        export BRIK_TEST_COVERAGE_THRESHOLD="90"
        brik.coverage.summary() { :; }
        brik.coverage.gate() { return 10; }
        export -f brik.coverage.summary brik.coverage.gate
        local ctx
        ctx="$(context.create "test")" 2>/dev/null || ctx="$(mktemp)"
        stages.test "$ctx" >/dev/null 2>&1
        printf '%s' "$?"
      }
      When call run_gate_no_override
      The output should equal "10"
    End

    It "(e) surfaces BRIK_EXIT_INVALID_INPUT directly when threshold is malformed"
      run_gate_invalid_input() {
        _stub_tier2_success_gate
        export BRIK_TEST_REPORTS_ENABLED="true"
        export BRIK_TEST_COVERAGE_THRESHOLD="abc"
        brik.coverage.summary() { :; }
        brik.coverage.gate() { return "$BRIK_EXIT_INVALID_INPUT"; }
        export -f brik.coverage.summary brik.coverage.gate
        local ctx
        ctx="$(context.create "test")" 2>/dev/null || ctx="$(mktemp)"
        stages.test "$ctx" >/dev/null 2>&1
        printf '%s' "$?"
      }
      When call run_gate_invalid_input
      The output should equal "$BRIK_EXIT_INVALID_INPUT"
    End
  End
End

Describe "stacks.install_deps (test mode)"
  Include "$BRIK_HOME/lib/pipeline/stage.sh"
  Include "$BRIK_HOME/lib/pipeline/loader.sh"
  Include "$BRIK_HOME/lib/stages/test.sh"
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
        stacks.install_deps "$DEPS_WS" test 2>/dev/null
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
        stacks.install_deps "$DEPS_WS" test 2>/dev/null
      }
      When call run_node_skip
      The status should be success
    End
  End

  Describe "python stack"
    It "installs from pyproject.toml with dev extras"
      run_python_pyproject() {
        export BRIK_BUILD_STACK="python"
        printf '[project]\nname = "test"\n' > "${DEPS_WS}/pyproject.toml"
        mock.create_logging "pip" "$MOCK_LOG"
        mock.activate
        stacks.install_deps "$DEPS_WS" test 2>/dev/null
        grep -q 'pip install -e' "$MOCK_LOG"
      }
      When call run_python_pyproject
      The status should be success
    End

    It "installs from requirements.txt"
      run_python_req() {
        export BRIK_BUILD_STACK="python"
        rm -f "${DEPS_WS}/pyproject.toml"
        printf 'pytest\n' > "${DEPS_WS}/requirements.txt"
        mock.create_logging "pip" "$MOCK_LOG"
        mock.activate
        stacks.install_deps "$DEPS_WS" test 2>/dev/null
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
        stacks.install_deps "$DEPS_WS" test 2>/dev/null
        [[ ! -f "$MOCK_LOG" ]]
      }
      When call run_python_noop
      The status should be success
    End
  End

  Describe "java stack"
    It "does nothing (Maven/Gradle handle deps)"
      run_java_noop() {
        export BRIK_BUILD_STACK="java"
        rm -f "$MOCK_LOG"
        stacks.install_deps "$DEPS_WS" test 2>/dev/null
        [[ ! -f "$MOCK_LOG" ]]
      }
      When call run_java_noop
      The status should be success
    End
  End

  Describe "rust stack"
    It "does nothing (Cargo handles deps)"
      run_rust_noop() {
        export BRIK_BUILD_STACK="rust"
        rm -f "$MOCK_LOG"
        stacks.install_deps "$DEPS_WS" test 2>/dev/null
        [[ ! -f "$MOCK_LOG" ]]
      }
      When call run_rust_noop
      The status should be success
    End
  End

  Describe "dotnet stack"
    It "runs dotnet restore"
      run_dotnet_restore() {
        export BRIK_BUILD_STACK="dotnet"
        mock.create_logging "dotnet" "$MOCK_LOG"
        mock.activate
        stacks.install_deps "$DEPS_WS" test 2>/dev/null
        grep -q "dotnet restore" "$MOCK_LOG"
      }
      When call run_dotnet_restore
      The status should be success
    End
  End

  Describe "unknown stack"
    It "does nothing for unrecognized stack"
      run_unknown_stack() {
        export BRIK_BUILD_STACK="go"
        rm -f "$MOCK_LOG"
        stacks.install_deps "$DEPS_WS" test 2>/dev/null
        [[ ! -f "$MOCK_LOG" ]]
      }
      When call run_unknown_stack
      The status should be success
    End

    It "does nothing when BRIK_BUILD_STACK is empty"
      run_empty_stack() {
        unset BRIK_BUILD_STACK
        rm -f "$MOCK_LOG"
        stacks.install_deps "$DEPS_WS" test 2>/dev/null
        [[ ! -f "$MOCK_LOG" ]]
      }
      When call run_empty_stack
      The status should be success
    End
  End
End
