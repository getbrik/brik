#!/usr/bin/env bash
# self_update_spec.sh - ShellSpec tests for `brik self-update`

Describe "brik self-update"

  Describe "option parsing"
    It "rejects unknown options"
      When run script "${BRIK_BIN}" self-update --badopt
      The status should eq 2
      The stderr should include "unknown option"
    End

    It "rejects invalid channel"
      When run script "${BRIK_BIN}" self-update --channel invalid
      The status should eq 2
      The stderr should include "invalid channel"
    End

    It "requires a value for --channel"
      When run script "${BRIK_BIN}" self-update --channel
      The status should eq 2
      The stderr should include "requires a value"
    End

    It "requires a value for --version"
      When run script "${BRIK_BIN}" self-update --version
      The status should eq 2
      The stderr should include "requires a value"
    End
  End

  Describe "install method detection"
    It "reports source when BRIK_HOME is not ~/.brik"
      When run script "${BRIK_BIN}" version --verbose
      The status should eq 0
      The output should include "install: source"
    End
  End

End
