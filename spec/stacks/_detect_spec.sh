Describe "stacks/_detect.sh (stack detection primitives)"
  Include "$BRIK_PIPELINE_LIB/logging.sh"
  Include "$BRIK_STACKS_LIB/_detect.sh"

  Describe "stacks.detect"
    It "detects node from package.json"
      When call stacks.detect "$WORKSPACES/node-simple"
      The output should equal "node"
    End

    It "detects java from pom.xml"
      When call stacks.detect "$WORKSPACES/java-maven"
      The output should equal "java"
    End

    It "detects python from pyproject.toml"
      When call stacks.detect "$WORKSPACES/python-simple"
      The output should equal "python"
    End

    It "detects rust from Cargo.toml"
      When call stacks.detect "$WORKSPACES/rust-simple"
      The output should equal "rust"
    End

    It "detects dotnet from .csproj file"
      When call stacks.detect "$WORKSPACES/dotnet-simple"
      The output should equal "dotnet"
    End

    It "returns 1 for unknown workspace"
      When call stacks.detect "$WORKSPACES/unknown"
      The status should equal 1
      The stderr should include "cannot detect stack"
    End
  End

  Describe "stacks.detect_from_framework"
    It "maps jest to node"
      When call stacks.detect_from_framework "jest"
      The output should equal "node"
    End

    It "maps vitest to node"
      When call stacks.detect_from_framework "vitest"
      The output should equal "node"
    End

    It "returns failure for mocha (not supported)"
      When call stacks.detect_from_framework "mocha"
      The status should be failure
      The output should equal ""
    End

    It "maps junit to java"
      When call stacks.detect_from_framework "junit"
      The output should equal "java"
    End

    It "maps pytest to python"
      When call stacks.detect_from_framework "pytest"
      The output should equal "python"
    End

    It "maps unittest to python"
      When call stacks.detect_from_framework "unittest"
      The output should equal "python"
    End

    It "maps tox to python"
      When call stacks.detect_from_framework "tox"
      The output should equal "python"
    End

    It "maps cargo to rust"
      When call stacks.detect_from_framework "cargo"
      The output should equal "rust"
    End

    It "maps xunit to dotnet"
      When call stacks.detect_from_framework "xunit"
      The output should equal "dotnet"
    End

    It "maps nunit to dotnet"
      When call stacks.detect_from_framework "nunit"
      The output should equal "dotnet"
    End

    It "returns 1 for unknown framework"
      When call stacks.detect_from_framework "unknown-fw"
      The status should equal 1
    End
  End
End
