Describe "version-info.sh (version metadata)"
  Include "$BRIK_HOME/runtime/bash/lib/runtime/version-info.sh"

  Describe "exports version constants"
    It "defines BRIK_VERSION"
      The variable BRIK_VERSION should be present
      The variable BRIK_VERSION should not equal ""
    End

    It "defines BRIK_SCHEMA_VERSION"
      The variable BRIK_SCHEMA_VERSION should equal "v1"
    End

    It "defines BRIK_RUNTIME"
      The variable BRIK_RUNTIME should equal "bash"
    End

    It "defines BRIK_REF from BRIK_VERSION"
      The variable BRIK_REF should start with "v"
    End
  End

  Describe "guard against double-sourcing"
    It "sets the loaded flag"
      The variable _BRIK_VERSION_INFO_LOADED should equal "1"
    End
  End
End
