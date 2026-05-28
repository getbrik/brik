Describe "brik run"
  Include "$BRIK_HOME/spec/support/mock_helper.sh"

  Describe "brik run without subcommand"
    It "shows an error message"
      When run script "$BRIK_BIN" run
      The status should equal 2
      The stderr should include "requires a subcommand"
    End
  End

  Describe "brik run stage without name"
    It "shows an error message"
      When run script "$BRIK_BIN" run stage
      The status should equal 2
      The stderr should include "requires a stage name"
    End
  End

  Describe "brik run unknown subcommand"
    It "shows an error message"
      When run script "$BRIK_BIN" run foobar
      The status should equal 2
      The stderr should include "unknown run subcommand"
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

  Describe "brik run stage build --badopt"
    It "shows an error for unknown option"
      When run script "$BRIK_BIN" run stage build --badopt
      The status should equal 2
      The stderr should include "unknown option"
    End
  End

End
