#shellcheck shell=bash disable=SC2148,SC2317,SC2329

Describe "stages.sast"
  Include "$BRIK_HOME/lib/pipeline/stage.sh"
  Include "$BRIK_HOME/lib/pipeline/loader.sh"
  Include "$BRIK_HOME/lib/pipeline/report.sh"
  Include "$BRIK_HOME/lib/transverse/config.sh"
  Include "$BRIK_HOME/lib/transverse/sarif.sh"
  Include "$BRIK_HOME/lib/stages/verify/scan/scan.sh"
  Include "$BRIK_HOME/lib/stages/sast.sh"

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
    export BRIK_RUN_ID="sast-spec-fixture"
    config.read "$BRIK_CONFIG_FILE" >/dev/null 2>&1 || true
    report.init >/dev/null 2>&1 || true
  }
  cleanup_env() {
    rm -f "$BRIK_CONFIG_FILE"
    rm -rf "$BRIK_WORKSPACE" "$BRIK_LOG_DIR"
    unset BRIK_SECURITY_SAST_TOOL BRIK_SECURITY_SAST_COMMAND \
          BRIK_SECURITY_SAST_RULESET BRIK_SECURITY_LICENSE_ALLOWED \
          BRIK_SECURITY_LICENSE_DENIED BRIK_SECURITY_IAC_TOOL \
          BRIK_SECURITY_IAC_COMMAND BRIK_SECURITY_SEVERITY_THRESHOLD \
          BRIK_RUN_ID 2>/dev/null || true
  }

  read_sast_tech() {
    local key="$1"
    jq -r --arg k "$key" \
      '.stages[] | select(.name == "sast") | .tech[$k] // empty' \
      "$BRIK_LOG_DIR/aggregate-report.json" 2>/dev/null
  }
  Before 'setup_env'
  After 'cleanup_env'

  It "is callable as a function"
    callable_check() { declare -f stages.sast >/dev/null; }
    When call callable_check
    The status should be success
  End

  It "records sast.tech.tool defaulting to semgrep"
    run_sast_default_tool() {
      verify.scan.run() { return 0; }
      brik.use() { :; }
      local ctx
      ctx="$(context.create "sast")" 2>/dev/null || ctx="$(mktemp)"
      stages.sast "$ctx" >/dev/null 2>&1
      read_sast_tech "tool"
    }
    When call run_sast_default_tool
    The output should equal "semgrep"
  End

  It "records sast.tech.tool from .security.sast.tool when set"
    run_sast_custom_tool() {
      cat > "$BRIK_CONFIG_FILE" <<'YAML'
version: 1
project:
  name: test
  stack: node
security:
  sast:
    tool: bandit
YAML
      config.read "$BRIK_CONFIG_FILE" >/dev/null 2>&1 || true
      verify.scan.run() { return 0; }
      brik.use() { :; }
      local ctx
      ctx="$(context.create "sast")" 2>/dev/null || ctx="$(mktemp)"
      stages.sast "$ctx" >/dev/null 2>&1
      read_sast_tech "tool"
    }
    When call run_sast_custom_tool
    The output should equal "bandit"
  End

  It "records sast.tech.ruleset from .security.sast.ruleset when set"
    run_sast_ruleset() {
      cat > "$BRIK_CONFIG_FILE" <<'YAML'
version: 1
project:
  name: test
  stack: node
security:
  sast:
    ruleset: "p/owasp-top-ten"
YAML
      config.read "$BRIK_CONFIG_FILE" >/dev/null 2>&1 || true
      verify.scan.run() { return 0; }
      brik.use() { :; }
      local ctx
      ctx="$(context.create "sast")" 2>/dev/null || ctx="$(mktemp)"
      stages.sast "$ctx" >/dev/null 2>&1
      read_sast_tech "ruleset"
    }
    When call run_sast_ruleset
    The output should equal "p/owasp-top-ten"
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

    It "defaults to semgrep and returns 0 when the scan succeeds"
      run_sast_defaults() {
        verify.scan.sast.run() { return 0; }
        local ctx
        ctx="$(context.create "sast")" 2>/dev/null || ctx="$(mktemp)"
        stages.sast "$ctx"
      }
      When call run_sast_defaults
      The status should be success
      The error should be present
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

    It "returns 0 when the SAST scan succeeds"
      run_sast() {
        brik.use() { :; }
        verify.scan.sast.run() { return 0; }
        local ctx
        ctx="$(context.create "sast")" 2>/dev/null || ctx="$(mktemp)"
        stages.sast "$ctx"
      }
      When call run_sast
      The status should be success
      The error should be present
    End

    It "returns non-zero when the SAST scan fails"
      run_sast_fail() {
        brik.use() { :; }
        verify.scan.sast.run() { return 1; }
        local ctx
        ctx="$(context.create "sast")" 2>/dev/null || ctx="$(mktemp)"
        stages.sast "$ctx"
      }
      When call run_sast_fail
      The status should equal 10
      The error should be present
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

    It "returns 0 when the license scan succeeds"
      run_license() {
        brik.use() { :; }
        verify.scan.sast.run() { return 0; }
        verify.scan.license.run() { return 0; }
        local ctx
        ctx="$(context.create "sast")" 2>/dev/null || ctx="$(mktemp)"
        stages.sast "$ctx"
      }
      When call run_license
      The status should be success
      The error should be present
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

    It "returns 0 when the IaC scan succeeds"
      run_iac() {
        brik.use() { :; }
        verify.scan.sast.run() { return 0; }
        verify.scan.iac.run() { return 0; }
        local ctx
        ctx="$(context.create "sast")" 2>/dev/null || ctx="$(mktemp)"
        stages.sast "$ctx"
      }
      When call run_iac
      The status should be success
      The error should be present
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

    It "returns 0 when all configured scans pass"
      run_multi() {
        brik.use() { :; }
        verify.scan.sast.run() { return 0; }
        verify.scan.license.run() { return 0; }
        local ctx
        ctx="$(context.create "sast")" 2>/dev/null || ctx="$(mktemp)"
        stages.sast "$ctx"
      }
      When call run_multi
      The status should be success
      The error should be present
    End

    It "returns non-zero if any scan fails"
      run_multi_fail() {
        brik.use() { :; }
        verify.scan.sast.run() { return 0; }
        verify.scan.license.run() { return 1; }
        local ctx
        ctx="$(context.create "sast")" 2>/dev/null || ctx="$(mktemp)"
        stages.sast "$ctx"
      }
      When call run_multi_fail
      The status should equal 10
      The error should be present
    End
  End

  Describe "business.* aggregation from brik-artifacts/sast/sast.sarif"
    read_sast_business_json() {
      local key="$1"
      jq -c --arg k "$key" \
        '.stages[] | select(.name == "sast") | .business[$k] // empty' \
        "$BRIK_LOG_DIR/aggregate-report.json" 2>/dev/null
    }

    setup_sast_with_sarif() {
      mkdir -p "$BRIK_WORKSPACE/brik-artifacts/sast"
    }
    Before 'setup_sast_with_sarif'

    It "records business.findings.total from semgrep SARIF"
      run_total() {
        cp "${BRIK_HOME}/spec/fixtures/sarif/semgrep.sarif" "$BRIK_WORKSPACE/brik-artifacts/sast/sast.sarif"
        verify.scan.run() { return 0; }
        brik.use() { :; }
        local ctx
        ctx="$(context.create "sast")" 2>/dev/null || ctx="$(mktemp)"
        stages.sast "$ctx" >/dev/null 2>&1
        read_sast_business_json "findings" | jq -r '.total'
      }
      When call run_total
      The output should equal "15"
    End

    It "records business.findings.by_severity from semgrep SARIF"
      run_sev() {
        cp "${BRIK_HOME}/spec/fixtures/sarif/semgrep.sarif" "$BRIK_WORKSPACE/brik-artifacts/sast/sast.sarif"
        verify.scan.run() { return 0; }
        brik.use() { :; }
        local ctx
        ctx="$(context.create "sast")" 2>/dev/null || ctx="$(mktemp)"
        stages.sast "$ctx" >/dev/null 2>&1
        read_sast_business_json "findings" | jq -c '.by_severity'
      }
      When call run_sev
      The output should equal '{"critical":0,"high":1,"medium":14,"low":0,"info":0}'
    End

    It "records business.findings.cwe (sorted, deduped) from semgrep SARIF"
      run_cwe() {
        cp "${BRIK_HOME}/spec/fixtures/sarif/semgrep.sarif" "$BRIK_WORKSPACE/brik-artifacts/sast/sast.sarif"
        verify.scan.run() { return 0; }
        brik.use() { :; }
        local ctx
        ctx="$(context.create "sast")" 2>/dev/null || ctx="$(mktemp)"
        stages.sast "$ctx" >/dev/null 2>&1
        read_sast_business_json "findings" | jq -c '.cwe'
      }
      When call run_cwe
      The output should equal '["CWE-20","CWE-250"]'
    End

    It "records business.report = {format, path}"
      run_report() {
        cp "${BRIK_HOME}/spec/fixtures/sarif/semgrep.sarif" "$BRIK_WORKSPACE/brik-artifacts/sast/sast.sarif"
        verify.scan.run() { return 0; }
        brik.use() { :; }
        local ctx
        ctx="$(context.create "sast")" 2>/dev/null || ctx="$(mktemp)"
        stages.sast "$ctx" >/dev/null 2>&1
        read_sast_business_json "report"
      }
      When call run_report
      The output should equal '{"format":"sarif","path":"brik-artifacts/sast/sast.sarif"}'
    End

    It "honors a custom output_path from .security.sast.output_path"
      run_custom_path() {
        cat > "$BRIK_CONFIG_FILE" <<'YAML'
version: 1
project:
  name: test
  stack: node
security:
  sast:
    output_format: sarif
    output_path: build/security/sast.sarif
YAML
        config.read "$BRIK_CONFIG_FILE" >/dev/null 2>&1 || true
        mkdir -p "$BRIK_WORKSPACE/build/security"
        cp "${BRIK_HOME}/spec/fixtures/sarif/semgrep.sarif" "$BRIK_WORKSPACE/build/security/sast.sarif"
        verify.scan.run() { return 0; }
        brik.use() { :; }
        local ctx
        ctx="$(context.create "sast")" 2>/dev/null || ctx="$(mktemp)"
        stages.sast "$ctx" >/dev/null 2>&1
        read_sast_business_json "report"
      }
      When call run_custom_path
      The output should equal '{"format":"sarif","path":"build/security/sast.sarif"}'
    End

    It "omits business.* entirely when no SARIF was produced"
      run_no_sarif() {
        verify.scan.run() { return 0; }
        brik.use() { :; }
        local ctx
        ctx="$(context.create "sast")" 2>/dev/null || ctx="$(mktemp)"
        stages.sast "$ctx" >/dev/null 2>&1
        jq -c '.stages[] | select(.name == "sast") | .business // {}' \
          "$BRIK_LOG_DIR/aggregate-report.json" 2>/dev/null
      }
      When call run_no_sarif
      The output should equal "{}"
    End

    It "records empty business.findings.cwe when the SARIF has no CWE tags"
      run_no_cwe() {
        cp "${BRIK_HOME}/spec/fixtures/sarif/eslint.sarif" "$BRIK_WORKSPACE/brik-artifacts/sast/sast.sarif"
        verify.scan.run() { return 0; }
        brik.use() { :; }
        local ctx
        ctx="$(context.create "sast")" 2>/dev/null || ctx="$(mktemp)"
        stages.sast "$ctx" >/dev/null 2>&1
        read_sast_business_json "findings" | jq -c '.cwe'
      }
      When call run_no_cwe
      The output should equal '[]'
    End
  End
End
