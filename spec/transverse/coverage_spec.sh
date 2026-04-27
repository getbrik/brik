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
End
