#!/usr/bin/env bash
# self_uninstall_spec.sh - ShellSpec tests for `brik self-uninstall`

Describe "brik self-uninstall"

  Describe "option parsing"
    It "rejects unknown options"
      When run script "${BRIK_BIN}" self-uninstall --badopt
      The status should eq 2
      The stderr should include "unknown option"
    End
  End

End
