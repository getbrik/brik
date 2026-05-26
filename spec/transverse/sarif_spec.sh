#shellcheck shell=bash disable=SC2148,SC2317,SC2329

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

    # Earlier revisions listed every CWE tag declared by the scanner's
    # rules, even when no result referenced them. That produced a ~60-
    # entry CWE list for a clean SAST run, which misled readers into
    # thinking those weaknesses were detected. The function now only
    # surfaces the CWE tags of rules that produced at least one result.
    Describe "filters CWE list to rules actually hit by a result"
      build_sarif() {
        local results="$1" rules="$2"
        local tmp; tmp="$(mktemp)"
        jq -n --argjson results "$results" --argjson rules "$rules" '
          {
            version: "2.1.0",
            runs: [{
              tool: { driver: { name: "synthetic", rules: $rules } },
              results: $results
            }]
          }
        ' > "$tmp"
        printf '%s' "$tmp"
      }

      It "returns [] when no results were produced even if rules declare CWE tags"
        run_check() {
          local sarif
          sarif="$(build_sarif '[]' '[
            {"id":"js.xss","properties":{"tags":["CWE-79: XSS"]}},
            {"id":"sql.injection","properties":{"tags":["CWE-89: SQLi"]}}
          ]')"
          sarif.extract_cwe "$sarif"
          rm -f "$sarif"
        }
        When call run_check
        The output should equal '[]'
      End

      It "lists only the CWE tags of rules that produced a result"
        run_check() {
          local sarif
          sarif="$(build_sarif '[
            {"ruleId":"js.xss","level":"warning","message":{"text":"x"},"locations":[]}
          ]' '[
            {"id":"js.xss","properties":{"tags":["CWE-79: XSS"]}},
            {"id":"sql.injection","properties":{"tags":["CWE-89: SQLi"]}},
            {"id":"sec.leak","properties":{"tags":["CWE-200: Info exposure"]}}
          ]')"
          sarif.extract_cwe "$sarif"
          rm -f "$sarif"
        }
        When call run_check
        The output should equal '["CWE-79"]'
      End

      It "dedups the list when several results reference the same rule"
        run_check() {
          local sarif
          sarif="$(build_sarif '[
            {"ruleId":"js.xss","level":"warning","message":{"text":"a"},"locations":[]},
            {"ruleId":"js.xss","level":"warning","message":{"text":"b"},"locations":[]},
            {"ruleId":"sql.injection","level":"error","message":{"text":"c"},"locations":[]}
          ]' '[
            {"id":"js.xss","properties":{"tags":["CWE-79: XSS"]}},
            {"id":"sql.injection","properties":{"tags":["CWE-89: SQLi"]}},
            {"id":"sec.leak","properties":{"tags":["CWE-200: Info exposure"]}}
          ]')"
          sarif.extract_cwe "$sarif"
          rm -f "$sarif"
        }
        When call run_check
        The output should equal '["CWE-79","CWE-89"]'
      End
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

  Describe "sarif.from_dotnet_format"
    setup_dn() { DN_DIR="$(mktemp -d)"; }
    cleanup_dn() { rm -rf "$DN_DIR"; }
    Before 'setup_dn'
    After 'cleanup_dn'

    It "produces a valid SARIF 2.1.0 document from the dotnet-format fixture"
      run_valid() {
        sarif.from_dotnet_format "${RAW}/dotnet-format.json" "${DN_DIR}/out.sarif"
        sarif.is_valid "${DN_DIR}/out.sarif"
      }
      When call run_valid
      The status should be success
    End

    It "produces tool driver name = dotnet-format"
      run_tool() {
        sarif.from_dotnet_format "${RAW}/dotnet-format.json" "${DN_DIR}/out.sarif"
        sarif.tool_name "${DN_DIR}/out.sarif"
      }
      When call run_tool
      The output should equal "dotnet-format"
    End

    It "yields 17 results (one per FileChange)"
      run_count() {
        sarif.from_dotnet_format "${RAW}/dotnet-format.json" "${DN_DIR}/out.sarif"
        sarif.count_total "${DN_DIR}/out.sarif"
      }
      When call run_count
      The output should equal "17"
    End

    It "uses DiagnosticId WHITESPACE as ruleId"
      run_rules() {
        sarif.from_dotnet_format "${RAW}/dotnet-format.json" "${DN_DIR}/out.sarif"
        jq -c '.runs[0].results | map(.ruleId) | unique' "${DN_DIR}/out.sarif"
      }
      When call run_rules
      The output should equal '["WHITESPACE"]'
    End

    It "places all 17 findings under medium (style issues = warning)"
      run_sev() {
        sarif.from_dotnet_format "${RAW}/dotnet-format.json" "${DN_DIR}/out.sarif"
        sarif.count_by_severity "${DN_DIR}/out.sarif"
      }
      When call run_sev
      The output should equal '{"critical":0,"high":0,"medium":17,"low":0,"info":0}'
    End

    It "preserves FilePath, LineNumber, and CharNumber in result location"
      run_loc() {
        sarif.from_dotnet_format "${RAW}/dotnet-format.json" "${DN_DIR}/out.sarif"
        jq -c '.runs[0].results[0].locations[0].physicalLocation' "${DN_DIR}/out.sarif"
      }
      When call run_loc
      The output should equal '{"artifactLocation":{"uri":"/src/Program.cs"},"region":{"startLine":2,"startColumn":14}}'
    End

    It "produces a valid empty SARIF when input has no FileChanges"
      run_empty() {
        echo '[]' > "${DN_DIR}/empty.json"
        sarif.from_dotnet_format "${DN_DIR}/empty.json" "${DN_DIR}/out.sarif"
        sarif.is_valid "${DN_DIR}/out.sarif" \
          && sarif.count_total "${DN_DIR}/out.sarif"
      }
      When call run_empty
      The output should equal "0"
      The status should be success
    End

    It "fails with rc=2 when arguments are missing"
      When call sarif.from_dotnet_format
      The status should equal 2
      The stderr should include "missing"
    End

    It "fails with rc=1 when input does not exist"
      When call sarif.from_dotnet_format "${DN_DIR}/missing.json" "${DN_DIR}/out.sarif"
      The status should equal 1
      The stderr should include "does not exist"
    End
  End

  Describe "sarif.extract_items"
    It "fails with rc=2 when no argument is given"
      When call sarif.extract_items
      The status should equal 2
      The stderr should include "missing"
    End

    It "fails with rc=1 when file does not exist"
      When call sarif.extract_items "${FIX}/does-not-exist.sarif"
      The status should be failure
      The stderr should include "does not exist"
    End

    It "returns [] for an empty SARIF (no results)"
      When call sarif.extract_items "${FIX}/eslint-empty.sarif"
      The output should equal "[]"
      The status should be success
    End

    It "returns one item per result on grype fixture with 4 results"
      result_count() { sarif.extract_items "${FIX}/grype-rule-help.sarif" | jq 'length'; }
      When call result_count
      The output should equal "4"
      The status should be success
    End

    It "extracts canonical CVE id, severity, score, level, tool from grype-purls"
      run_extract() {
        sarif.extract_items "${FIX}/grype-purls.sarif" \
          | jq -c '.[] | select(.id == "CVE-2026-42010-gnutls")
                   | { id, severity, score, level, tool, help_uri }'
      }
      When call run_extract
      The output should equal '{"id":"CVE-2026-42010-gnutls","severity":"high","score":7.1,"level":"error","tool":{"name":"grype","version":"0.111.1"},"help_uri":"https://security.alpinelinux.org/vuln/CVE-2026-42010"}'
      The status should be success
    End

    It "extracts package name+version+ecosystem from grype PURL"
      run_pkg() {
        sarif.extract_items "${FIX}/grype-purls.sarif" \
          | jq -c '.[] | select(.id == "CVE-2026-42010-gnutls").package'
      }
      When call run_pkg
      The output should equal '{"name":"gnutls","version":"3.8.12-r0","ecosystem":"apk"}'
      The status should be success
    End

    It "extracts fix info from grype help.text when present"
      run_fix() {
        sarif.extract_items "${FIX}/grype-purls.sarif" \
          | jq -c '.[] | select(.id == "CVE-2026-42010-gnutls").fix'
      }
      When call run_fix
      The output should equal '{"versions":["3.8.13-r0"],"available":true}'
      The status should be success
    End

    It "marks fix unavailable when help.text Fix Version is empty"
      run_fix() {
        sarif.extract_items "${FIX}/grype-purls.sarif" \
          | jq -c '.[] | select(.id == "CVE-2026-99999-libfoo").fix'
      }
      When call run_fix
      The output should equal '{"versions":[],"available":false}'
      The status should be success
    End

    It "extracts location uri and logical fully qualified name when present"
      run_loc() {
        sarif.extract_items "${FIX}/grype-purls.sarif" \
          | jq -c '.[] | select(.id == "CVE-2026-42010-gnutls").location | {uri, logical}'
      }
      When call run_loc
      The output should equal '{"uri":"example//lib/apk/db/installed","logical":"example:0.1.0@sha256:abc:/lib/apk/db/installed"}'
      The status should be success
    End

    It "carries the result message text"
      run_msg() {
        sarif.extract_items "${FIX}/grype-purls.sarif" \
          | jq -r '.[] | select(.id == "CVE-2026-42010-gnutls").message'
      }
      When call run_msg
      The output should include "high vulnerability in apk package: gnutls"
      The status should be success
    End

    It "extracts CWE tags from semgrep rule properties.tags"
      run_cwe() {
        sarif.extract_items "${FIX}/semgrep.sarif" \
          | jq -c '[.[].cwe // [] | .[]] | unique | sort'
      }
      When call run_cwe
      The output should include "CWE-"
      The status should be success
    End

    It "preserves rule helpUri from semgrep"
      run_uri() {
        sarif.extract_items "${FIX}/semgrep.sarif" \
          | jq -r 'first(.[] | select(.help_uri != null and .help_uri != "")).help_uri'
      }
      When call run_uri
      The output should include "semgrep.dev"
      The status should be success
    End

    It "extracts location with start_line/end_line/snippet from gitleaks"
      run_loc() {
        sarif.extract_items "${FIX}/gitleaks.sarif" \
          | jq -c 'first(.[]).location | {uri, start_line, end_line, snippet_present: (.snippet != null and .snippet != "")}'
      }
      When call run_loc
      The output should include '"start_line":44'
      The output should include '"end_line":77'
      The output should include '"snippet_present":true'
      The status should be success
    End

    It "buckets gitleaks finding without level as info"
      run_sev() {
        sarif.extract_items "${FIX}/gitleaks.sarif" \
          | jq -c 'first(.[]) | {severity, level}'
      }
      When call run_sev
      The output should equal '{"severity":"info","level":null}'
      The status should be success
    End
  End
End
