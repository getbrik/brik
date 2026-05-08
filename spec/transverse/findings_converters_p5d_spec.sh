#shellcheck shell=bash
# Tests for the dockle / trufflehog / scancode / clippy SARIF converters
# (chantier 20260508 P5.D).

Describe "transverse/findings/converters/{dockle,trufflehog,scancode,clippy}.sh"
  Include "$BRIK_HOME/lib/transverse/sarif.sh"
  Include "$BRIK_HOME/lib/transverse/findings.sh"

  FIX="${BRIK_HOME}/spec/fixtures/json"

  setup_p5d() { OUT="$(mktemp).sarif"; }
  cleanup_p5d() { rm -f "$OUT"; }
  Before 'setup_p5d'
  After  'cleanup_p5d'

  # -------------------------------------------------------------------------
  # dockle
  # -------------------------------------------------------------------------
  Describe "dockle converter"
    convert_dockle() {
      findings.from_json dockle "$FIX/dockle.json" "$OUT" >/dev/null 2>&1
    }

    It "produces a structurally valid SARIF document"
      run() { convert_dockle && sarif.is_valid "$OUT"; }
      When call run
      The status should be success
    End

    It "omits PASS entries and emits one result per alert"
      run() { convert_dockle; jq -r '.runs[0].results | length' "$OUT"; }
      When call run
      The output should equal "4"
    End

    It "maps FATAL->error, WARN->warning, INFO->note"
      run() {
        convert_dockle
        jq -c '[.runs[0].results[] | {id: .ruleId, level}] | sort_by(.id)' "$OUT"
      }
      When call run
      The output should include '{"id":"CIS-DI-0001","level":"warning"}'
      The output should include '{"id":"CIS-DI-0005","level":"error"}'
      The output should include '{"id":"CIS-DI-0008","level":"note"}'
    End

    It "deduplicates rules by code"
      run() { convert_dockle; jq -r '.runs[0].tool.driver.rules | length' "$OUT"; }
      When call run
      The output should equal "3"
    End
  End

  # -------------------------------------------------------------------------
  # trufflehog
  # -------------------------------------------------------------------------
  Describe "trufflehog converter"
    convert_th() {
      findings.from_json trufflehog "$FIX/trufflehog.ndjson" "$OUT" >/dev/null 2>&1
    }

    It "produces a structurally valid SARIF document"
      run() { convert_th && sarif.is_valid "$OUT"; }
      When call run
      The status should be success
    End

    It "emits one result per NDJSON entry"
      run() { convert_th; jq -r '.runs[0].results | length' "$OUT"; }
      When call run
      The output should equal "3"
    End

    It "maps Verified=true to level=error"
      run() {
        convert_th
        jq -r '[.runs[0].results[] | select(.properties.verified == true) | .level] | unique | .[]' "$OUT"
      }
      When call run
      The output should equal "error"
    End

    It "maps Verified=false to level=warning"
      run() {
        convert_th
        jq -r '[.runs[0].results[] | select(.properties.verified == false) | .level] | unique | .[]' "$OUT"
      }
      When call run
      The output should equal "warning"
    End

    It "uses DetectorName as ruleId"
      run() { convert_th; jq -r '[.runs[0].results[].ruleId] | sort | .[]' "$OUT"; }
      When call run
      The output should include "AWS"
      The output should include "GitHub"
      The output should include "Slack"
    End
  End

  # -------------------------------------------------------------------------
  # scancode
  # -------------------------------------------------------------------------
  Describe "scancode converter"
    convert_sc() {
      findings.from_json scancode "$FIX/scancode.json" "$OUT" >/dev/null 2>&1
    }

    It "produces a structurally valid SARIF document"
      run() { convert_sc && sarif.is_valid "$OUT"; }
      When call run
      The status should be success
    End

    It "emits one result per (file, license_detection, match) triple"
      run() { convert_sc; jq -r '.runs[0].results | length' "$OUT"; }
      When call run
      The output should equal "3"
    End

    It "tags every license result level=note"
      run() {
        convert_sc
        jq -r '[.runs[0].results[].level] | unique | .[]' "$OUT"
      }
      When call run
      The output should equal "note"
    End

    It "uses the license expression as ruleId"
      run() {
        convert_sc
        jq -r '[.runs[0].results[].ruleId] | sort | unique | .[]' "$OUT"
      }
      When call run
      The output should include "gpl-3.0-only"
      The output should include "mit"
    End

    It "skips directory entries (type != file)"
      run() {
        convert_sc
        jq -r '[.runs[0].results[].locations[0].physicalLocation.artifactLocation.uri] | sort | unique | .[]' "$OUT"
      }
      When call run
      The output should include "src/main.py"
      The output should include "src/utils.py"
      The output should not include "build/"
    End
  End

  # -------------------------------------------------------------------------
  # clippy
  # -------------------------------------------------------------------------
  Describe "clippy converter"
    convert_clippy() {
      findings.from_json clippy "$FIX/clippy.ndjson" "$OUT" >/dev/null 2>&1
    }

    It "produces a structurally valid SARIF document"
      run() { convert_clippy && sarif.is_valid "$OUT"; }
      When call run
      The status should be success
    End

    It "filters out non-clippy diagnostics (rustc + build-script)"
      run() { convert_clippy; jq -r '.runs[0].results | length' "$OUT"; }
      When call run
      The output should equal "3"
    End

    It "maps cargo level=error to SARIF level=error"
      run() {
        convert_clippy
        jq -r '[.runs[0].results[] | select(.ruleId == "clippy::approx_constant") | .level] | first' "$OUT"
      }
      When call run
      The output should equal "error"
    End

    It "preserves the file_name + line_start in physicalLocation"
      run() {
        convert_clippy
        jq -r '.runs[0].results[] | select(.ruleId == "clippy::needless_return") | .locations[0].physicalLocation | "\(.artifactLocation.uri):\(.region.startLine)"' "$OUT"
      }
      When call run
      The output should equal "src/main.rs:5"
    End
  End
End
