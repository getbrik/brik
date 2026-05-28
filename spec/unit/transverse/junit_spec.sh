Describe "transverse/junit.sh"
  Include "$BRIK_PIPELINE_LIB/logging.sh"
  Include "$BRIK_TRANSVERSE_LIB/junit.sh"

  setup_junit_dir() {
    JUNIT_DIR="$(mktemp -d)"
  }
  cleanup_junit_dir() {
    rm -rf "$JUNIT_DIR"
  }
  Before 'setup_junit_dir'
  After 'cleanup_junit_dir'

  Describe "junit.parse on a single testsuite (jest-junit shape)"
    write_jest_junit() {
      cat > "$JUNIT_DIR/junit.xml" <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<testsuites>
  <testsuite name="Suite" tests="10" failures="2" errors="0" skipped="1" time="3.456">
    <testcase classname="A" name="t1" time="0.5"/>
    <testcase classname="A" name="t2" time="0.5">
      <failure message="boom">stack</failure>
    </testcase>
  </testsuite>
</testsuites>
XML
    }

    It "produces total=10"
      run_total() { write_jest_junit; junit.parse "$JUNIT_DIR/junit.xml" | jq -r '.total'; }
      When call run_total
      The output should equal "10"
    End

    It "produces failed=2 (failures + errors)"
      run_failed() { write_jest_junit; junit.parse "$JUNIT_DIR/junit.xml" | jq -r '.failed'; }
      When call run_failed
      The output should equal "2"
    End

    It "produces skipped=1"
      run_skipped() { write_jest_junit; junit.parse "$JUNIT_DIR/junit.xml" | jq -r '.skipped'; }
      When call run_skipped
      The output should equal "1"
    End

    It "produces passed = total - failed - skipped"
      run_passed() { write_jest_junit; junit.parse "$JUNIT_DIR/junit.xml" | jq -r '.passed'; }
      When call run_passed
      The output should equal "7"
    End

    It "produces duration_ms = round(time * 1000)"
      run_dur() { write_jest_junit; junit.parse "$JUNIT_DIR/junit.xml" | jq -r '.duration_ms'; }
      When call run_dur
      The output should equal "3456"
    End
  End

  Describe "junit.parse on multiple testsuites (surefire/pytest shape)"
    write_multi_suite() {
      cat > "$JUNIT_DIR/junit.xml" <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<testsuites>
  <testsuite name="A" tests="5" failures="1" errors="0" skipped="0" time="1.0"/>
  <testsuite name="B" tests="3" failures="0" errors="1" skipped="2" time="0.5"/>
</testsuites>
XML
    }

    It "sums total across suites"
      run() { write_multi_suite; junit.parse "$JUNIT_DIR/junit.xml" | jq -r '.total'; }
      When call run
      The output should equal "8"
    End

    It "sums failed (failures + errors) across suites"
      run() { write_multi_suite; junit.parse "$JUNIT_DIR/junit.xml" | jq -r '.failed'; }
      When call run
      The output should equal "2"
    End

    It "sums skipped across suites"
      run() { write_multi_suite; junit.parse "$JUNIT_DIR/junit.xml" | jq -r '.skipped'; }
      When call run
      The output should equal "2"
    End

    It "sums duration_ms across suites"
      run() { write_multi_suite; junit.parse "$JUNIT_DIR/junit.xml" | jq -r '.duration_ms'; }
      When call run
      The output should equal "1500"
    End
  End

  Describe "junit.parse on a bare <testsuite> root (legacy pytest shape)"
    write_bare_root() {
      cat > "$JUNIT_DIR/junit.xml" <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<testsuite name="Bare" tests="4" failures="0" errors="0" skipped="0" time="0.25"/>
XML
    }

    It "still extracts total=4"
      run() { write_bare_root; junit.parse "$JUNIT_DIR/junit.xml" | jq -r '.total'; }
      When call run
      The output should equal "4"
    End

    It "passed equals total when no failures or skips"
      run() { write_bare_root; junit.parse "$JUNIT_DIR/junit.xml" | jq -r '.passed'; }
      When call run
      The output should equal "4"
    End
  End

  Describe "junit.parse error handling"
    It "returns non-zero on a missing file"
      run() { junit.parse "$JUNIT_DIR/does-not-exist.xml" 2>/dev/null; }
      When call run
      The status should not equal 0
    End

    It "returns non-zero when called without arguments"
      When call junit.parse
      The status should not equal 0
      The stderr should not be blank
    End

    It "returns zeroes when XML has no testsuite element"
      write_empty_xml() {
        cat > "$JUNIT_DIR/junit.xml" <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<root/>
XML
      }
      run() {
        write_empty_xml
        junit.parse "$JUNIT_DIR/junit.xml" | jq -c '{total, failed, passed, skipped, duration_ms}'
      }
      When call run
      The output should equal '{"total":0,"failed":0,"passed":0,"skipped":0,"duration_ms":0}'
    End
  End
End
