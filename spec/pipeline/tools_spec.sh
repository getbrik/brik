Describe "tools.sh"
  Include "$BRIK_PIPELINE_LIB/tools.sh"

  Describe "pipeline.require_tool"
    It "returns 0 for an available tool (bash)"
      When call pipeline.require_tool bash
      The status should be success
    End

    It "returns 3 and logs for a missing tool"
      When call pipeline.require_tool __brik_nonexistent_tool_12345__
      The status should equal 3
      The stderr should include "required tool not found"
      The stderr should include "__brik_nonexistent_tool_12345__"
    End
  End

  Describe "pipeline.require_file"
    setup() { TEST_FILE="$(mktemp)"; }
    cleanup() { rm -f "$TEST_FILE"; }
    Before 'setup'
    After 'cleanup'

    It "returns 0 for an existing file"
      When call pipeline.require_file "$TEST_FILE"
      The status should be success
    End

    It "returns 6 and logs for a missing file"
      When call pipeline.require_file "/nonexistent/path/file.txt"
      The status should equal 6
      The stderr should include "required file not found"
    End
  End

  Describe "pipeline.require_dir"
    setup() { TEST_DIR="$(mktemp -d)"; }
    cleanup() { rm -rf "$TEST_DIR"; }
    Before 'setup'
    After 'cleanup'

    It "returns 0 for an existing directory"
      When call pipeline.require_dir "$TEST_DIR"
      The status should be success
    End

    It "returns 6 and logs for a missing directory"
      When call pipeline.require_dir "/nonexistent/path/dir"
      The status should equal 6
      The stderr should include "required directory not found"
    End
  End
End
