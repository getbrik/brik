Describe "transverse/coverage.sh"
  Include "$BRIK_HOME/lib/transverse/coverage.sh"

  Describe "brik.coverage.summary"
    Describe "with cobertura coverage.xml"
      setup_cobertura() {
        TEST_DIR="$(mktemp -d)"
        mkdir -p "${TEST_DIR}/coverage"
        cat > "${TEST_DIR}/coverage/coverage.xml" <<'XML'
<?xml version="1.0" ?>
<coverage line-rate="0.8542" branch-rate="0.7" version="6.0">
</coverage>
XML
      }
      cleanup_cobertura() { rm -rf "$TEST_DIR"; }
      Before 'setup_cobertura'
      After 'cleanup_cobertura'

      It "emits the line-rate as a percentage with two decimals"
        When call brik.coverage.summary "${TEST_DIR}/coverage"
        The output should equal "[brik] coverage: 85.42%"
        The status should be success
      End
    End

    Describe "with jacoco jacoco.xml"
      setup_jacoco() {
        TEST_DIR="$(mktemp -d)"
        mkdir -p "${TEST_DIR}/coverage"
        # Multiple <counter type="LINE"/> at method/class/package level;
        # the helper must pick the report-level aggregate (last one).
        cat > "${TEST_DIR}/coverage/jacoco.xml" <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<report name="t">
  <package name="x">
    <class name="x/A">
      <counter type="LINE" missed="2" covered="3"/>
    </class>
    <counter type="LINE" missed="2" covered="3"/>
  </package>
  <counter type="INSTRUCTION" missed="10" covered="40"/>
  <counter type="LINE" missed="42" covered="158"/>
  <counter type="CLASS" missed="0" covered="1"/>
</report>
XML
      }
      cleanup_jacoco() { rm -rf "$TEST_DIR"; }
      Before 'setup_jacoco'
      After 'cleanup_jacoco'

      It "aggregates from the last LINE counter (158 / (158 + 42) = 79%)"
        When call brik.coverage.summary "${TEST_DIR}/coverage"
        The output should equal "[brik] coverage: 79.00%"
        The status should be success
      End
    End

    Describe "with no report file"
      setup_empty() {
        TEST_DIR="$(mktemp -d)"
        mkdir -p "${TEST_DIR}/coverage"
      }
      cleanup_empty() { rm -rf "$TEST_DIR"; }
      Before 'setup_empty'
      After 'cleanup_empty'

      It "produces no output and returns 0"
        When call brik.coverage.summary "${TEST_DIR}/coverage"
        The output should equal ""
        The status should be success
      End
    End

    Describe "with a malformed cobertura file (no line-rate)"
      setup_malformed() {
        TEST_DIR="$(mktemp -d)"
        mkdir -p "${TEST_DIR}/coverage"
        printf '<coverage version="6.0"></coverage>\n' > "${TEST_DIR}/coverage/coverage.xml"
      }
      cleanup_malformed() { rm -rf "$TEST_DIR"; }
      Before 'setup_malformed'
      After 'cleanup_malformed'

      It "produces no output without crashing"
        When call brik.coverage.summary "${TEST_DIR}/coverage"
        The output should equal ""
        The status should be success
      End
    End

    Describe "with BRIK_TEST_COVERAGE_DIR override"
      setup_env() {
        TEST_DIR="$(mktemp -d)"
        mkdir -p "${TEST_DIR}/custom-cov"
        cat > "${TEST_DIR}/custom-cov/coverage.xml" <<'XML'
<coverage line-rate="0.5"/>
XML
        export BRIK_TEST_COVERAGE_DIR="${TEST_DIR}/custom-cov"
      }
      cleanup_env() {
        unset BRIK_TEST_COVERAGE_DIR
        rm -rf "$TEST_DIR"
      }
      Before 'setup_env'
      After 'cleanup_env'

      It "reads from BRIK_TEST_COVERAGE_DIR when no arg passed"
        When call brik.coverage.summary
        The output should equal "[brik] coverage: 50.00%"
      End
    End
  End

  Describe "brik.coverage.gate"
    Describe "case 1: empty or unset threshold"
      It "returns 0 silently when threshold is empty string"
        When call brik.coverage.gate ""
        The status should be success
        The output should equal ""
        The stderr should equal ""
      End

      It "returns 0 silently when threshold arg is omitted"
        When call brik.coverage.gate
        The status should be success
        The output should equal ""
        The stderr should equal ""
      End
    End

    Describe "case 2: non-numeric threshold"
      # The validation happens before any file I/O, so no fixture dir needed.
      # Pass a nonexistent path -- the threshold check fires first.
      It "returns INVALID_INPUT (2) for alphabetic threshold"
        When call brik.coverage.gate "abc" "/nonexistent/cov"
        The status should equal 2
        The stderr should include "invalid"
      End

      It "returns INVALID_INPUT (2) for mixed alphanumeric threshold"
        When call brik.coverage.gate "12abc" "/nonexistent/cov"
        The status should equal 2
        The stderr should include "invalid"
      End

      It "returns INVALID_INPUT (2) for negative threshold"
        When call brik.coverage.gate "-5" "/nonexistent/cov"
        The status should equal 2
        The stderr should include "invalid"
      End
    End

    Describe "case 3: no coverage file present"
      setup_no_file() {
        TEST_DIR="$(mktemp -d)"
        mkdir -p "${TEST_DIR}/coverage"
      }
      cleanup_no_file() { rm -rf "$TEST_DIR"; }
      Before 'setup_no_file'
      After 'cleanup_no_file'

      It "returns 0 and warns when no report file exists"
        When call brik.coverage.gate "80" "${TEST_DIR}/coverage"
        The status should be success
        The stderr should include "coverage gate skipped"
        The stderr should include "no coverage report"
      End
    End

    Describe "case 4: cobertura coverage >= threshold"
      setup_cobertura_pass() {
        TEST_DIR="$(mktemp -d)"
        mkdir -p "${TEST_DIR}/coverage"
        cat > "${TEST_DIR}/coverage/coverage.xml" <<'XML'
<?xml version="1.0" ?>
<coverage line-rate="0.8542" branch-rate="0.7" version="6.0">
</coverage>
XML
      }
      cleanup_cobertura_pass() { rm -rf "$TEST_DIR"; }
      Before 'setup_cobertura_pass'
      After 'cleanup_cobertura_pass'

      It "returns 0 and logs info when coverage 85.42% >= threshold 80%"
        When call brik.coverage.gate "80" "${TEST_DIR}/coverage"
        The status should be success
        The stderr should include "85.42%"
        The stderr should include ">="
        The stderr should include "80"
      End

      It "returns 0 when threshold equals integer part of coverage (boundary: 85)"
        When call brik.coverage.gate "85" "${TEST_DIR}/coverage"
        The status should be success
        The stderr should include ">="
      End
    End

    Describe "case 5: cobertura coverage < threshold"
      setup_cobertura_fail() {
        TEST_DIR="$(mktemp -d)"
        mkdir -p "${TEST_DIR}/coverage"
        cat > "${TEST_DIR}/coverage/coverage.xml" <<'XML'
<?xml version="1.0" ?>
<coverage line-rate="0.7200" branch-rate="0.6" version="6.0">
</coverage>
XML
      }
      cleanup_cobertura_fail() { rm -rf "$TEST_DIR"; }
      Before 'setup_cobertura_fail'
      After 'cleanup_cobertura_fail'

      It "returns CHECK_FAILED (10) when coverage 72% < threshold 80%"
        When call brik.coverage.gate "80" "${TEST_DIR}/coverage"
        The status should equal 10
        The stderr should include "72.00%"
        The stderr should include "below"
        The stderr should include "80"
      End
    End

    Describe "case 6: jacoco coverage >= threshold"
      setup_jacoco_pass() {
        TEST_DIR="$(mktemp -d)"
        mkdir -p "${TEST_DIR}/coverage"
        cat > "${TEST_DIR}/coverage/jacoco.xml" <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<report name="t">
  <counter type="INSTRUCTION" missed="10" covered="40"/>
  <counter type="LINE" missed="15" covered="85"/>
  <counter type="CLASS" missed="0" covered="1"/>
</report>
XML
      }
      cleanup_jacoco_pass() { rm -rf "$TEST_DIR"; }
      Before 'setup_jacoco_pass'
      After 'cleanup_jacoco_pass'

      It "returns 0 when jacoco coverage 85/(85+15)=85% >= threshold 80%"
        When call brik.coverage.gate "80" "${TEST_DIR}/coverage"
        The status should be success
        The stderr should include ">="
      End
    End

    Describe "case 7: jacoco coverage < threshold"
      setup_jacoco_fail() {
        TEST_DIR="$(mktemp -d)"
        mkdir -p "${TEST_DIR}/coverage"
        cat > "${TEST_DIR}/coverage/jacoco.xml" <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<report name="t">
  <counter type="INSTRUCTION" missed="10" covered="40"/>
  <counter type="LINE" missed="42" covered="58"/>
  <counter type="CLASS" missed="0" covered="1"/>
</report>
XML
      }
      cleanup_jacoco_fail() { rm -rf "$TEST_DIR"; }
      Before 'setup_jacoco_fail'
      After 'cleanup_jacoco_fail'

      It "returns CHECK_FAILED (10) when jacoco coverage 58/(58+42)=58% < threshold 80%"
        When call brik.coverage.gate "80" "${TEST_DIR}/coverage"
        The status should equal 10
        The stderr should include "below"
      End
    End

    Describe "case 8: malformed XML file present"
      setup_malformed_gate() {
        TEST_DIR="$(mktemp -d)"
        mkdir -p "${TEST_DIR}/coverage"
        printf 'THIS IS NOT XML AT ALL\n' > "${TEST_DIR}/coverage/coverage.xml"
      }
      cleanup_malformed_gate() { rm -rf "$TEST_DIR"; }
      Before 'setup_malformed_gate'
      After 'cleanup_malformed_gate'

      It "returns 0 and warns when coverage report cannot be parsed"
        When call brik.coverage.gate "80" "${TEST_DIR}/coverage"
        The status should be success
        The stderr should include "coverage gate skipped"
        The stderr should include "could not parse"
      End
    End

    Describe "decimal threshold"
      setup_decimal() {
        TEST_DIR="$(mktemp -d)"
        mkdir -p "${TEST_DIR}/coverage"
        cat > "${TEST_DIR}/coverage/coverage.xml" <<'XML'
<?xml version="1.0" ?>
<coverage line-rate="0.8542" branch-rate="0.7" version="6.0">
</coverage>
XML
      }
      cleanup_decimal() { rm -rf "$TEST_DIR"; }
      Before 'setup_decimal'
      After 'cleanup_decimal'

      It "accepts decimal threshold (85.5) and fails when coverage 85.42% < 85.5%"
        When call brik.coverage.gate "85.5" "${TEST_DIR}/coverage"
        The status should equal 10
        The stderr should include "below"
      End

      It "accepts decimal threshold (85.4) and passes when coverage 85.42% >= 85.4%"
        When call brik.coverage.gate "85.4" "${TEST_DIR}/coverage"
        The status should be success
        The stderr should include ">="
      End
    End
  End

  Describe "_brik.coverage._parse_branch_pct"
    Describe "with cobertura branch-rate"
      setup_cob_branch() {
        TEST_DIR="$(mktemp -d)"
        mkdir -p "${TEST_DIR}/coverage"
        cat > "${TEST_DIR}/coverage/coverage.xml" <<'XML'
<?xml version="1.0" ?>
<coverage line-rate="0.8542" branch-rate="0.72" version="6.0">
</coverage>
XML
      }
      cleanup_cob_branch() { rm -rf "$TEST_DIR"; }
      Before 'setup_cob_branch'
      After 'cleanup_cob_branch'

      It "emits the branch-rate as a percentage with two decimals"
        When call _brik.coverage._parse_branch_pct "${TEST_DIR}/coverage"
        The output should equal "72.00"
        The status should be success
      End
    End

    Describe "with jacoco BRANCH counter"
      setup_jacoco_branch() {
        TEST_DIR="$(mktemp -d)"
        mkdir -p "${TEST_DIR}/coverage"
        cat > "${TEST_DIR}/coverage/jacoco.xml" <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<report name="t">
  <package name="x">
    <counter type="BRANCH" missed="3" covered="7"/>
  </package>
  <counter type="LINE" missed="42" covered="158"/>
  <counter type="BRANCH" missed="20" covered="80"/>
  <counter type="CLASS" missed="0" covered="1"/>
</report>
XML
      }
      cleanup_jacoco_branch() { rm -rf "$TEST_DIR"; }
      Before 'setup_jacoco_branch'
      After 'cleanup_jacoco_branch'

      It "aggregates from the last BRANCH counter (80 / (80 + 20) = 80%)"
        When call _brik.coverage._parse_branch_pct "${TEST_DIR}/coverage"
        The output should equal "80.00"
        The status should be success
      End
    End

    Describe "with cobertura missing branch-rate"
      setup_cob_no_branch() {
        TEST_DIR="$(mktemp -d)"
        mkdir -p "${TEST_DIR}/coverage"
        cat > "${TEST_DIR}/coverage/coverage.xml" <<'XML'
<?xml version="1.0" ?>
<coverage line-rate="0.8542" version="6.0">
</coverage>
XML
      }
      cleanup_cob_no_branch() { rm -rf "$TEST_DIR"; }
      Before 'setup_cob_no_branch'
      After 'cleanup_cob_no_branch'

      It "produces empty output when branch-rate is absent"
        When call _brik.coverage._parse_branch_pct "${TEST_DIR}/coverage"
        The output should equal ""
        The status should be success
      End
    End

    Describe "with jacoco missing BRANCH counter"
      setup_jacoco_no_branch() {
        TEST_DIR="$(mktemp -d)"
        mkdir -p "${TEST_DIR}/coverage"
        cat > "${TEST_DIR}/coverage/jacoco.xml" <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<report name="t">
  <counter type="LINE" missed="42" covered="158"/>
</report>
XML
      }
      cleanup_jacoco_no_branch() { rm -rf "$TEST_DIR"; }
      Before 'setup_jacoco_no_branch'
      After 'cleanup_jacoco_no_branch'

      It "produces empty output when BRANCH counter is absent"
        When call _brik.coverage._parse_branch_pct "${TEST_DIR}/coverage"
        The output should equal ""
        The status should be success
      End
    End

    Describe "with no report file"
      setup_empty_branch() {
        TEST_DIR="$(mktemp -d)"
        mkdir -p "${TEST_DIR}/coverage"
      }
      cleanup_empty_branch() { rm -rf "$TEST_DIR"; }
      Before 'setup_empty_branch'
      After 'cleanup_empty_branch'

      It "produces empty output and returns 0"
        When call _brik.coverage._parse_branch_pct "${TEST_DIR}/coverage"
        The output should equal ""
        The status should be success
      End
    End
  End

  # ---------------------------------------------------------------------------
  # SC18: LCOV parsing (c8 / Node default output)
  # ---------------------------------------------------------------------------
  Describe "_brik.coverage._parse_pct with lcov.info"
    Describe "single file LCOV"
      setup_lcov() {
        TEST_DIR="$(mktemp -d)"
        mkdir -p "${TEST_DIR}/coverage"
        cat > "${TEST_DIR}/coverage/lcov.info" <<'LCOV'
TN:
SF:/work/src/a.js
DA:1,1
DA:2,1
DA:3,0
DA:4,0
LF:4
LH:2
end_of_record
LCOV
      }
      cleanup_lcov() { rm -rf "$TEST_DIR"; }
      Before 'setup_lcov'
      After  'cleanup_lcov'

      It "computes the line percentage from LF/LH (2/4 = 50%)"
        When call _brik.coverage._parse_pct "${TEST_DIR}/coverage"
        The output should equal "50.00"
        The status should be success
      End
    End

    Describe "multi-file LCOV summed across records"
      setup_multi() {
        TEST_DIR="$(mktemp -d)"
        mkdir -p "${TEST_DIR}/coverage"
        cat > "${TEST_DIR}/coverage/lcov.info" <<'LCOV'
TN:
SF:/work/src/a.js
LF:10
LH:8
end_of_record
TN:
SF:/work/src/b.js
LF:10
LH:6
end_of_record
LCOV
      }
      cleanup_multi() { rm -rf "$TEST_DIR"; }
      Before 'setup_multi'
      After  'cleanup_multi'

      It "aggregates LH/LF across records (14/20 = 70%)"
        When call _brik.coverage._parse_pct "${TEST_DIR}/coverage"
        The output should equal "70.00"
        The status should be success
      End
    End

    Describe "LCOV preferred over absent cobertura/jacoco"
      setup_lcov_only() {
        TEST_DIR="$(mktemp -d)"
        mkdir -p "${TEST_DIR}/coverage"
        cat > "${TEST_DIR}/coverage/lcov.info" <<'LCOV'
TN:
SF:/x.js
LF:5
LH:5
end_of_record
LCOV
      }
      cleanup_lcov_only() { rm -rf "$TEST_DIR"; }
      Before 'setup_lcov_only'
      After  'cleanup_lcov_only'

      It "returns 100.00 for full coverage"
        When call _brik.coverage._parse_pct "${TEST_DIR}/coverage"
        The output should equal "100.00"
        The status should be success
      End
    End
  End

  # ---------------------------------------------------------------------------
  # SC18: SARIF emission of coverage breaches
  # ---------------------------------------------------------------------------
  Describe "brik.coverage.emit_sarif"
    setup_emit() {
      TEST_DIR="$(mktemp -d)"
      mkdir -p "${TEST_DIR}/coverage"
      SARIF_OUT="${TEST_DIR}/test-coverage.sarif"
    }
    cleanup_emit() { rm -rf "$TEST_DIR"; }
    Before 'setup_emit'
    After  'cleanup_emit'

    Describe "below threshold"
      setup_below() {
        cat > "${TEST_DIR}/coverage/coverage.xml" <<'XML'
<?xml version="1.0" ?>
<coverage line-rate="0.6500" version="6.0"></coverage>
XML
      }
      Before 'setup_below'

      It "writes a SARIF file with one result and rc=0"
        When call brik.coverage.emit_sarif 80 "${TEST_DIR}/coverage" "$SARIF_OUT"
        The status should be success
        The path "$SARIF_OUT" should be exist
      End

      It "sets the rule id to brik-coverage-below-threshold"
        do_emit() {
          brik.coverage.emit_sarif 80 "${TEST_DIR}/coverage" "$SARIF_OUT" >/dev/null
          jq -r '.runs[0].results[0].ruleId' "$SARIF_OUT"
        }
        When call do_emit
        The output should equal "brik-coverage-below-threshold"
      End

      It "embeds the measured and required percentages in the message"
        do_emit() {
          brik.coverage.emit_sarif 80 "${TEST_DIR}/coverage" "$SARIF_OUT" >/dev/null
          jq -r '.runs[0].results[0].message.text' "$SARIF_OUT"
        }
        When call do_emit
        The output should include "65"
        The output should include "80"
      End

      It "carries the tool driver name 'brik-coverage'"
        do_emit() {
          brik.coverage.emit_sarif 80 "${TEST_DIR}/coverage" "$SARIF_OUT" >/dev/null
          jq -r '.runs[0].tool.driver.name' "$SARIF_OUT"
        }
        When call do_emit
        The output should equal "brik-coverage"
      End
    End

    Describe "at or above threshold"
      setup_above() {
        cat > "${TEST_DIR}/coverage/coverage.xml" <<'XML'
<?xml version="1.0" ?>
<coverage line-rate="0.8542" version="6.0"></coverage>
XML
      }
      Before 'setup_above'

      It "writes a SARIF file with an empty results[] and rc=0"
        do_emit() {
          brik.coverage.emit_sarif 80 "${TEST_DIR}/coverage" "$SARIF_OUT" >/dev/null
          jq -r '.runs[0].results | length' "$SARIF_OUT"
        }
        When call do_emit
        The output should equal "0"
      End
    End

    Describe "empty/absent threshold"
      It "skips emission silently with rc=0 when threshold is empty"
        do_emit() {
          brik.coverage.emit_sarif "" "${TEST_DIR}/coverage" "$SARIF_OUT" >/dev/null
          [[ -f "$SARIF_OUT" ]] && echo "wrote" || echo "skipped"
        }
        When call do_emit
        The output should equal "skipped"
      End
    End

    Describe "no coverage report at the configured dir"
      It "writes a SARIF with empty results[] (advisory: missing data must not block)"
        do_emit() {
          brik.coverage.emit_sarif 80 "${TEST_DIR}/coverage" "$SARIF_OUT" >/dev/null
          jq -r '.runs[0].results | length' "$SARIF_OUT"
        }
        When call do_emit
        The output should equal "0"
      End
    End

    Describe "invalid threshold"
      It "returns INVALID_INPUT (2) for non-numeric threshold"
        When call brik.coverage.emit_sarif "abc" "${TEST_DIR}/coverage" "$SARIF_OUT"
        The status should equal 2
        The stderr should include "invalid threshold"
      End
    End
  End
End
