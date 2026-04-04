#!/usr/bin/env bash
# version_spec.sh - ShellSpec tests for `brik version`

Describe "brik version"

  Describe "output content"
    It "contains 'brik 0.1.0'"
      When run script "${BRIK_BIN}" version
      The status should eq 0
      The output should include "brik 0.1.0"
      The stderr should be blank
    End

    It "contains 'schema: v1'"
      When run script "${BRIK_BIN}" version
      The status should eq 0
      The output should include "schema: v1"
      The stderr should be blank
    End

    It "contains 'runtime: bash'"
      When run script "${BRIK_BIN}" version
      The status should eq 0
      The output should include "runtime: bash"
      The stderr should be blank
    End
  End

  Describe "exit status"
    It "exits with code 0"
      When run script "${BRIK_BIN}" version
      The status should eq 0
      The output should be present
      The stderr should be blank
    End
  End

  Describe "output line count"
    It "prints exactly 3 lines"
      When run script "${BRIK_BIN}" version
      The status should eq 0
      The lines of output should eq 3
      The stderr should be blank
    End
  End

  Describe "--verbose flag"
    It "includes home path"
      When run script "${BRIK_BIN}" version --verbose
      The status should eq 0
      The output should include "home:"
    End

    It "includes install method"
      When run script "${BRIK_BIN}" version --verbose
      The status should eq 0
      The output should include "install:"
    End

    It "includes commit info"
      When run script "${BRIK_BIN}" version --verbose
      The status should eq 0
      The output should include "commit:"
    End

    It "prints exactly 6 lines"
      When run script "${BRIK_BIN}" version --verbose
      The status should eq 0
      The lines of output should eq 6
    End

    It "commit line contains a value"
      When run script "${BRIK_BIN}" version --verbose
      The status should eq 0
      The output should match pattern "*commit: *"
    End
  End

  Describe "unknown option"
    It "rejects unknown options"
      When run script "${BRIK_BIN}" version --badopt
      The status should eq 2
      The stderr should include "unknown option"
    End
  End

End
