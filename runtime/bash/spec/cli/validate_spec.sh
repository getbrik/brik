#!/usr/bin/env bash
# validate_spec.sh - ShellSpec tests for `brik validate`

Describe "brik validate"

  Describe "valid configurations"

    Describe "minimal-node example"
      It "exits with code 0 and prints 'brik.yml is valid'"
        When run script "${BRIK_BIN}" validate --config "${EXAMPLES}/minimal-node/brik.yml"
        The status should eq 0
        The output should include "valid"
        The stderr should be blank
      End
    End

    Describe "java-maven example"
      It "exits with code 0 and prints 'brik.yml is valid'"
        When run script "${BRIK_BIN}" validate --config "${EXAMPLES}/java-maven/brik.yml"
        The status should eq 0
        The output should include "valid"
        The stderr should be blank
      End
    End

    Describe "python-pytest example"
      It "exits with code 0 and prints 'brik.yml is valid'"
        When run script "${BRIK_BIN}" validate --config "${EXAMPLES}/python-pytest/brik.yml"
        The status should eq 0
        The output should include "valid"
        The stderr should be blank
      End
    End

    Describe "mono-dotnet example"
      It "exits with code 0 and prints 'brik.yml is valid'"
        When run script "${BRIK_BIN}" validate --config "${EXAMPLES}/mono-dotnet/brik.yml"
        The status should eq 0
        The output should include "valid"
        The stderr should be blank
      End
    End

  End

  Describe "invalid configurations"

    Describe "missing required version field"
      It "exits with code 2 and prints an error to stderr"
        When run script "${BRIK_BIN}" validate --config "${FIXTURES}/invalid-missing-version.yml"
        The status should eq 2
        The stderr should include "invalid"
        The output should be blank
      End
    End

    Describe "version as string instead of integer"
      It "exits with code 2 and prints an error to stderr"
        When run script "${BRIK_BIN}" validate --config "${FIXTURES}/invalid-wrong-type.yml"
        The status should eq 2
        The stderr should include "invalid"
        The output should be blank
      End
    End

    Describe "unknown top-level key"
      It "exits with code 2 and prints an error to stderr"
        When run script "${BRIK_BIN}" validate --config "${FIXTURES}/invalid-unknown-key.yml"
        The status should eq 2
        The stderr should include "invalid"
        The output should be blank
      End
    End

  End

  Describe "missing config file"
    It "exits with code 6 and prints a 'not found' error to stderr"
      When run script "${BRIK_BIN}" validate --config "/nonexistent/path/brik.yml"
      The status should eq 6
      The error should include "not found"
      The output should be blank
    End
  End

  Describe "default config resolution"
    # run_validate_in_dir changes to a directory then calls brik validate.
    # ShellSpec isolates each example scope so the cd is safe.
    run_validate_in_dir() {
      cd "$1" && shift && bash "${BRIK_BIN}" "$@"
    }

    It "uses brik.yml in current directory when --config is omitted"
      When call run_validate_in_dir "${EXAMPLES}/minimal-node" validate
      The status should eq 0
      The output should include "valid"
    End

    It "exits with code 6 when no brik.yml exists in current directory"
      When call run_validate_in_dir "/tmp" validate
      The status should eq 6
      The stderr should include "not found"
    End
  End

  Describe "custom --schema flag"
    It "accepts a custom schema path and validates successfully"
      When run script "${BRIK_BIN}" validate \
        --config "${EXAMPLES}/minimal-node/brik.yml" \
        --schema "${BRIK_SCHEMA}"
      The status should eq 0
      The output should include "valid"
      The stderr should be blank
    End

    It "exits with code 6 when the schema file does not exist"
      When run script "${BRIK_BIN}" validate \
        --config "${EXAMPLES}/minimal-node/brik.yml" \
        --schema "/nonexistent/schema.json"
      The status should eq 6
      The stderr should include "not found"
      The output should be blank
    End
  End

  Describe "argument errors"
    It "exits with code 2 for unknown option"
      When run script "${BRIK_BIN}" validate --unknown-flag
      The status should eq 2
      The stderr should include "unknown"
      The output should be blank
    End

    It "exits with code 2 when --config is missing its argument"
      When run script "${BRIK_BIN}" validate --config
      The status should eq 2
      The stderr should include "--config"
      The output should be blank
    End

    It "exits with code 2 when --schema is missing its argument"
      When run script "${BRIK_BIN}" validate --schema
      The status should eq 2
      The stderr should include "--schema"
      The output should be blank
    End
  End

  Describe "invalid YAML"
    setup_invalid_yaml() {
      TEMP_DIR="$(mktemp -d)"
      printf 'invalid: yaml: [broken\n' > "${TEMP_DIR}/bad.yml"
    }
    cleanup_invalid_yaml() { rm -rf "$TEMP_DIR"; }
    Before 'setup_invalid_yaml'
    After 'cleanup_invalid_yaml'

    It "exits with code 2 when YAML is unparseable"
      When run script "${BRIK_BIN}" validate --config "${TEMP_DIR}/bad.yml"
      The status should eq 2
      The stderr should include "failed to parse"
    End
  End

End
