#shellcheck shell=bash disable=SC2148,SC2317,SC2329

Describe "stages.scan"
  Include "$BRIK_HOME/lib/pipeline/stage.sh"
  Include "$BRIK_HOME/lib/pipeline/loader.sh"
  Include "$BRIK_HOME/lib/pipeline/report.sh"
  Include "$BRIK_HOME/lib/transverse/config.sh"
  Include "$BRIK_HOME/lib/transverse/sarif.sh"
  Include "$BRIK_HOME/lib/transverse/sbom.sh"
  Include "$BRIK_HOME/lib/stages/verify/scan/scan.sh"
  Include "$BRIK_HOME/lib/stages/scan.sh"

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
    export BRIK_RUN_ID="scan-spec-fixture"
    config.read "$BRIK_CONFIG_FILE" >/dev/null 2>&1 || true
    report.init >/dev/null 2>&1 || true
  }
  cleanup_env() {
    rm -f "$BRIK_CONFIG_FILE"
    rm -rf "$BRIK_WORKSPACE" "$BRIK_LOG_DIR"
    unset BRIK_SECURITY_DEPS_TOOL BRIK_SECURITY_DEPS_COMMAND \
          BRIK_SECURITY_DEPS_SEVERITY BRIK_SECURITY_SECRETS_TOOL \
          BRIK_SECURITY_SECRETS_COMMAND BRIK_SECURITY_SEVERITY_THRESHOLD \
          BRIK_RUN_ID 2>/dev/null || true
  }

  read_scan_tech() {
    local key="$1"
    jq -r --arg k "$key" \
      '.stages[] | select(.name == "scan") | .tech[$k] // empty' \
      "$BRIK_LOG_DIR/pipeline-report.json" 2>/dev/null
  }

  read_scan_tech_json() {
    local key="$1"
    jq -c --arg k "$key" \
      '.stages[] | select(.name == "scan") | .tech[$k] // empty' \
      "$BRIK_LOG_DIR/pipeline-report.json" 2>/dev/null
  }
  Before 'setup_env'
  After 'cleanup_env'

  It "is callable as a function"
    callable_check() { declare -f stages.scan >/dev/null; }
    When call callable_check
    The status should be success
  End

  It "records scan.tech.deps as a nested object with the deps tool"
    run_scan_deps_object() {
      verify.scan.run() { return 0; }
      brik.use() { :; }
      stacks.install_deps() { :; }
      local ctx
      ctx="$(context.create "scan")" 2>/dev/null || ctx="$(mktemp)"
      stages.scan "$ctx" >/dev/null 2>&1
      read_scan_tech_json "deps"
    }
    When call run_scan_deps_object
    The output should equal '{"tool":"osv-scanner"}'
  End

  It "records scan.tech.secret as a nested object with the secrets tool"
    run_scan_secret_object() {
      verify.scan.run() { return 0; }
      brik.use() { :; }
      stacks.install_deps() { :; }
      local ctx
      ctx="$(context.create "scan")" 2>/dev/null || ctx="$(mktemp)"
      stages.scan "$ctx" >/dev/null 2>&1
      read_scan_tech_json "secret"
    }
    When call run_scan_secret_object
    The output should equal '{"tool":"gitleaks"}'
  End

  It "records scan.tech.severity_threshold from default 'high'"
    run_scan_severity() {
      verify.scan.run() { return 0; }
      brik.use() { :; }
      stacks.install_deps() { :; }
      local ctx
      ctx="$(context.create "scan")" 2>/dev/null || ctx="$(mktemp)"
      stages.scan "$ctx" >/dev/null 2>&1
      read_scan_tech "severity_threshold"
    }
    When call run_scan_severity
    The output should equal "high"
  End

  It "records scan.tech.severity_threshold from .security.deps.severity when set"
    run_scan_severity_custom() {
      cat > "$BRIK_CONFIG_FILE" <<'YAML'
version: 1
project:
  name: test
  stack: node
security:
  deps:
    severity: critical
YAML
      config.read "$BRIK_CONFIG_FILE" >/dev/null 2>&1 || true
      verify.scan.run() { return 0; }
      brik.use() { :; }
      stacks.install_deps() { :; }
      local ctx
      ctx="$(context.create "scan")" 2>/dev/null || ctx="$(mktemp)"
      stages.scan "$ctx" >/dev/null 2>&1
      read_scan_tech "severity_threshold"
    }
    When call run_scan_severity_custom
    The output should equal "critical"
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
        verify.scan.deps.run() { return 0; }
        verify.scan.secret.run() { return 0; }
        local ctx
        ctx="$(context.create "scan")" 2>/dev/null || ctx="$(mktemp)"
        stages.scan "$ctx"
      }
      When call run_scan_defaults
      The status should be success
      The error should be present
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
        verify.scan.deps.run() { return 0; }
        verify.scan.secret.run() { return 0; }
        local ctx
        ctx="$(context.create "scan")" 2>/dev/null || ctx="$(mktemp)"
        stages.scan "$ctx"
      }
      When call run_deps
      The status should be success
      The error should be present
    End

    It "sets status to failed when deps scan fails"
      run_deps_fail() {
        verify.scan.deps.run() { return 1; }
        verify.scan.secret.run() { return 0; }
        local ctx
        ctx="$(context.create "scan")" 2>/dev/null || ctx="$(mktemp)"
        stages.scan "$ctx"
      }
      When call run_deps_fail
      The status should equal 10
      The error should be present
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
        verify.scan.deps.run() { return 0; }
        verify.scan.secret.run() { return 0; }
        local ctx
        ctx="$(context.create "scan")" 2>/dev/null || ctx="$(mktemp)"
        stages.scan "$ctx"
      }
      When call run_secrets
      The status should be success
      The error should be present
    End

    It "sets status to failed when secret scan fails"
      run_secrets_fail() {
        verify.scan.deps.run() { return 0; }
        verify.scan.secret.run() { return 1; }
        local ctx
        ctx="$(context.create "scan")" 2>/dev/null || ctx="$(mktemp)"
        stages.scan "$ctx"
      }
      When call run_secrets_fail
      The status should equal 10
      The error should be present
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
        verify.scan.deps.run() { return 0; }
        verify.scan.secret.run() { return 0; }
        local ctx
        ctx="$(context.create "scan")" 2>/dev/null || ctx="$(mktemp)"
        stages.scan "$ctx"
      }
      When call run_both
      The status should be success
      The error should be present
    End

    It "fails if any scan fails"
      run_both_fail() {
        verify.scan.deps.run() { return 0; }
        verify.scan.secret.run() { return 1; }
        local ctx
        ctx="$(context.create "scan")" 2>/dev/null || ctx="$(mktemp)"
        stages.scan "$ctx"
      }
      When call run_both_fail
      The status should equal 10
      The error should be present
    End
  End

  Describe "business.* aggregation from target/{scan,secret}.sarif and target/sbom.cdx.json"
    read_scan_business_json() {
      local key="$1"
      jq -c --arg k "$key" \
        '.stages[] | select(.name == "scan") | .business[$k] // empty' \
        "$BRIK_LOG_DIR/pipeline-report.json" 2>/dev/null
    }

    setup_scan_with_artifacts() {
      mkdir -p "$BRIK_WORKSPACE/target"
    }
    Before 'setup_scan_with_artifacts'

    It "records business.deps.vulnerabilities.total from scan SARIF"
      run_total() {
        cp "${BRIK_HOME}/spec/fixtures/sarif/osv-scanner.sarif" "$BRIK_WORKSPACE/target/scan.sarif"
        verify.scan.run() { return 0; }
        brik.use() { :; }
        local ctx
        ctx="$(context.create "scan")" 2>/dev/null || ctx="$(mktemp)"
        stages.scan "$ctx" >/dev/null 2>&1
        read_scan_business_json "deps" | jq -r '.vulnerabilities.total'
      }
      When call run_total
      The output should equal "1"
    End

    It "records business.deps.vulnerabilities.by_severity from scan SARIF"
      run_sev() {
        cp "${BRIK_HOME}/spec/fixtures/sarif/osv-scanner.sarif" "$BRIK_WORKSPACE/target/scan.sarif"
        verify.scan.run() { return 0; }
        brik.use() { :; }
        local ctx
        ctx="$(context.create "scan")" 2>/dev/null || ctx="$(mktemp)"
        stages.scan "$ctx" >/dev/null 2>&1
        read_scan_business_json "deps" | jq -c '.vulnerabilities.by_severity'
      }
      When call run_sev
      The output should equal '{"critical":0,"high":0,"medium":1,"low":0,"info":0}'
    End

    It "records business.deps.affected_packages from CycloneDX SBOM"
      run_pkg() {
        cp "${BRIK_HOME}/spec/fixtures/sarif/osv-scanner.sarif" "$BRIK_WORKSPACE/target/scan.sarif"
        cp "${BRIK_HOME}/spec/fixtures/sbom/osv-scanner.cdx.json" "$BRIK_WORKSPACE/target/sbom.cdx.json"
        verify.scan.run() { return 0; }
        brik.use() { :; }
        local ctx
        ctx="$(context.create "scan")" 2>/dev/null || ctx="$(mktemp)"
        stages.scan "$ctx" >/dev/null 2>&1
        read_scan_business_json "deps" | jq -r '.affected_packages'
      }
      When call run_pkg
      The output should equal "1"
    End

    It "records business.deps.sbom_path when SBOM is present"
      run_sbom_path() {
        cp "${BRIK_HOME}/spec/fixtures/sarif/osv-scanner.sarif" "$BRIK_WORKSPACE/target/scan.sarif"
        cp "${BRIK_HOME}/spec/fixtures/sbom/osv-scanner.cdx.json" "$BRIK_WORKSPACE/target/sbom.cdx.json"
        verify.scan.run() { return 0; }
        brik.use() { :; }
        local ctx
        ctx="$(context.create "scan")" 2>/dev/null || ctx="$(mktemp)"
        stages.scan "$ctx" >/dev/null 2>&1
        read_scan_business_json "deps" | jq -r '.sbom_path'
      }
      When call run_sbom_path
      The output should equal "target/sbom.cdx.json"
    End

    It "records business.secret.findings_count from secret SARIF"
      run_secret_count() {
        cp "${BRIK_HOME}/spec/fixtures/sarif/gitleaks.sarif" "$BRIK_WORKSPACE/target/secret.sarif"
        verify.scan.run() { return 0; }
        brik.use() { :; }
        local ctx
        ctx="$(context.create "scan")" 2>/dev/null || ctx="$(mktemp)"
        stages.scan "$ctx" >/dev/null 2>&1
        read_scan_business_json "secret" | jq -r '.findings_count'
      }
      When call run_secret_count
      The output should equal "1"
    End

    It "records business.secret.report = {format, path}"
      run_secret_report() {
        cp "${BRIK_HOME}/spec/fixtures/sarif/gitleaks.sarif" "$BRIK_WORKSPACE/target/secret.sarif"
        verify.scan.run() { return 0; }
        brik.use() { :; }
        local ctx
        ctx="$(context.create "scan")" 2>/dev/null || ctx="$(mktemp)"
        stages.scan "$ctx" >/dev/null 2>&1
        read_scan_business_json "secret" | jq -c '.report'
      }
      When call run_secret_report
      The output should equal '{"format":"sarif","path":"target/secret.sarif"}'
    End

    It "records business.report rollup pointing at target/scan.sarif"
      run_rollup() {
        cp "${BRIK_HOME}/spec/fixtures/sarif/osv-scanner.sarif" "$BRIK_WORKSPACE/target/scan.sarif"
        verify.scan.run() { return 0; }
        brik.use() { :; }
        local ctx
        ctx="$(context.create "scan")" 2>/dev/null || ctx="$(mktemp)"
        stages.scan "$ctx" >/dev/null 2>&1
        read_scan_business_json "report"
      }
      When call run_rollup
      The output should equal '{"format":"sarif","path":"target/scan.sarif"}'
    End

    It "honors security.deps.output_path when set"
      run_custom_deps_path() {
        cat > "$BRIK_CONFIG_FILE" <<'YAML'
version: 1
project:
  name: test
  stack: node
security:
  deps:
    output_path: build/scan/deps.sarif
YAML
        config.read "$BRIK_CONFIG_FILE" >/dev/null 2>&1 || true
        mkdir -p "$BRIK_WORKSPACE/build/scan"
        cp "${BRIK_HOME}/spec/fixtures/sarif/osv-scanner.sarif" "$BRIK_WORKSPACE/build/scan/deps.sarif"
        verify.scan.run() { return 0; }
        brik.use() { :; }
        local ctx
        ctx="$(context.create "scan")" 2>/dev/null || ctx="$(mktemp)"
        stages.scan "$ctx" >/dev/null 2>&1
        read_scan_business_json "report" | jq -r '.path'
      }
      When call run_custom_deps_path
      The output should equal "build/scan/deps.sarif"
    End

    It "omits business.* entirely when no SARIF or SBOM was produced"
      run_no_artifacts() {
        verify.scan.run() { return 0; }
        brik.use() { :; }
        local ctx
        ctx="$(context.create "scan")" 2>/dev/null || ctx="$(mktemp)"
        stages.scan "$ctx" >/dev/null 2>&1
        jq -c '.stages[] | select(.name == "scan") | .business // {}' \
          "$BRIK_LOG_DIR/pipeline-report.json" 2>/dev/null
      }
      When call run_no_artifacts
      The output should equal "{}"
    End
  End
End

Describe "stacks.install_deps (scan mode)"
  Include "$BRIK_HOME/lib/pipeline/stage.sh"
  Include "$BRIK_HOME/lib/pipeline/loader.sh"
  Include "$BRIK_HOME/lib/stages/scan.sh"
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
        stacks.install_deps "$DEPS_WS" scan 2>/dev/null
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
        stacks.install_deps "$DEPS_WS" scan 2>/dev/null
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
        stacks.install_deps "$DEPS_WS" scan 2>/dev/null
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
        mock.create_logging "pip" "$MOCK_LOG"
        mock.activate
        stacks.install_deps "$DEPS_WS" scan 2>/dev/null
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
        stacks.install_deps "$DEPS_WS" scan 2>/dev/null
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
        stacks.install_deps "$DEPS_WS" scan 2>/dev/null
        [[ ! -f "$MOCK_LOG" ]]
      }
      When call run_unknown_stack
      The status should be success
    End

    It "does nothing when BRIK_BUILD_STACK is empty"
      run_empty_stack() {
        unset BRIK_BUILD_STACK
        rm -f "$MOCK_LOG"
        stacks.install_deps "$DEPS_WS" scan 2>/dev/null
        [[ ! -f "$MOCK_LOG" ]]
      }
      When call run_empty_stack
      The status should be success
    End
  End
End
