Describe "brik CLI verbs"
  Include "$BRIK_HOME/spec/support/mock_helper.sh"

  Describe "brik stage without name"
    It "shows an error message"
      When run script "$BRIK_BIN" stage
      The status should equal 2
      The stderr should include "requires a stage name"
    End
  End

  Describe "brik unknown command"
    It "shows an error and help hint"
      When run script "$BRIK_BIN" foobar
      The status should equal 2
      The stderr should include "unknown command"
      The stderr should include "brik help"
    End
  End

  Describe "brik stage build --badopt"
    It "shows an error for unknown option"
      When run script "$BRIK_BIN" stage build --badopt
      The status should equal 2
      The stderr should include "unknown option"
    End
  End
End
