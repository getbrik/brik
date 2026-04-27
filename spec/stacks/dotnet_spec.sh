Describe "build/dotnet.sh"
  Include "$BRIK_PIPELINE_LIB/logging.sh"
  Include "$BRIK_PIPELINE_LIB/tools.sh"
  Include "$BRIK_STACKS_LIB/dotnet.sh"
  Include "$BRIK_HOME/spec/support/mock_helper.sh"

  Describe "stacks.dotnet.build"
    It "returns 6 for nonexistent workspace"
      When call stacks.dotnet.build "/nonexistent/workspace"
      The status should equal 6
      The stderr should include "required directory not found"
    End

    It "returns 2 for unknown option"
      When call stacks.dotnet.build "$WORKSPACES/dotnet-simple" --badopt foo
      The status should equal 2
      The stderr should include "unknown option"
    End

    It "returns 6 when no .csproj or .sln found"
      When call stacks.dotnet.build "$WORKSPACES/unknown"
      The status should equal 6
      The stderr should include "no .csproj or .sln found"
    End

    Describe "with mock dotnet"
      setup_dotnet() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_dotnet.log"
        printf '<Project Sdk="Microsoft.NET.Sdk"><PropertyGroup><TargetFramework>net8.0</TargetFramework></PropertyGroup></Project>\n' > "${TEST_WS}/Test.csproj"
        mock.create_logging "dotnet" "$MOCK_LOG"
        mock.activate
      }
      cleanup_dotnet() {
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_dotnet'
      After 'cleanup_dotnet'

      It "succeeds and reports completion"
        When call stacks.dotnet.build "$TEST_WS"
        The status should be success
        The stderr should include "build completed successfully"
      End

      It "runs dotnet build"
        invoke_dotnet_check() {
          stacks.dotnet.build "$TEST_WS" 2>/dev/null || return 1
          grep -q "^dotnet build" "$MOCK_LOG"
        }
        When call invoke_dotnet_check
        The status should be success
      End
    End

    Describe "with --configuration Release"
      setup_dotnet_release() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_dotnet.log"
        printf '<Project Sdk="Microsoft.NET.Sdk"></Project>\n' > "${TEST_WS}/Test.csproj"
        mock.create_logging "dotnet" "$MOCK_LOG"
        mock.activate
      }
      cleanup_dotnet_release() {
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_dotnet_release'
      After 'cleanup_dotnet_release'

      It "passes --configuration flag"
        invoke_config_check() {
          stacks.dotnet.build "$TEST_WS" --configuration Release 2>/dev/null || return 1
          grep -q "\-\-configuration Release" "$MOCK_LOG"
        }
        When call invoke_config_check
        The status should be success
      End
    End

    Describe "with .sln file"
      setup_dotnet_sln() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_dotnet.log"
        printf 'Microsoft Visual Studio Solution File\n' > "${TEST_WS}/App.sln"
        mock.create_logging "dotnet" "$MOCK_LOG"
        mock.activate
      }
      cleanup_dotnet_sln() {
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_dotnet_sln'
      After 'cleanup_dotnet_sln'

      It "builds with .sln file"
        When call stacks.dotnet.build "$TEST_WS"
        The status should be success
        The stderr should include "build completed successfully"
      End
    End

    Describe "with failing dotnet"
      setup_dotnet_fail() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        printf '<Project Sdk="Microsoft.NET.Sdk"></Project>\n' > "${TEST_WS}/Test.csproj"
        mock.create_exit "dotnet" 1
        mock.activate
      }
      cleanup_dotnet_fail() {
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_dotnet_fail'
      After 'cleanup_dotnet_fail'

      It "returns 5 when dotnet fails"
        When call stacks.dotnet.build "$TEST_WS"
        The status should equal 5
        The stderr should include "build failed"
      End
    End

    Describe "require_tool dotnet failure"
      setup_no_dotnet() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        printf '<Project Sdk="Microsoft.NET.Sdk"></Project>\n' > "${TEST_WS}/Test.csproj"
        mock.isolate
      }
      cleanup_no_dotnet() {
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_no_dotnet'
      After 'cleanup_no_dotnet'

      It "returns 3 when dotnet is not on PATH"
        When call stacks.dotnet.build "$TEST_WS"
        The status should equal 3
        The stderr should include "required tool not found"
      End
    End
  End
End
Describe "test/dotnet.sh"
  Include "$BRIK_PIPELINE_LIB/logging.sh"
  Include "$BRIK_PIPELINE_LIB/tools.sh"
  Include "$BRIK_STACKS_LIB/dotnet.sh"

  Describe "stacks.dotnet.test_cmd"
    It "returns dotnet test for dotnet framework"
      When call stacks.dotnet.test_cmd "dotnet" "/workspace" ""
      The output should equal "dotnet test"
    End

    It "returns 7 for unsupported framework"
      When call stacks.dotnet.test_cmd "unknown" "/workspace" ""
      The status should equal 7
      The stderr should include "unsupported .NET test framework"
    End

    Describe "with BRIK_TEST_REPORTS_ENABLED=true"
      setup_reports_on() { export BRIK_TEST_REPORTS_ENABLED=true; }
      cleanup_reports_on() {
        unset BRIK_TEST_REPORTS_ENABLED BRIK_TEST_COVERAGE_DIR BRIK_TEST_JUNIT_PATH
      }
      Before 'setup_reports_on'
      After 'cleanup_reports_on'

      It "injects coverage and junit logger flags for dotnet"
        When call stacks.dotnet.test_cmd "dotnet" "/workspace" ""
        The output should include "dotnet test"
        The output should include "--collect:'XPlat Code Coverage'"
        The output should include "--logger:'junit;LogFilePath=reports/junit.xml'"
        The output should include "--results-directory 'coverage'"
      End

      It "flattens coverage.cobertura.xml from the GUID subdir"
        When call stacks.dotnet.test_cmd "dotnet" "/workspace" ""
        The output should include "find 'coverage' -name 'coverage.cobertura.xml'"
        The output should include "cp -f {} 'coverage/coverage.xml'"
        The output should include "exit \$_rc"
      End

      It "honours BRIK_TEST_COVERAGE_DIR override"
        export BRIK_TEST_COVERAGE_DIR="custom/cov"
        When call stacks.dotnet.test_cmd "dotnet" "/workspace" ""
        The output should include "--results-directory 'custom/cov'"
      End

      It "honours BRIK_TEST_JUNIT_PATH override"
        export BRIK_TEST_JUNIT_PATH="custom/junit.xml"
        When call stacks.dotnet.test_cmd "dotnet" "/workspace" ""
        The output should include "--logger:'junit;LogFilePath=custom/junit.xml'"
      End
    End

    Describe "with BRIK_TEST_REPORTS_ENABLED=false"
      setup_reports_off() { export BRIK_TEST_REPORTS_ENABLED=false; }
      cleanup_reports_off() { unset BRIK_TEST_REPORTS_ENABLED; }
      Before 'setup_reports_off'
      After 'cleanup_reports_off'

      It "leaves dotnet test_cmd unchanged"
        When call stacks.dotnet.test_cmd "dotnet" "/workspace" ""
        The output should equal "dotnet test"
      End
    End
  End

  Describe "stacks.dotnet.test"
    It "delegates to dotnet test by default"
      When call stacks.dotnet.test "/workspace" ""
      The output should equal "dotnet test"
    End
  End
End
