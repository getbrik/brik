Describe "banner.sh"
  Include "$BRIK_PIPELINE_LIB/banner.sh"

  Describe "banner.brik"
    It "outputs the ASCII logo on stderr"
      When call banner.brik "1.0.0"
      The status should be success
      The stderr should include "████████"
    End

    It "outputs the version below the logo"
      When call banner.brik "1.0.0"
      The stderr should include "v1.0.0"
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
      When call banner.brik "1.0.0"
      The stdout should equal ""
      The stderr should be present
    End
  End

  Describe "banner.stage"
    It "outputs the stage name in spaced uppercase on stderr"
      When call banner.stage "build"
      The stderr should include "B U I L D"
    End

    It "outputs the box-drawing top corner"
      When call banner.stage "build"
      The stderr should include "┌"
      The stderr should include "─"
      The stderr should include "┐"
    End

    It "outputs the box-drawing bottom corner"
      When call banner.stage "build"
      The stderr should include "└"
      The stderr should include "┘"
    End

    It "uppercases multi-word stage names"
      When call banner.stage "quality"
      The stderr should include "Q U A L I T Y"
    End

    It "shows runner metadata when provided"
      When call banner.stage "sast" "ghcr.io/getbrik/runner:1"
      # render.kv now uses padding-as-separator (no colon)
      The stderr should include "runner  "
      The stderr should include "ghcr.io/getbrik/runner:1"
    End

    It "ignores extra positional arguments (legacy tech arg)"
      # banner.stage used to accept a 3rd "tech" argument that was never
      # populated and always rendered as 'tech: -'. The arg was removed in
      # the 0.6.x cleanup but bash silently accepts extra args, so legacy
      # callers do not break.
      When call banner.stage "sast" "ghcr.io/getbrik/runner:1" "semgrep"
      The stderr should include "runner  "
      The stderr should not include "tech "
      The stderr should not include "semgrep"
    End

    It "falls back to '-' when runner is missing"
      When call banner.stage "build"
      The stderr should include "runner  "
      The stderr should match pattern "*runner *-*"
      The stderr should not include "tech "
    End

    It "does not write anything to stdout"
      When call banner.stage "test"
      The stdout should equal ""
      The stderr should be present
    End
  End
End
