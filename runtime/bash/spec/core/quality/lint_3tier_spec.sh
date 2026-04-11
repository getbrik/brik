Describe "quality/lint.sh - 3-tier resolution"
  Include "$BRIK_RUNTIME_LIB/logging.sh"
  Include "$BRIK_RUNTIME_LIB/tools.sh"
  Include "$BRIK_CORE_LIB/quality/lint.sh"
  Include "$BRIK_HOME/runtime/bash/spec/support/mock_helper.sh"

  Describe "Tier 1: BRIK_QUALITY_LINT_COMMAND override"
    setup_cmd_override() {
      mock.setup
      TEST_WS="$(mktemp -d)"
      mock.create_script "biome" 'printf "biome %s\n" "$*"
exit 0'
      mock.activate
      export BRIK_QUALITY_LINT_COMMAND="biome check ."
    }
    cleanup_cmd_override() {
      unset BRIK_QUALITY_LINT_COMMAND
      mock.cleanup
      rm -rf "$TEST_WS"
    }
    Before 'setup_cmd_override'
    After 'cleanup_cmd_override'

    It "uses BRIK_QUALITY_LINT_COMMAND regardless of workspace content"
      When call quality.lint.run "$TEST_WS"
      The status should be success
      The stdout should be present
      The stderr should include "lint passed"
    End
  End

  Describe "Tier 2: BRIK_QUALITY_LINT_TOOL override"
    setup_tool_override() {
      mock.setup
      TEST_WS="$(mktemp -d)"
      MOCK_LOG="${TEST_WS}/mock.log"
      printf '{"name":"test"}\n' > "${TEST_WS}/package.json"
      mock.create_logging "npx" "$MOCK_LOG"
      mock.activate
      export BRIK_QUALITY_LINT_TOOL="biome"
    }
    cleanup_tool_override() {
      unset BRIK_QUALITY_LINT_TOOL
      mock.cleanup
      rm -rf "$TEST_WS"
    }
    Before 'setup_tool_override'
    After 'cleanup_tool_override'

    It "uses biome when BRIK_QUALITY_LINT_TOOL=biome"
      invoke_biome() {
        quality.lint.run "$TEST_WS" 2>/dev/null || return 1
        grep -q "biome" "$MOCK_LOG"
      }
      When call invoke_biome
      The status should be success
    End
  End

  Describe "Java lint with checkstyle"
    setup_java_lint() {
      mock.setup
      TEST_WS="$(mktemp -d)"
      MOCK_LOG="${TEST_WS}/mock.log"
      printf '<project/>\n' > "${TEST_WS}/pom.xml"
      mock.create_logging "mvn" "$MOCK_LOG"
      mock.activate
    }
    cleanup_java_lint() {
      mock.cleanup
      rm -rf "$TEST_WS"
    }
    Before 'setup_java_lint'
    After 'cleanup_java_lint'

    It "runs mvn checkstyle:check for Java/Maven projects"
      invoke_checkstyle() {
        quality.lint.run "$TEST_WS" 2>/dev/null || return 1
        grep -q "checkstyle" "$MOCK_LOG"
      }
      When call invoke_checkstyle
      The status should be success
    End
  End

  Describe ".NET lint with dotnet format"
    setup_dotnet_lint() {
      mock.setup
      TEST_WS="$(mktemp -d)"
      MOCK_LOG="${TEST_WS}/mock.log"
      printf '<Project Sdk="Microsoft.NET.Sdk"></Project>\n' > "${TEST_WS}/Test.csproj"
      mock.create_logging "dotnet" "$MOCK_LOG"
      mock.activate
    }
    cleanup_dotnet_lint() {
      mock.cleanup
      rm -rf "$TEST_WS"
    }
    Before 'setup_dotnet_lint'
    After 'cleanup_dotnet_lint'

    It "runs dotnet format for .NET projects"
      invoke_dotnet_fmt() {
        quality.lint.run "$TEST_WS" 2>/dev/null || return 1
        grep -q "dotnet format" "$MOCK_LOG"
      }
      When call invoke_dotnet_fmt
      The status should be success
    End
  End
End
