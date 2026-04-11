Describe "quality/lint.sh - Tier 3 auto-detect edge cases"
  Include "$BRIK_RUNTIME_LIB/logging.sh"
  Include "$BRIK_RUNTIME_LIB/tools.sh"
  Include "$BRIK_CORE_LIB/quality/lint.sh"
  Include "$BRIK_HOME/runtime/bash/spec/support/mock_helper.sh"

  Describe "quality.lint.run"
    Describe "Tier 3: Gradle auto-detect with gradle present"
      setup_gradle_auto() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock.log"
        printf 'apply plugin: "java"\n' > "${TEST_WS}/build.gradle"
        mock.create_logging "gradle" "$MOCK_LOG"
        mock.activate
      }
      cleanup_gradle_auto() {
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_gradle_auto'
      After 'cleanup_gradle_auto'

      It "auto-detects gradle checkstyleMain"
        invoke_gradle_auto() {
          quality.lint.run "$TEST_WS" 2>/dev/null || return 1
          grep -q "gradle checkstyleMain" "$MOCK_LOG"
        }
        When call invoke_gradle_auto
        The status should be success
      End
    End

    Describe "Tier 3: Gradle auto-detect with gradle missing"
      setup_gradle_missing() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        printf 'apply plugin: "java"\n' > "${TEST_WS}/build.gradle"
        mock.isolate
      }
      cleanup_gradle_missing() {
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_gradle_missing'
      After 'cleanup_gradle_missing'

      It "skips when gradle not found"
        When call quality.lint.run "$TEST_WS"
        The status should be success
        The stderr should include "gradle not found"
      End
    End

    Describe "Tier 3: .NET dotnet missing"
      setup_dotnet_missing() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        printf '<Project Sdk="Microsoft.NET.Sdk"></Project>\n' > "${TEST_WS}/Test.csproj"
        mock.isolate
      }
      cleanup_dotnet_missing() {
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_dotnet_missing'
      After 'cleanup_dotnet_missing'

      It "returns 3 when dotnet not found for .NET"
        When call quality.lint.run "$TEST_WS"
        The status should equal 3
        The stderr should include "dotnet not found"
      End
    End

    Describe "Tier 3: Rust cargo missing"
      setup_rust_no_cargo() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        printf '[package]\nname = "test"\n' > "${TEST_WS}/Cargo.toml"
        mock.isolate
      }
      cleanup_rust_no_cargo() {
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_rust_no_cargo'
      After 'cleanup_rust_no_cargo'

      It "returns 3 when cargo not found for Rust"
        When call quality.lint.run "$TEST_WS"
        The status should equal 3
        The stderr should include "cargo not found"
      End
    End

    Describe "Tier 3: Python via setup.py"
      setup_setuppy() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock.log"
        printf 'from setuptools import setup\n' > "${TEST_WS}/setup.py"
        mock.create_logging "ruff" "$MOCK_LOG"
        mock.activate
      }
      cleanup_setuppy() {
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_setuppy'
      After 'cleanup_setuppy'

      It "detects Python from setup.py"
        invoke_setuppy() {
          quality.lint.run "$TEST_WS" 2>/dev/null || return 1
          grep -q "ruff check" "$MOCK_LOG"
        }
        When call invoke_setuppy
        The status should be success
      End
    End

    Describe "with failing linter"
      setup_fail() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        printf '{"name":"test"}\n' > "${TEST_WS}/package.json"
        printf 'export default [];\n' > "${TEST_WS}/eslint.config.js"
        mock.create_exit "npx" 1
        mock.activate
      }
      cleanup_fail() {
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_fail'
      After 'cleanup_fail'

      It "returns 10 when lint fails"
        When call quality.lint.run "$TEST_WS"
        The status should equal 10
        The stderr should include "lint violations found"
      End
    End
  End
End
