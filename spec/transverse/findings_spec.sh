#shellcheck shell=bash disable=SC2148,SC2317,SC2329

Describe "transverse/findings.sh"
  Include "$BRIK_HOME/lib/pipeline/loader.sh"
  Include "$BRIK_HOME/lib/pipeline/report.sh"
  Include "$BRIK_HOME/lib/transverse/sarif.sh"
  Include "$BRIK_HOME/lib/transverse/findings.sh"

  FIX="${BRIK_HOME}/spec/fixtures/sarif"

  setup_env() {
    export BRIK_LOG_DIR
    BRIK_LOG_DIR="$(mktemp -d)"
    export BRIK_WORKSPACE
    BRIK_WORKSPACE="$(mktemp -d)"
    export BRIK_RUN_ID="findings-spec"
    report.init >/dev/null 2>&1 || true
  }
  cleanup_env() {
    rm -rf "$BRIK_LOG_DIR" "$BRIK_WORKSPACE"
    unset BRIK_RUN_ID
  }
  Before 'setup_env'
  After 'cleanup_env'

  read_business() {
    local stage="$1" key="$2"
    jq -c --arg s "$stage" --arg k "$key" \
      '.stages[] | select(.name == $s) | .business[$k] // empty' \
      "$BRIK_LOG_DIR/aggregate-report.json" 2>/dev/null
  }

  Describe "API surface"
    It "declares findings.from_sarif"
      When call declare -f findings.from_sarif
      The status should be success
      The output should not be blank
    End

    It "declares findings.from_json"
      When call declare -f findings.from_json
      The status should be success
      The output should not be blank
    End

    It "declares findings.apply_policy"
      When call declare -f findings.apply_policy
      The status should be success
      The output should not be blank
    End

    It "declares findings.aggregate"
      When call declare -f findings.aggregate
      The status should be success
      The output should not be blank
    End

    It "declares findings.expiring_soon"
      When call declare -f findings.expiring_soon
      The status should be success
      The output should not be blank
    End

    It "declares findings.merge_pipeline"
      When call declare -f findings.merge_pipeline
      The status should be success
      The output should not be blank
    End
  End

  Describe "findings.from_sarif"
    It "rejects missing arguments"
      When call findings.from_sarif
      The status should equal 2
      The error should include "missing arguments"
    End

    It "rejects an empty stage name"
      When call findings.from_sarif "" "$FIX/semgrep.sarif"
      The status should equal 2
      The error should include "stage must not be empty"
    End

    It "rejects a nonexistent SARIF file"
      When call findings.from_sarif "sast" "/nonexistent/file.sarif"
      The status should equal 6
      The error should include "not found"
    End

    It "rejects an invalid SARIF document"
      bad_sarif() {
        local tmp
        tmp="$(mktemp).sarif"
        printf '{"not": "sarif"}' > "$tmp"
        findings.from_sarif "sast" "$tmp"
        local rc=$?
        rm -f "$tmp"
        return "$rc"
      }
      When call bad_sarif
      The status should equal 7
      The error should include "invalid SARIF"
    End

    It "accepts a valid SARIF fixture"
      When call findings.from_sarif "sast" "$FIX/semgrep.sarif"
      The status should be success
    End
  End

  Describe "findings.apply_policy (P1 passthrough)"
    It "rejects missing arguments"
      When call findings.apply_policy
      The status should equal 2
      The error should include "missing arguments"
    End

    It "rejects a nonexistent input file"
      bad_input() {
        local out
        out="$(mktemp).sarif"
        findings.apply_policy "/nonexistent.sarif" "$out"
        local rc=$?
        rm -f "$out"
        return "$rc"
      }
      When call bad_input
      The status should equal 6
      The error should include "input not found"
    End

    It "writes a valid SARIF to the output path"
      pass_through() {
        local out
        out="$(mktemp).sarif"
        findings.apply_policy "$FIX/semgrep.sarif" "$out" || { rm -f "$out"; return 1; }
        sarif.is_valid "$out"
        local rc=$?
        rm -f "$out"
        return "$rc"
      }
      When call pass_through
      The status should be success
    End
  End

  Describe "findings.aggregate"
    It "rejects missing arguments"
      When call findings.aggregate
      The status should equal 2
      The error should include "missing arguments"
    End

    It "rejects an empty stage name"
      When call findings.aggregate "" "$FIX/semgrep.sarif"
      The status should equal 2
      The error should include "stage must not be empty"
    End

    It "is a silent no-op when the SARIF file does not exist"
      When call findings.aggregate "sast" "/nonexistent.sarif"
      The status should be success
    End

    It "records business.findings.total from a SARIF fixture"
      run_aggregate() {
        findings.aggregate "sast" "$FIX/semgrep.sarif" >/dev/null 2>&1
        read_business "sast" "findings" | jq -r '.total // empty'
      }
      When call run_aggregate
      The output should not be blank
    End

    It "records business.findings.by_severity with the standard buckets"
      run_aggregate() {
        findings.aggregate "sast" "$FIX/semgrep.sarif" >/dev/null 2>&1
        read_business "sast" "findings" | jq -c '.by_severity'
      }
      When call run_aggregate
      The output should include "critical"
      The output should include "high"
      The output should include "medium"
      The output should include "low"
      The output should include "info"
    End

    It "records business.findings.cwe as a JSON array"
      run_aggregate() {
        findings.aggregate "sast" "$FIX/semgrep.sarif" >/dev/null 2>&1
        read_business "sast" "findings" | jq -r '.cwe | type'
      }
      When call run_aggregate
      The output should equal "array"
    End

    It "records business.report.format as sarif"
      run_aggregate() {
        findings.aggregate "sast" "$FIX/semgrep.sarif" >/dev/null 2>&1
        read_business "sast" "report" | jq -r '.format'
      }
      When call run_aggregate
      The output should equal "sarif"
    End

    It "records business.report.path relative to BRIK_WORKSPACE when nested under it"
      run_aggregate() {
        local nested="$BRIK_WORKSPACE/brik-artifacts/sast/sast.sarif"
        mkdir -p "$(dirname "$nested")"
        cp "$FIX/semgrep.sarif" "$nested"
        findings.aggregate "sast" "$nested" >/dev/null 2>&1
        read_business "sast" "report" | jq -r '.path'
      }
      When call run_aggregate
      The output should equal "brik-artifacts/sast/sast.sarif"
    End

    It "is idempotent across repeated calls"
      run_aggregate_twice() {
        findings.aggregate "sast" "$FIX/semgrep.sarif" >/dev/null 2>&1
        findings.aggregate "sast" "$FIX/semgrep.sarif" >/dev/null 2>&1
        jq -r '[.stages[] | select(.name == "sast")] | length' \
          "$BRIK_LOG_DIR/aggregate-report.json"
      }
      When call run_aggregate_twice
      The output should equal "1"
    End
  End

  Describe "stub functions"
    It "findings.from_json signals not-yet-implemented (P5 scope)"
      When call findings.from_json
      The status should not be success
      The error should include "not implemented"
    End

    It "findings.expiring_soon returns 0 when no allowlist is loaded"
      When call findings.expiring_soon
      The status should be success
    End

    It "findings.merge_pipeline signals not-yet-implemented (P6 scope)"
      When call findings.merge_pipeline
      The status should not be success
      The error should include "not implemented"
    End
  End
End
