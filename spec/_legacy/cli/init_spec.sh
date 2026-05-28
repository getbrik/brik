#!/usr/bin/env bash
# init_spec.sh - ShellSpec tests for `brik init`

Describe "brik init"

  Describe "non-interactive mode with node stack"
    setup_project() {
      TEMP_DIR="$(mktemp -d)"
      printf '{"name":"test-app","version":"1.0.0"}\n' > "${TEMP_DIR}/package.json"
    }
    cleanup_project() { rm -rf "$TEMP_DIR"; }
    Before 'setup_project'
    After 'cleanup_project'

    It "generates a valid brik.yml"
      When run script "${BRIK_BIN}" init --stack node --platform gitlab --dir "${TEMP_DIR}" --non-interactive
      The status should eq 0
      The output should include "Created"
      The file "${TEMP_DIR}/brik.yml" should be exist
    End

    It "generates a .gitlab-ci.yml bootstrap"
      When run script "${BRIK_BIN}" init --stack node --platform gitlab --dir "${TEMP_DIR}" --non-interactive
      The status should eq 0
      The output should include "Created"
      The file "${TEMP_DIR}/.gitlab-ci.yml" should be exist
    End

    It "brik.yml contains version 1"
      When run script "${BRIK_BIN}" init --stack node --platform gitlab --dir "${TEMP_DIR}" --non-interactive
      The output should include "Created"
      The contents of file "${TEMP_DIR}/brik.yml" should include "version: 1"
    End

    It "brik.yml contains stack: node"
      When run script "${BRIK_BIN}" init --stack node --platform gitlab --dir "${TEMP_DIR}" --non-interactive
      The output should include "Created"
      The contents of file "${TEMP_DIR}/brik.yml" should include "stack: node"
    End

    It ".gitlab-ci.yml includes brik pipeline template"
      When run script "${BRIK_BIN}" init --stack node --platform gitlab --dir "${TEMP_DIR}" --non-interactive
      The output should include "Created"
      The contents of file "${TEMP_DIR}/.gitlab-ci.yml" should include "pipeline.yml"
    End
  End

  Describe "auto-detection from package.json"
    setup_node() {
      TEMP_DIR="$(mktemp -d)"
      printf '{"name":"auto-app","version":"1.0.0"}\n' > "${TEMP_DIR}/package.json"
    }
    cleanup_node() { rm -rf "$TEMP_DIR"; }
    Before 'setup_node'
    After 'cleanup_node'

    It "detects node from package.json"
      When run script "${BRIK_BIN}" init --platform gitlab --dir "${TEMP_DIR}" --non-interactive
      The status should eq 0
      The output should include "Detected stack: node"
      The contents of file "${TEMP_DIR}/brik.yml" should include "stack: node"
    End
  End

  Describe "auto-detection from pom.xml"
    setup_java() {
      TEMP_DIR="$(mktemp -d)"
      printf '<project></project>\n' > "${TEMP_DIR}/pom.xml"
    }
    cleanup_java() { rm -rf "$TEMP_DIR"; }
    Before 'setup_java'
    After 'cleanup_java'

    It "detects java from pom.xml"
      When run script "${BRIK_BIN}" init --platform gitlab --dir "${TEMP_DIR}" --non-interactive
      The status should eq 0
      The output should include "Detected stack: java"
      The contents of file "${TEMP_DIR}/brik.yml" should include "stack: java"
    End
  End

  Describe "auto-detection from requirements.txt"
    setup_python() {
      TEMP_DIR="$(mktemp -d)"
      printf 'flask==2.0\n' > "${TEMP_DIR}/requirements.txt"
    }
    cleanup_python() { rm -rf "$TEMP_DIR"; }
    Before 'setup_python'
    After 'cleanup_python'

    It "detects python from requirements.txt"
      When run script "${BRIK_BIN}" init --platform gitlab --dir "${TEMP_DIR}" --non-interactive
      The status should eq 0
      The output should include "Detected stack: python"
      The contents of file "${TEMP_DIR}/brik.yml" should include "stack: python"
    End
  End

  Describe "refuses to overwrite existing brik.yml"
    setup_existing() {
      TEMP_DIR="$(mktemp -d)"
      printf 'version: 1\n' > "${TEMP_DIR}/brik.yml"
    }
    cleanup_existing() { rm -rf "$TEMP_DIR"; }
    Before 'setup_existing'
    After 'cleanup_existing'

    It "exits with error when brik.yml already exists"
      When run script "${BRIK_BIN}" init --stack node --platform gitlab --dir "${TEMP_DIR}" --non-interactive
      The status should eq 2
      The stderr should include "already exists"
    End
  End

  Describe "github platform"
    setup_project() {
      TEMP_DIR="$(mktemp -d)"
      printf '{"name":"test"}\n' > "${TEMP_DIR}/package.json"
    }
    cleanup_project() { rm -rf "$TEMP_DIR"; }
    Before 'setup_project'
    After 'cleanup_project'

    It "generates .github/workflows/ci.yml for github platform"
      When run script "${BRIK_BIN}" init --stack node --platform github --dir "${TEMP_DIR}" --non-interactive
      The status should eq 0
      The output should include "Created"
      The file "${TEMP_DIR}/.github/workflows/ci.yml" should be exist
    End
  End

  Describe "jenkins platform"
    setup_project() {
      TEMP_DIR="$(mktemp -d)"
      printf '{"name":"test"}\n' > "${TEMP_DIR}/package.json"
    }
    cleanup_project() { rm -rf "$TEMP_DIR"; }
    Before 'setup_project'
    After 'cleanup_project'

    It "generates Jenkinsfile for jenkins platform"
      When run script "${BRIK_BIN}" init --stack node --platform jenkins --dir "${TEMP_DIR}" --non-interactive
      The status should eq 0
      The output should include "Created"
      The file "${TEMP_DIR}/Jenkinsfile" should be exist
    End
  End

  Describe "unsupported stack"
    setup_unsupported_stack() { TEMP_DIR="$(mktemp -d)"; }
    cleanup_unsupported_stack() { rm -rf "$TEMP_DIR"; }
    Before 'setup_unsupported_stack'
    After 'cleanup_unsupported_stack'

    It "exits with code 2 for unsupported stack"
      When run script "${BRIK_BIN}" init --stack fortran --platform gitlab --dir "${TEMP_DIR}" --non-interactive
      The status should eq 2
      The stderr should include "unsupported stack"
    End
  End

  Describe "unsupported platform"
    setup_unsupported_platform() { TEMP_DIR="$(mktemp -d)"; }
    cleanup_unsupported_platform() { rm -rf "$TEMP_DIR"; }
    Before 'setup_unsupported_platform'
    After 'cleanup_unsupported_platform'

    It "exits with code 2 for unsupported platform"
      When run script "${BRIK_BIN}" init --stack node --platform aws --dir "${TEMP_DIR}" --non-interactive
      The status should eq 2
      The stderr should include "unsupported platform"
    End
  End

  Describe "non-interactive with undetectable stack"
    setup_undetectable() { TEMP_DIR="$(mktemp -d)"; }
    cleanup_undetectable() { rm -rf "$TEMP_DIR"; }
    Before 'setup_undetectable'
    After 'cleanup_undetectable'

    It "exits with code 2 when stack cannot be detected"
      When run script "${BRIK_BIN}" init --platform gitlab --dir "${TEMP_DIR}" --non-interactive
      The status should eq 2
      The stderr should include "could not detect stack"
    End
  End

  Describe "unknown option"
    It "exits with code 2 for unknown option"
      When run script "${BRIK_BIN}" init --badopt
      The status should eq 2
      The stderr should include "unknown option"
    End
  End

  Describe "auto-detection from Cargo.toml (rust)"
    setup_rust() {
      TEMP_DIR="$(mktemp -d)"
      printf '[package]\nname = "test"\n' > "${TEMP_DIR}/Cargo.toml"
    }
    cleanup_rust() { rm -rf "$TEMP_DIR"; }
    Before 'setup_rust'
    After 'cleanup_rust'

    It "detects rust from Cargo.toml"
      When run script "${BRIK_BIN}" init --platform gitlab --dir "${TEMP_DIR}" --non-interactive
      The status should eq 0
      The output should include "Detected stack: rust"
      The contents of file "${TEMP_DIR}/brik.yml" should include "stack: rust"
    End
  End

  Describe "auto-detection from .csproj (dotnet)"
    setup_dotnet() {
      TEMP_DIR="$(mktemp -d)"
      printf '<Project Sdk="Microsoft.NET.Sdk"></Project>\n' > "${TEMP_DIR}/Test.csproj"
    }
    cleanup_dotnet() { rm -rf "$TEMP_DIR"; }
    Before 'setup_dotnet'
    After 'cleanup_dotnet'

    It "detects dotnet from .csproj"
      When run script "${BRIK_BIN}" init --platform gitlab --dir "${TEMP_DIR}" --non-interactive
      The status should eq 0
      The output should include "Detected stack: dotnet"
      The contents of file "${TEMP_DIR}/brik.yml" should include "stack: dotnet"
    End
  End

End
