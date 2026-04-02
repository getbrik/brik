Describe "test/dotnet.sh"
  Include "$BRIK_RUNTIME_LIB/logging.sh"
  Include "$BRIK_RUNTIME_LIB/tools.sh"
  Include "$BRIK_CORE_LIB/test/dotnet.sh"

  Describe "test.dotnet.cmd"
    It "returns dotnet test for dotnet framework"
      When call test.dotnet.cmd "dotnet" "/workspace" ""
      The output should equal "dotnet test"
    End

    It "returns 7 for unsupported framework"
      When call test.dotnet.cmd "unknown" "/workspace" ""
      The status should equal 7
      The stderr should include "unsupported .NET test framework"
    End
  End

  Describe "test.dotnet.run_cmd"
    It "delegates to dotnet test by default"
      When call test.dotnet.run_cmd "/workspace" ""
      The output should equal "dotnet test"
    End
  End
End
