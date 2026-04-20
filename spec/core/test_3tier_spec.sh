Describe "test.sh - 3-tier resolution"
  Include "$BRIK_PIPELINE_LIB/logging.sh"
  Include "$BRIK_PIPELINE_LIB/tools.sh"
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

  # Note: stacks.detect_from_framework tests moved to spec/stacks/_detect_spec.sh.
End
