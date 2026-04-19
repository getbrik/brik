Describe "test.sh - 3-tier resolution"
  Include "$BRIK_RUNTIME_LIB/logging.sh"
  Include "$BRIK_RUNTIME_LIB/tools.sh"
  Include "$BRIK_CORE_LIB/test.sh"

  Describe "Tier 1: BRIK_TEST_COMMAND override"
    setup_cmd() {
      TEST_WS="$(mktemp -d)"
      printf '{"name":"test"}\n' > "${TEST_WS}/package.json"
      export BRIK_TEST_COMMAND="echo test-passed"
    }
    cleanup_cmd() {
      unset BRIK_TEST_COMMAND
      rm -rf "$TEST_WS"
    }
    Before 'setup_cmd'
    After 'cleanup_cmd'

    It "uses BRIK_TEST_COMMAND as Tier 1 override"
      When call test.run "$TEST_WS"
      The status should be success
      The stdout should include "test-passed"
      The stderr should include "tests passed"
    End
  End

  Describe "extended framework mappings"
    It "maps vitest to node"
      When call _test._stack_for_framework "vitest"
      The output should equal "node"
    End

    It "maps mocha to node"
      When call _test._stack_for_framework "mocha"
      The output should equal "node"
    End

    It "maps unittest to python"
      When call _test._stack_for_framework "unittest"
      The output should equal "python"
    End

    It "maps tox to python"
      When call _test._stack_for_framework "tox"
      The output should equal "python"
    End

    It "maps xunit to dotnet"
      When call _test._stack_for_framework "xunit"
      The output should equal "dotnet"
    End

    It "maps nunit to dotnet"
      When call _test._stack_for_framework "nunit"
      The output should equal "dotnet"
    End
  End
End
