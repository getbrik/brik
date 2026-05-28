Describe "secrets.sh (transverse secret-variable guard)"
  Include "$BRIK_PIPELINE_LIB/logging.sh"
  Include "$BRIK_TRANSVERSE_LIB/secrets.sh"

  Describe "transverse.secrets.require_var"
    It "fails with CONFIG_ERROR when var_name is empty"
      When call transverse.secrets.require_var "" "npm token"
      The status should equal "$BRIK_EXIT_CONFIG_ERROR"
      The stderr should include "npm token variable name is not configured"
    End

    It "fails with CONFIG_ERROR when var_name is not a valid identifier"
      When call transverse.secrets.require_var "bad name!" "test label"
      The status should equal "$BRIK_EXIT_CONFIG_ERROR"
      The stderr should include "is not a valid identifier"
    End

    It "fails with CONFIG_ERROR when the referenced variable is unset"
      # Ensure the probe variable is not in the environment.
      unset BRIK_SPEC_SECRET_PROBE
      When call transverse.secrets.require_var "BRIK_SPEC_SECRET_PROBE" "probe token"
      The status should equal "$BRIK_EXIT_CONFIG_ERROR"
      The stderr should include "is not set or empty"
    End

    It "fails with CONFIG_ERROR when the referenced variable is empty"
      export BRIK_SPEC_SECRET_PROBE=""
      When call transverse.secrets.require_var "BRIK_SPEC_SECRET_PROBE" "probe token"
      The status should equal "$BRIK_EXIT_CONFIG_ERROR"
      The stderr should include "is not set or empty"
      unset BRIK_SPEC_SECRET_PROBE
    End

    It "returns success when the referenced variable is a non-empty string"
      export BRIK_SPEC_SECRET_PROBE="secret-value"
      When call transverse.secrets.require_var "BRIK_SPEC_SECRET_PROBE" "probe token"
      The status should be success
      unset BRIK_SPEC_SECRET_PROBE
    End

    It "accepts a leading underscore in the variable name"
      export _BRIK_UNDERSCORED="x"
      When call transverse.secrets.require_var "_BRIK_UNDERSCORED" "underscored"
      The status should be success
      unset _BRIK_UNDERSCORED
    End
  End
End
