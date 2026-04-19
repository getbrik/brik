Describe "banner.sh"
  Include "$BRIK_RUNTIME_LIB/banner.sh"

  Describe "banner.brik"
    It "outputs the ASCII logo on stderr"
      When call banner.brik "0.2.0"
      The status should be success
      The stderr should include "████████"
    End

    It "outputs the version below the logo"
      When call banner.brik "0.2.0"
      The stderr should include "v0.2.0"
    End

    It "handles version with v prefix"
      When call banner.brik "v1.0.0"
      The stderr should include "v1.0.0"
    End

    It "works without a version argument"
      When call banner.brik
      The status should be success
      The stderr should include "████████"
    End

    It "does not write anything to stdout"
      When call banner.brik "0.2.0"
      The stdout should equal ""
      The stderr should be present
    End
  End

  Describe "banner.stage"
    It "outputs the stage name in uppercase on stderr"
      When call banner.stage "build"
      The stderr should include "BUILD"
    End

    It "outputs visual delimiters"
      When call banner.stage "build"
      The stderr should include "══════"
    End

    It "uppercases multi-word stage names"
      When call banner.stage "quality"
      The stderr should include "QUALITY"
    End

    It "does not write anything to stdout"
      When call banner.stage "test"
      The stdout should equal ""
      The stderr should be present
    End
  End
End
