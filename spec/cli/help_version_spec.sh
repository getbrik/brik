#!/usr/bin/env bash
# help_version_spec.sh - ShellSpec tests for `brik` no-args, help, and version

Describe "brik help and no-args"

  Describe "no arguments"
    It "prints help and exits with 0"
      When run script "${BRIK_BIN}"
      The status should eq 0
      The output should include "Usage:"
      The output should include "Commands:"
    End
  End

  Describe "brik help"
    It "prints help and exits with 0"
      When run script "${BRIK_BIN}" help
      The status should eq 0
      The output should include "Usage:"
      The output should include "Commands:"
    End
  End

  Describe "brik --help"
    It "prints help and exits with 0"
      When run script "${BRIK_BIN}" --help
      The status should eq 0
      The output should include "Usage:"
    End
  End

  Describe "brik -h"
    It "prints help and exits with 0"
      When run script "${BRIK_BIN}" -h
      The status should eq 0
      The output should include "Usage:"
    End
  End

End
