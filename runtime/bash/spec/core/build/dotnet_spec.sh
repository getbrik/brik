Describe "build/dotnet.sh"
  Include "$BRIK_RUNTIME_LIB/logging.sh"
  Include "$BRIK_RUNTIME_LIB/tools.sh"
  Include "$BRIK_CORE_LIB/build/dotnet.sh"
  Include "$BRIK_HOME/runtime/bash/spec/support/mock_helper.sh"

  Describe "build.dotnet.run"
    It "returns 6 for nonexistent workspace"
      When call build.dotnet.run "/nonexistent/workspace"
      The status should equal 6
      The stderr should include "required directory not found"
    End

    It "returns 2 for unknown option"
      When call build.dotnet.run "$WORKSPACES/dotnet-simple" --badopt foo
      The status should equal 2
      The stderr should include "unknown option"
    End

    It "returns 6 when no .csproj or .sln found"
      When call build.dotnet.run "$WORKSPACES/unknown"
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
        When call build.dotnet.run "$TEST_WS"
        The status should be success
        The stderr should include "build completed successfully"
      End

      It "runs dotnet build"
        invoke_dotnet_check() {
          build.dotnet.run "$TEST_WS" 2>/dev/null || return 1
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
          build.dotnet.run "$TEST_WS" --configuration Release 2>/dev/null || return 1
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
        When call build.dotnet.run "$TEST_WS"
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
        When call build.dotnet.run "$TEST_WS"
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
        When call build.dotnet.run "$TEST_WS"
        The status should equal 3
        The stderr should include "required tool not found"
      End
    End
  End
End
