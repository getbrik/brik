#shellcheck shell=bash
# Tests for the JUnit -> SARIF converter (chantier 20260508 P5.B).
#
# Loaded via the dispatcher findings.from_json so each test exercises both
# the converter logic and the dispatcher contract end-to-end.

Describe "transverse/findings/converters/junit.sh"
  Include "$BRIK_HOME/lib/transverse/sarif.sh"
  Include "$BRIK_HOME/lib/transverse/findings.sh"

  FIX="${BRIK_HOME}/spec/fixtures/junit"

  setup_junit() {
    OUT="$(mktemp).sarif"
  }
  cleanup_junit() { rm -f "$OUT"; }
  Before 'setup_junit'
  After  'cleanup_junit'

  Describe "mixed report (failure + error + skipped + xfail + pass)"
    convert_mixed() {
      findings.from_json junit "$FIX/mixed.xml" "$OUT" >/dev/null 2>&1
    }

    It "returns success and produces a structurally valid SARIF document"
      run_then_check() {
        convert_mixed || return 1
        sarif.is_valid "$OUT"
      }
      When call run_then_check
      The status should be success
    End

    It "emits 4 results (1 failure + 1 error + 2 skipped, pass omitted)"
      run_count() {
        convert_mixed
        jq -r '.runs[0].results | length' "$OUT"
      }
      When call run_count
      The output should equal "4"
    End

    It "tags failure and error as kind=fail with level=error"
      run_count_fail() {
        convert_mixed
        jq -r '[.runs[0].results[] | select(.kind == "fail" and .level == "error")] | length' "$OUT"
      }
      When call run_count_fail
      The output should equal "2"
    End

    It "tags skipped and xfail as kind=review with level=note"
      run_count_review() {
        convert_mixed
        jq -r '[.runs[0].results[] | select(.kind == "review" and .level == "note")] | length' "$OUT"
      }
      When call run_count_review
      The output should equal "2"
    End

    It "preserves the testcase classname.name as ruleId"
      run_check_rule_id() {
        convert_mixed
        jq -r '[.runs[0].results[].ruleId] | sort | .[]' "$OUT"
      }
      When call run_check_rule_id
      The output should include "tests.test_calc.test_div_by_zero"
      The output should include "tests.test_io.test_read_file"
      The output should include "tests.test_io.test_skipped_for_ci"
      The output should include "tests.test_io.test_xfail_known_bug"
    End

    It "embeds the failure message + content in result.message.text"
      run_msg() {
        convert_mixed
        jq -r '.runs[0].results[] | select(.ruleId == "tests.test_calc.test_div_by_zero") | .message.text' "$OUT"
      }
      When call run_msg
      The output should include "AssertionError: 1/0 should raise"
      The output should include "Traceback"
    End

    It "preserves the source kind via properties.source"
      run_sources() {
        convert_mixed
        jq -r '[.runs[0].results[].properties.source] | sort | unique | .[]' "$OUT"
      }
      When call run_sources
      The output should include "error"
      The output should include "failure"
      The output should include "skipped"
    End

    It "deduplicates rules by ruleId"
      run_count_rules() {
        convert_mixed
        jq -r '.runs[0].tool.driver.rules | length' "$OUT"
      }
      When call run_count_rules
      The output should equal "4"
    End
  End

  Describe "edge cases"
    It "handles a single testcase via testcase-as-object yq shape"
      run_single() {
        local in
        in="$(mktemp).xml"
        cat > "$in" <<'XML'
<?xml version="1.0" encoding="utf-8"?>
<testsuites>
  <testsuite name="single" tests="1" failures="1">
    <testcase classname="tests.solo" name="test_only">
      <failure message="boom" type="AssertionError">stack trace</failure>
    </testcase>
  </testsuite>
</testsuites>
XML
        findings.from_json junit "$in" "$OUT" >/dev/null 2>&1
        local rc=$?
        rm -f "$in"
        [[ $rc -eq 0 ]] || return $rc
        jq -r '.runs[0].results | length' "$OUT"
      }
      When call run_single
      The output should equal "1"
    End

    It "handles a bare <testsuite> root without <testsuites>"
      run_bare() {
        local in
        in="$(mktemp).xml"
        cat > "$in" <<'XML'
<?xml version="1.0" encoding="utf-8"?>
<testsuite name="bare" tests="2" failures="1">
  <testcase classname="t" name="a"/>
  <testcase classname="t" name="b">
    <failure message="x" type="E">x</failure>
  </testcase>
</testsuite>
XML
        findings.from_json junit "$in" "$OUT" >/dev/null 2>&1
        local rc=$?
        rm -f "$in"
        [[ $rc -eq 0 ]] || return $rc
        jq -r '.runs[0].results | length' "$OUT"
      }
      When call run_bare
      The output should equal "1"
    End

    It "produces an empty results[] when every testcase passes"
      run_all_pass() {
        local in
        in="$(mktemp).xml"
        cat > "$in" <<'XML'
<?xml version="1.0" encoding="utf-8"?>
<testsuites>
  <testsuite name="ok" tests="2" failures="0">
    <testcase classname="t" name="a"/>
    <testcase classname="t" name="b"/>
  </testsuite>
</testsuites>
XML
        findings.from_json junit "$in" "$OUT" >/dev/null 2>&1
        local rc=$?
        rm -f "$in"
        [[ $rc -eq 0 ]] || return $rc
        jq -r '.runs[0].results | length' "$OUT"
      }
      When call run_all_pass
      The output should equal "0"
    End
  End
End
