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

  Describe "unknown option"
    It "exits with code 2 for unknown option"
      When run script "${BRIK_BIN}" doctor --badopt
      The status should eq 2
      The stderr should include "unknown option"
    End
  End

  Describe "python stack detection"
    setup_python_project() {
      TEMP_DIR="$(mktemp -d)"
      printf '[project]\nname = "test"\n' > "${TEMP_DIR}/pyproject.toml"
    }
    cleanup_python_project() { rm -rf "$TEMP_DIR"; }
    Before 'setup_python_project'
    After 'cleanup_python_project'

    It "detects python stack from pyproject.toml"
      When run script "${BRIK_BIN}" doctor --workspace "${TEMP_DIR}"
      The output should include "python"
    End
  End

  Describe "rust stack detection"
    setup_rust_project() {
      TEMP_DIR="$(mktemp -d)"
      printf '[package]\nname = "test"\n' > "${TEMP_DIR}/Cargo.toml"
    }
    cleanup_rust_project() { rm -rf "$TEMP_DIR"; }
    Before 'setup_rust_project'
    After 'cleanup_rust_project'

    It "detects rust stack from Cargo.toml"
      When run script "${BRIK_BIN}" doctor --workspace "${TEMP_DIR}"
      The output should include "rust"
    End
  End

  Describe "dotnet stack detection"
    setup_dotnet_project() {
      TEMP_DIR="$(mktemp -d)"
      printf '<Project Sdk="Microsoft.NET.Sdk"></Project>\n' > "${TEMP_DIR}/Test.csproj"
    }
    cleanup_dotnet_project() { rm -rf "$TEMP_DIR"; }
    Before 'setup_dotnet_project'
    After 'cleanup_dotnet_project'

    It "detects dotnet stack from .csproj"
      When run script "${BRIK_BIN}" doctor --workspace "${TEMP_DIR}"
      The output should include "Detected stack: dotnet"
      # dotnet may not be installed locally, so don't check exit status
      The status should satisfy "true"
    End
  End

  Describe "no stack detected"
    setup_no_stack() { TEMP_DIR="$(mktemp -d)"; }
    cleanup_no_stack() { rm -rf "$TEMP_DIR"; }
    Before 'setup_no_stack'
    After 'cleanup_no_stack'

    It "reports no stack detected"
      When run script "${BRIK_BIN}" doctor --workspace "${TEMP_DIR}"
      The status should eq 0
      The output should include "No stack detected"
    End
  End

End
