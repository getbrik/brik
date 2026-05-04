#shellcheck shell=bash disable=SC2148,SC2317

Describe "transverse/sarif.sh"
  Include "$BRIK_TRANSVERSE_LIB/sarif.sh"

  FIX="${BRIK_HOME}/spec/fixtures/sarif"

  Describe "sarif.tool_name"
    It "returns the driver name from semgrep fixture"
      When call sarif.tool_name "${FIX}/semgrep.sarif"
      The output should equal "Semgrep OSS"
      The status should be success
    End

    It "returns ESLint for eslint fixture"
      When call sarif.tool_name "${FIX}/eslint.sarif"
      The output should equal "ESLint"
      The status should be success
    End

    It "returns ruff for ruff fixture"
      When call sarif.tool_name "${FIX}/ruff.sarif"
      The output should equal "ruff"
      The status should be success
    End

    It "returns osv-scanner for osv fixture"
      When call sarif.tool_name "${FIX}/osv-scanner.sarif"
      The output should equal "osv-scanner"
      The status should be success
    End

    It "returns Checkov for checkov fixture"
      When call sarif.tool_name "${FIX}/checkov.sarif"
      The output should equal "Checkov"
      The status should be success
    End

    It "returns gitleaks for gitleaks fixture"
      When call sarif.tool_name "${FIX}/gitleaks.sarif"
      The output should equal "gitleaks"
      The status should be success
    End

    It "fails with rc=1 when file does not exist"
      When call sarif.tool_name "${FIX}/does-not-exist.sarif"
      The status should be failure
      The stderr should include "does not exist"
    End

    It "fails with rc=2 when no argument is given"
      When call sarif.tool_name
      The status should equal 2
      The stderr should include "missing"
    End
  End

  Describe "sarif.count_total"
    It "counts 5 results in eslint fixture"
      When call sarif.count_total "${FIX}/eslint.sarif"
      The output should equal "5"
    End

    It "counts 6 results in ruff fixture"
      When call sarif.count_total "${FIX}/ruff.sarif"
      The output should equal "6"
    End

    It "counts 15 results in semgrep fixture"
      When call sarif.count_total "${FIX}/semgrep.sarif"
      The output should equal "15"
    End

    It "counts 1 result in osv fixture"
      When call sarif.count_total "${FIX}/osv-scanner.sarif"
      The output should equal "1"
    End

    It "counts 0 results in eslint-empty fixture"
      When call sarif.count_total "${FIX}/eslint-empty.sarif"
      The output should equal "0"
    End

    It "counts 0 results in ruff-empty fixture"
      When call sarif.count_total "${FIX}/ruff-empty.sarif"
      The output should equal "0"
    End
  End

  Describe "sarif.count_by_severity"
    It "splits eslint into 3 high (error) + 2 medium (warning)"
      When call sarif.count_by_severity "${FIX}/eslint.sarif"
      The output should equal '{"critical":0,"high":3,"medium":2,"low":0,"info":0}'
    End

    It "puts all 6 ruff findings under high (level=error)"
      When call sarif.count_by_severity "${FIX}/ruff.sarif"
      The output should equal '{"critical":0,"high":6,"medium":0,"low":0,"info":0}'
    End

    It "resolves semgrep level via tool.driver.rules.defaultConfiguration"
      When call sarif.count_by_severity "${FIX}/semgrep.sarif"
      The output should equal '{"critical":0,"high":1,"medium":14,"low":0,"info":0}'
    End

    It "places osv-scanner finding (CVSS 6.3) under medium"
      When call sarif.count_by_severity "${FIX}/osv-scanner.sarif"
      The output should equal '{"critical":0,"high":0,"medium":1,"low":0,"info":0}'
    End

    It "puts checkov finding under high (level=error)"
      When call sarif.count_by_severity "${FIX}/checkov.sarif"
      The output should equal '{"critical":0,"high":1,"medium":0,"low":0,"info":0}'
    End

    It "places gitleaks finding under info when no level info is available"
      When call sarif.count_by_severity "${FIX}/gitleaks.sarif"
      The output should equal '{"critical":0,"high":0,"medium":0,"low":0,"info":1}'
    End

    It "returns all-zero counts on an empty SARIF"
      When call sarif.count_by_severity "${FIX}/eslint-empty.sarif"
      The output should equal '{"critical":0,"high":0,"medium":0,"low":0,"info":0}'
    End
  End

  Describe "sarif.extract_cwe"
    It "extracts CWE-20 and CWE-250 from semgrep rule tags, sorted and deduped"
      When call sarif.extract_cwe "${FIX}/semgrep.sarif"
      The output should equal '["CWE-20","CWE-250"]'
    End

    It "returns an empty array when no CWE tags are present (eslint)"
      When call sarif.extract_cwe "${FIX}/eslint.sarif"
      The output should equal '[]'
    End

    It "returns an empty array when no CWE tags are present (ruff)"
      When call sarif.extract_cwe "${FIX}/ruff.sarif"
      The output should equal '[]'
    End

    It "returns an empty array on an empty SARIF"
      When call sarif.extract_cwe "${FIX}/eslint-empty.sarif"
      The output should equal '[]'
    End
  End

  Describe "sarif.is_valid"
    It "validates a real semgrep SARIF as valid"
      When call sarif.is_valid "${FIX}/semgrep.sarif"
      The status should be success
    End

    It "validates an empty-results SARIF as valid"
      When call sarif.is_valid "${FIX}/eslint-empty.sarif"
      The status should be success
    End

    It "validates every captured fixture"
      check_all() {
        local rc=0
        local f
        for f in "${FIX}"/*.sarif; do
          sarif.is_valid "$f" || { printf 'invalid: %s\n' "$f" >&2; rc=1; }
        done
        return $rc
      }
      When call check_all
      The status should be success
    End

    It "rejects a non-SARIF JSON file"
      bad_file() {
        local f
        f="$(mktemp /tmp/not-a-sarif.XXXXXX.json)"
        echo '{"foo":"bar"}' > "$f"
        sarif.is_valid "$f"
        local rc=$?
        rm -f "$f"
        return $rc
      }
      When call bad_file
      The status should equal 1
    End

    It "rejects a non-existent file"
      When call sarif.is_valid "${FIX}/does-not-exist.sarif"
      The status should equal 1
    End
  End
End
