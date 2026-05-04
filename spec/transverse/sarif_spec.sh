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

  RAW="${BRIK_HOME}/spec/fixtures/raw"

  Describe "sarif.from_prettier"
    setup_conv() { CONV_DIR="$(mktemp -d)"; }
    cleanup_conv() { rm -rf "$CONV_DIR"; }
    Before 'setup_conv'
    After 'cleanup_conv'

    It "produces a valid SARIF 2.1.0 document from the prettier fixture"
      run_valid() {
        sarif.from_prettier "${RAW}/prettier.txt" "${CONV_DIR}/out.sarif"
        sarif.is_valid "${CONV_DIR}/out.sarif"
      }
      When call run_valid
      The status should be success
    End

    It "produces tool driver name = prettier"
      run_tool() {
        sarif.from_prettier "${RAW}/prettier.txt" "${CONV_DIR}/out.sarif"
        sarif.tool_name "${CONV_DIR}/out.sarif"
      }
      When call run_tool
      The output should equal "prettier"
    End

    It "yields 1 result for the fixture (the bad-prettier.js file flagged)"
      run_count() {
        sarif.from_prettier "${RAW}/prettier.txt" "${CONV_DIR}/out.sarif"
        sarif.count_total "${CONV_DIR}/out.sarif"
      }
      When call run_count
      The output should equal "1"
    End

    It "places the finding under medium (level=warning per Brik mapping)"
      run_sev() {
        sarif.from_prettier "${RAW}/prettier.txt" "${CONV_DIR}/out.sarif"
        sarif.count_by_severity "${CONV_DIR}/out.sarif"
      }
      When call run_sev
      The output should equal '{"critical":0,"high":0,"medium":1,"low":0,"info":0}'
    End

    It "preserves the file URI in the result location"
      run_uri() {
        sarif.from_prettier "${RAW}/prettier.txt" "${CONV_DIR}/out.sarif"
        jq -r '.runs[0].results[0].locations[0].physicalLocation.artifactLocation.uri' "${CONV_DIR}/out.sarif"
      }
      When call run_uri
      The output should equal "src/bad-prettier.js"
    End

    It "produces a valid empty SARIF when prettier reports no findings"
      run_empty() {
        echo "Checking formatting..." > "${CONV_DIR}/clean.txt"
        echo "All matched files use Prettier code style!" >> "${CONV_DIR}/clean.txt"
        sarif.from_prettier "${CONV_DIR}/clean.txt" "${CONV_DIR}/out.sarif"
        sarif.is_valid "${CONV_DIR}/out.sarif" \
          && sarif.count_total "${CONV_DIR}/out.sarif"
      }
      When call run_empty
      The output should equal "0"
      The status should be success
    End

    It "ignores the trailing summary [warn] line"
      run_filter() {
        cat > "${CONV_DIR}/multiline.txt" <<'TXT'
[warn] src/a.js
[warn] src/b.ts
[warn] Code style issues found in the above files. Run Prettier with --write to fix.
TXT
        sarif.from_prettier "${CONV_DIR}/multiline.txt" "${CONV_DIR}/out.sarif"
        sarif.count_total "${CONV_DIR}/out.sarif"
      }
      When call run_filter
      The output should equal "2"
    End

    It "fails with rc=2 when arguments are missing"
      When call sarif.from_prettier
      The status should equal 2
      The stderr should include "missing"
    End

    It "fails with rc=1 when input does not exist"
      When call sarif.from_prettier "${CONV_DIR}/missing.txt" "${CONV_DIR}/out.sarif"
      The status should equal 1
      The stderr should include "does not exist"
    End
  End

  Describe "sarif.from_tsc"
    setup_tsc() { TSC_DIR="$(mktemp -d)"; }
    cleanup_tsc() { rm -rf "$TSC_DIR"; }
    Before 'setup_tsc'
    After 'cleanup_tsc'

    It "produces a valid SARIF 2.1.0 document from the tsc fixture"
      run_valid() {
        sarif.from_tsc "${RAW}/tsc.txt" "${TSC_DIR}/out.sarif"
        sarif.is_valid "${TSC_DIR}/out.sarif"
      }
      When call run_valid
      The status should be success
    End

    It "produces tool driver name = tsc"
      run_tool() {
        sarif.from_tsc "${RAW}/tsc.txt" "${TSC_DIR}/out.sarif"
        sarif.tool_name "${TSC_DIR}/out.sarif"
      }
      When call run_tool
      The output should equal "tsc"
    End

    It "yields 2 results for the fixture (TS2322 + TS2304)"
      run_count() {
        sarif.from_tsc "${RAW}/tsc.txt" "${TSC_DIR}/out.sarif"
        sarif.count_total "${TSC_DIR}/out.sarif"
      }
      When call run_count
      The output should equal "2"
    End

    It "extracts ruleIds TS2322 and TS2304 sorted"
      run_rules() {
        sarif.from_tsc "${RAW}/tsc.txt" "${TSC_DIR}/out.sarif"
        jq -c '.runs[0].results | map(.ruleId) | sort' "${TSC_DIR}/out.sarif"
      }
      When call run_rules
      The output should equal '["TS2304","TS2322"]'
    End

    It "places the 2 errors under high (level=error per Brik mapping)"
      run_sev() {
        sarif.from_tsc "${RAW}/tsc.txt" "${TSC_DIR}/out.sarif"
        sarif.count_by_severity "${TSC_DIR}/out.sarif"
      }
      When call run_sev
      The output should equal '{"critical":0,"high":2,"medium":0,"low":0,"info":0}'
    End

    It "preserves the file uri and line/column from the diagnostic"
      run_loc() {
        sarif.from_tsc "${RAW}/tsc.txt" "${TSC_DIR}/out.sarif"
        jq -c '.runs[0].results[0].locations[0].physicalLocation' "${TSC_DIR}/out.sarif"
      }
      When call run_loc
      The output should equal '{"artifactLocation":{"uri":"src/bad.ts"},"region":{"startLine":1,"startColumn":7}}'
    End

    It "maps tsc warning severity to SARIF level=warning"
      run_warn() {
        printf 'src/x.ts(2,3): warning TS9999: deprecated.\n' > "${TSC_DIR}/in.txt"
        sarif.from_tsc "${TSC_DIR}/in.txt" "${TSC_DIR}/out.sarif"
        sarif.count_by_severity "${TSC_DIR}/out.sarif"
      }
      When call run_warn
      The output should equal '{"critical":0,"high":0,"medium":1,"low":0,"info":0}'
    End

    It "produces an empty valid SARIF when no diagnostics are present"
      run_empty() {
        echo "" > "${TSC_DIR}/empty.txt"
        sarif.from_tsc "${TSC_DIR}/empty.txt" "${TSC_DIR}/out.sarif"
        sarif.is_valid "${TSC_DIR}/out.sarif" \
          && sarif.count_total "${TSC_DIR}/out.sarif"
      }
      When call run_empty
      The output should equal "0"
      The status should be success
    End

    It "fails with rc=2 when arguments are missing"
      When call sarif.from_tsc
      The status should equal 2
      The stderr should include "missing"
    End

    It "fails with rc=1 when input does not exist"
      When call sarif.from_tsc "${TSC_DIR}/missing.txt" "${TSC_DIR}/out.sarif"
      The status should equal 1
      The stderr should include "does not exist"
    End
  End
End
