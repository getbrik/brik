Describe "cli/run.sh - --dry-run flag"
  Include "$BRIK_PIPELINE_LIB/version-info.sh"
  Include "$BRIK_PIPELINE_LIB/logging.sh"
  Include "$BRIK_PIPELINE_LIB/error.sh"
  Include "$BRIK_PIPELINE_LIB/tools.sh"
  Include "$BRIK_PIPELINE_LIB/loader.sh"
  Include "$BRIK_CLI_LIB/helpers.sh"
  Include "$BRIK_CLI_LIB/run.sh"

  setup() {
    WORKSPACE="$(mktemp -d)"
    printf 'version: 1\nproject:\n  name: dryrun-test\n  stack: node\n' > "${WORKSPACE}/brik.yml"

    # Stub the heavy plumbing so cli.run.stage / cli.run.pipeline never
    # actually source the local wrapper or run a stage. We only care that
    # BRIK_DRY_RUN is exported correctly when the flag is parsed.
    _cli.run._setup_local_env() { return 0; }
    _cli.run._runtime() { return 0; }
    brik.local.run_stage() { return 0; }
    brik.local.run_pipeline() { return 0; }

    unset BRIK_DRY_RUN 2>/dev/null || true
  }
  cleanup() {
    rm -rf "$WORKSPACE"
    unset BRIK_DRY_RUN 2>/dev/null || true
  }
  Before 'setup'
  After 'cleanup'

  Describe "cli.run.stage"
    It "exports BRIK_DRY_RUN=true when --dry-run is passed"
      run_with_flag() {
        cli.run.stage build --workspace "$WORKSPACE" --dry-run >/dev/null 2>&1
        printf '%s' "${BRIK_DRY_RUN:-UNSET}"
      }
      When call run_with_flag
      The output should equal "true"
    End

    It "leaves BRIK_DRY_RUN unset when --dry-run is omitted"
      run_without_flag() {
        cli.run.stage build --workspace "$WORKSPACE" >/dev/null 2>&1
        printf '%s' "${BRIK_DRY_RUN:-UNSET}"
      }
      When call run_without_flag
      The output should equal "UNSET"
    End

    It "preserves a pre-existing BRIK_DRY_RUN=true exported by the caller"
      run_with_caller_env() {
        export BRIK_DRY_RUN="true"
        cli.run.stage build --workspace "$WORKSPACE" >/dev/null 2>&1
        printf '%s' "$BRIK_DRY_RUN"
      }
      When call run_with_caller_env
      The output should equal "true"
    End

    It "accepts --dry-run combined with --config and --workspace"
      run_combined() {
        cli.run.stage build --workspace "$WORKSPACE" --config "${WORKSPACE}/brik.yml" --dry-run >/dev/null 2>&1
        printf '%s' "${BRIK_DRY_RUN:-UNSET}"
      }
      When call run_combined
      The output should equal "true"
    End
  End

  Describe "cli.run.pipeline"
    It "exports BRIK_DRY_RUN=true when --dry-run is passed"
      run_with_flag() {
        cli.run.pipeline --workspace "$WORKSPACE" --dry-run >/dev/null 2>&1
        printf '%s' "${BRIK_DRY_RUN:-UNSET}"
      }
      When call run_with_flag
      The output should equal "true"
    End

    It "leaves BRIK_DRY_RUN unset when --dry-run is omitted"
      run_without_flag() {
        cli.run.pipeline --workspace "$WORKSPACE" >/dev/null 2>&1
        printf '%s' "${BRIK_DRY_RUN:-UNSET}"
      }
      When call run_without_flag
      The output should equal "UNSET"
    End

    It "accepts --dry-run alongside pipeline shape flags"
      run_combined() {
        cli.run.pipeline --workspace "$WORKSPACE" --with-deploy --dry-run --continue-on-error >/dev/null 2>&1
        printf '%s' "${BRIK_DRY_RUN:-UNSET}"
      }
      When call run_combined
      The output should equal "true"
    End
  End
End
