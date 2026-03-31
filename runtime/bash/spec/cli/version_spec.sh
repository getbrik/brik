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

End
