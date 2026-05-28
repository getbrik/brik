#shellcheck shell=bash
# Tests for the ruff and bandit -> SARIF converters (chantier 20260508 P5.C).

Describe "transverse/findings/converters/{ruff,bandit}.sh"
  Include "$BRIK_HOME/lib/transverse/sarif.sh"
  Include "$BRIK_HOME/lib/transverse/findings.sh"

  FIX="${BRIK_HOME}/spec/fixtures/json"

  setup_py_conv() {
    OUT="$(mktemp).sarif"
  }
  cleanup_py_conv() { rm -f "$OUT"; }
  Before 'setup_py_conv'
  After  'cleanup_py_conv'

  Describe "ruff converter"
    convert_ruff() {
      findings.from_json ruff "$FIX/ruff.json" "$OUT" >/dev/null 2>&1
    }

    It "produces a structurally valid SARIF document"
      run_then_check() {
        convert_ruff || return 1
        sarif.is_valid "$OUT"
      }
      When call run_then_check
      The status should be success
    End

    It "emits one result per finding"
      run_count() {
        convert_ruff
        jq -r '.runs[0].results | length' "$OUT"
      }
      When call run_count
      The output should equal "3"
    End

    It "deduplicates rules by code"
      run_count_rules() {
        convert_ruff
        jq -r '.runs[0].tool.driver.rules | length' "$OUT"
      }
      When call run_count_rules
      The output should equal "2"
    End

    It "uses the rule code as ruleId"
      run_rule_ids() {
        convert_ruff
        jq -r '[.runs[0].results[].ruleId] | sort | unique | .[]' "$OUT"
      }
      When call run_rule_ids
      The output should include "E501"
      The output should include "F401"
    End

    It "tags every result level=warning (ruff has no per-finding severity)"
      run_levels() {
        convert_ruff
        jq -r '[.runs[0].results[].level] | unique | .[]' "$OUT"
      }
      When call run_levels
      The output should equal "warning"
    End

    It "preserves filename + line range in physicalLocation"
      run_loc() {
        convert_ruff
        jq -r '.runs[0].results[0] | "\(.locations[0].physicalLocation.artifactLocation.uri):\(.locations[0].physicalLocation.region.startLine)"' "$OUT"
      }
      When call run_loc
      The output should equal "src/foo.py:12"
    End

    It "marks fixAvailable=true when ruff suggests a fix"
      run_fix() {
        convert_ruff
        jq -r '[.runs[0].results[] | select(.properties.fixAvailable == true)] | length' "$OUT"
      }
      When call run_fix
      The output should equal "1"
    End
  End

  Describe "bandit converter"
    convert_bandit() {
      findings.from_json bandit "$FIX/bandit.json" "$OUT" >/dev/null 2>&1
    }

    It "produces a structurally valid SARIF document"
      run_then_check() {
        convert_bandit || return 1
        sarif.is_valid "$OUT"
      }
      When call run_then_check
      The status should be success
    End

    It "emits one result per finding"
      run_count() {
        convert_bandit
        jq -r '.runs[0].results | length' "$OUT"
      }
      When call run_count
      The output should equal "3"
    End

    It "uses the bandit test_id as ruleId"
      run_rule_ids() {
        convert_bandit
        jq -r '[.runs[0].results[].ruleId] | sort | .[]' "$OUT"
      }
      When call run_rule_ids
      The output should include "B105"
      The output should include "B311"
      The output should include "B608"
    End

    It "maps issue_severity to SARIF level (LOW->note MEDIUM->warning HIGH->error)"
      run_levels() {
        convert_bandit
        jq -c '[.runs[0].results[] | {id: .ruleId, level}] | sort_by(.id)' "$OUT"
      }
      When call run_levels
      The output should include '{"id":"B105","level":"note"}'
      The output should include '{"id":"B311","level":"warning"}'
      The output should include '{"id":"B608","level":"error"}'
    End

    It "stores CWE-NN tags on rule.properties.tags"
      run_cwes() {
        convert_bandit
        jq -r '[.runs[0].tool.driver.rules[].properties.tags[]] | sort | .[]' "$OUT"
      }
      When call run_cwes
      The output should include "CWE-89"
      The output should include "CWE-259"
      The output should include "CWE-330"
    End

    It "lets sarif.extract_cwe pick up the CWEs"
      run_extract() {
        convert_bandit
        sarif.extract_cwe "$OUT" | jq -c 'sort'
      }
      When call run_extract
      The output should equal '["CWE-259","CWE-330","CWE-89"]'
    End

    It "lets sarif.count_by_severity bucket the findings"
      run_buckets() {
        convert_bandit
        sarif.count_by_severity "$OUT"
      }
      When call run_buckets
      The output should include '"high":1'
      The output should include '"medium":1'
      The output should include '"low":1'
    End

    It "populates a CVSS-like security-severity per finding"
      run_cvss() {
        convert_bandit
        jq -r '[.runs[0].results[] | .properties["security-severity"]] | sort | unique | .[]' "$OUT"
      }
      When call run_cvss
      The output should include "3.0"
      The output should include "5.5"
      The output should include "8.0"
    End
  End
End
