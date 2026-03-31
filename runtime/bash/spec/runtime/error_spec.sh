Describe "error.sh"
  Include "$BRIK_RUNTIME_LIB/error.sh"

  Describe "exit code constants"
    It "defines BRIK_EXIT_OK as 0"
      The value "$BRIK_EXIT_OK" should equal "0"
    End

    It "defines BRIK_EXIT_FAILURE as 1"
      The value "$BRIK_EXIT_FAILURE" should equal "1"
    End

    It "defines BRIK_EXIT_INVALID_INPUT as 2"
      The value "$BRIK_EXIT_INVALID_INPUT" should equal "2"
    End

    It "defines BRIK_EXIT_MISSING_DEP as 3"
      The value "$BRIK_EXIT_MISSING_DEP" should equal "3"
    End

    It "defines BRIK_EXIT_IO_FAILURE as 6"
      The value "$BRIK_EXIT_IO_FAILURE" should equal "6"
    End

    It "defines BRIK_EXIT_CONFIG_ERROR as 7"
      The value "$BRIK_EXIT_CONFIG_ERROR" should equal "7"
    End
  End

  Describe "error.raise"
    It "returns the given exit code and logs"
      When call error.raise 5 "external command failed"
      The status should equal 5
      The stderr should include "[ERROR]"
      The stderr should include "external command failed"
    End

    It "returns 2 and logs for bad input"
      When call error.raise 2 "bad input"
      The status should equal 2
      The stderr should include "bad input"
    End
  End
End
