Describe "pipeline context resolution helpers"
  Include "$BRIK_PIPELINE_LIB/pipeline.sh"

  Describe "_pipeline._resolve_context"
    It "returns snapshot when BRIK_COMMIT_TAG is unset"
      resolve_unset() {
        unset BRIK_COMMIT_TAG
        _pipeline._resolve_context
      }
      When call resolve_unset
      The output should equal "snapshot"
    End

    It "returns snapshot when BRIK_COMMIT_TAG is empty"
      resolve_empty() {
        BRIK_COMMIT_TAG="" _pipeline._resolve_context
      }
      When call resolve_empty
      The output should equal "snapshot"
    End

    It "returns release when BRIK_COMMIT_TAG is a stable version"
      resolve_release() {
        BRIK_COMMIT_TAG="v1.0.0" _pipeline._resolve_context
      }
      When call resolve_release
      The output should equal "release"
    End

    It "treats pre-release tags as release (no regex refinement)"
      resolve_prerelease() {
        BRIK_COMMIT_TAG="v1.2.3-rc1" _pipeline._resolve_context
      }
      When call resolve_prerelease
      The output should equal "release"
    End
  End

  Describe "_pipeline._resolve_continue_on_error"
    It "returns true for snapshot by default"
      resolve_snapshot_default() {
        unset BRIK_CONTINUE_ON_ERROR
        _pipeline._resolve_continue_on_error "snapshot" "false"
      }
      When call resolve_snapshot_default
      The output should equal "true"
    End

    It "returns false for release by default"
      resolve_release_default() {
        unset BRIK_CONTINUE_ON_ERROR
        _pipeline._resolve_continue_on_error "release" "false"
      }
      When call resolve_release_default
      The output should equal "false"
    End

    It "lets BRIK_CONTINUE_ON_ERROR=1 override release default"
      resolve_release_env_override_on() {
        BRIK_CONTINUE_ON_ERROR=1 _pipeline._resolve_continue_on_error "release" "false"
      }
      When call resolve_release_env_override_on
      The output should equal "true"
    End

    It "lets BRIK_CONTINUE_ON_ERROR=0 override snapshot default"
      resolve_snapshot_env_override_off() {
        BRIK_CONTINUE_ON_ERROR=0 _pipeline._resolve_continue_on_error "snapshot" "false"
      }
      When call resolve_snapshot_env_override_off
      The output should equal "false"
    End

    It "honours the CLI flag back-compat (forces true)"
      resolve_cli_flag() {
        unset BRIK_CONTINUE_ON_ERROR
        _pipeline._resolve_continue_on_error "release" "true"
      }
      When call resolve_cli_flag
      The output should equal "true"
    End

    It "lets explicit BRIK_CONTINUE_ON_ERROR=0 win over the CLI flag"
      resolve_env_beats_cli() {
        BRIK_CONTINUE_ON_ERROR=0 _pipeline._resolve_continue_on_error "snapshot" "true"
      }
      When call resolve_env_beats_cli
      The output should equal "false"
    End
  End
End
