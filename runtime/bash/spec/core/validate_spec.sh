Describe "validate.sh"
  Include "$BRIK_RUNTIME_LIB/logging.sh"
  Include "$BRIK_RUNTIME_LIB/tools.sh"
  Include "$BRIK_CORE_LIB/_loader.sh"
  Include "$BRIK_CORE_LIB/validate.sh"

  Describe "validate.run"
    It "validates a correct brik.yml"
      When call validate.run "$EXAMPLES/minimal-node/brik.yml" "$BRIK_SCHEMA"
      The status should eq 0
      The output should include "valid"
    End

    It "fails for invalid brik.yml"
      When call validate.run "$FIXTURES/invalid-missing-version.yml" "$BRIK_SCHEMA"
      The status should eq 2
      The stderr should include "invalid"
    End

    It "returns IO_FAILURE for missing config file"
      When call validate.run "/nonexistent/brik.yml" "$BRIK_SCHEMA"
      The status should eq 6
      The stderr should include "not found"
    End

    It "returns IO_FAILURE for missing schema file"
      When call validate.run "$EXAMPLES/minimal-node/brik.yml" "/nonexistent/schema.json"
      The status should eq 6
      The stderr should include "not found"
    End

    Describe "unparseable YAML"
      setup_bad_yaml() {
        BAD_YAML="$(mktemp)"
        printf 'invalid: yaml: [broken\n' > "$BAD_YAML"
      }
      cleanup_bad_yaml() { rm -f "$BAD_YAML"; }
      Before 'setup_bad_yaml'
      After 'cleanup_bad_yaml'

      It "returns INVALID_INPUT"
        When call validate.run "$BAD_YAML" "$BRIK_SCHEMA"
        The status should eq 2
        The stderr should include "failed to parse"
      End
    End
  End
End
