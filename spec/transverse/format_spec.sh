Describe "format.sh (Unicode table renderer)"
  Include "$BRIK_TRANSVERSE_LIB/format.sh"

  Describe "format.table"
    It "writes nothing when stdin is empty"
      When call format.table
      The status should be success
      The stderr should equal ""
      The stdout should equal ""
    End

    It "renders a header-only table with top and bottom rules"
      Data
        #|name|age
      End
      When call format.table --delim "|"
      The stderr should include "┌"
      The stderr should include "┐"
      The stderr should include "└"
      The stderr should include "┘"
      The stderr should include "│ name │ age │"
    End

    It "renders header, mid rule, and body rows"
      Data
        #|name|age
        #|alice|30
        #|bob|7
      End
      When call format.table --delim "|"
      The stderr should include "├"
      The stderr should include "┼"
      The stderr should include "┤"
      The stderr should include "│ alice │ 30  │"
      The stderr should include "│ bob   │ 7   │"
    End

    It "auto-sizes columns to the widest cell"
      Data
        #|stage|status
        #|init|ok
        #|container-scan|success
      End
      When call format.table --delim "|"
      The stderr should include "│ stage          │ status  │"
      The stderr should include "│ init           │ ok      │"
      The stderr should include "│ container-scan │ success │"
    End

    It "writes to stderr, not stdout"
      Data
        #|a|b
        #|1|2
      End
      When call format.table --delim "|"
      The stdout should equal ""
      The stderr should be present
    End

    It "skips blank lines from input"
      Data
        #|name|age
        #|
        #|alice|30
        #|
      End
      When call format.table --delim "|"
      The stderr should include "│ alice │ 30  │"
    End

    It "preserves multibyte glyphs in cells"
      Data
        #|stage|status
        #|sast|✓ success
      End
      When call format.table --delim "|"
      The stderr should include "│ sast  │ ✓ success │"
    End

    It "defaults to TAB delimiter"
      Data
        #|name	age
        #|alice	30
      End
      When call format.table
      The stderr should include "│ alice │ 30  │"
    End
  End
End
