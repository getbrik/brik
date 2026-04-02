#!/usr/bin/env bash
# doctor_spec.sh - ShellSpec tests for `brik doctor`

Describe "brik doctor"

  Describe "basic execution"
    It "exits with code 0 when all core tools are present"
      When run script "${BRIK_BIN}" doctor
      The status should eq 0
      The output should include "bash"
      The output should include "OK"
    End

    It "checks bash version >= 4"
      When run script "${BRIK_BIN}" doctor
      The output should include "bash"
    End

    It "checks yq availability"
      When run script "${BRIK_BIN}" doctor
      The output should include "yq"
    End

    It "checks jq availability"
      When run script "${BRIK_BIN}" doctor
      The output should include "jq"
    End
  End

  Describe "output format"
    It "prints a summary line"
      When run script "${BRIK_BIN}" doctor
      The output should include "checks passed"
    End
  End

  Describe "stack detection"
    setup_node_project() {
      TEMP_DIR="$(mktemp -d)"
      printf '{"name":"test","version":"1.0.0"}\n' > "${TEMP_DIR}/package.json"
    }
    cleanup_node_project() { rm -rf "$TEMP_DIR"; }
    Before 'setup_node_project'
    After 'cleanup_node_project'

    It "detects node stack from package.json"
      When run script "${BRIK_BIN}" doctor --workspace "${TEMP_DIR}"
      The output should include "node"
    End
  End

  Describe "with --workspace option"
    setup_empty_dir() { TEMP_DIR="$(mktemp -d)"; }
    cleanup_empty_dir() { rm -rf "$TEMP_DIR"; }
    Before 'setup_empty_dir'
    After 'cleanup_empty_dir'

    It "accepts --workspace argument"
      When run script "${BRIK_BIN}" doctor --workspace "${TEMP_DIR}"
      The status should eq 0
      The output should include "brik doctor"
    End
  End

End
