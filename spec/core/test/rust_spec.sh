Describe "test/rust.sh"
  Include "$BRIK_RUNTIME_LIB/logging.sh"
  Include "$BRIK_RUNTIME_LIB/tools.sh"
  Include "$BRIK_CORE_LIB/test/rust.sh"

  Describe "test.rust.cmd"
    It "returns cargo test for cargo framework"
      When call test.rust.cmd "cargo" "/workspace" ""
      The output should equal "cargo test"
    End

    It "returns 7 for unsupported framework"
      When call test.rust.cmd "unknown" "/workspace" ""
      The status should equal 7
      The stderr should include "unsupported Rust test framework"
    End
  End

  Describe "test.rust.run_cmd"
    It "delegates to cargo test by default"
      When call test.rust.run_cmd "/workspace" ""
      The output should equal "cargo test"
    End
  End
End
