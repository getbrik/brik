#shellcheck shell=bash
# Contract for lib/transverse/gating.sh (SC20).
#
# Each schedulable stage (release, package, deploy) gets a trigger block
# in brik.yml. The runtime exports those flags as
# BRIK_<PREFIX>_TRIGGER_{ON_TAG, ON_MAIN, ON_FEATURE, MANUAL}, plus a
# sentinel BRIK_<PREFIX>_TRIGGER_CONFIGURED=true when the block is
# present. gating.should_run_stage <prefix> answers whether the current
# pipeline context (tag/branch/manual) satisfies any of the trigger
# flags. Returns rc=0 to run, rc=1 to skip.
#
# Legacy compat: when CONFIGURED is unset, the helper returns 0
# (preserves the pre-SC20 always-run semantic).

Describe "lib/transverse/gating.sh"
  Include "$BRIK_HOME/lib/pipeline/logging.sh"
  Include "$BRIK_HOME/lib/transverse/gating.sh"

  reset_env() {
    unset BRIK_RELEASE_TRIGGER_CONFIGURED \
          BRIK_RELEASE_TRIGGER_ON_TAG \
          BRIK_RELEASE_TRIGGER_ON_MAIN \
          BRIK_RELEASE_TRIGGER_ON_FEATURE \
          BRIK_RELEASE_TRIGGER_MANUAL
    unset BRIK_PACKAGE_TRIGGER_CONFIGURED \
          BRIK_PACKAGE_TRIGGER_ON_TAG \
          BRIK_PACKAGE_TRIGGER_ON_MAIN \
          BRIK_PACKAGE_TRIGGER_ON_FEATURE \
          BRIK_PACKAGE_TRIGGER_MANUAL
    unset BRIK_COMMIT_TAG BRIK_COMMIT_BRANCH BRIK_TRIGGER_MANUAL BRIK_DEFAULT_BRANCH
  }
  Before 'reset_env'
  After  'reset_env'

  Describe "legacy compat (trigger block absent)"
    It "returns 0 (always run) when BRIK_RELEASE_TRIGGER_CONFIGURED is unset"
      When call gating.should_run_stage RELEASE
      The status should equal 0
    End

    It "ignores tag/branch context when trigger is unconfigured"
      run_unconfigured() {
        export BRIK_COMMIT_BRANCH="feature/x"
        gating.should_run_stage RELEASE
      }
      When call run_unconfigured
      The status should equal 0
    End
  End

  Describe "on-tag flag"
    setup_release_on_tag() {
      export BRIK_RELEASE_TRIGGER_CONFIGURED="true"
      export BRIK_RELEASE_TRIGGER_ON_TAG="true"
      export BRIK_RELEASE_TRIGGER_ON_MAIN="false"
      export BRIK_RELEASE_TRIGGER_MANUAL="false"
    }
    Before 'setup_release_on_tag'

    It "runs when BRIK_COMMIT_TAG is set"
      do_run() {
        export BRIK_COMMIT_TAG="v1.0.0"
        gating.should_run_stage RELEASE
      }
      When call do_run
      The status should equal 0
    End

    It "skips when BRIK_COMMIT_TAG is empty and no other trigger matches"
      do_skip() {
        export BRIK_COMMIT_BRANCH="main"
        gating.should_run_stage RELEASE
      }
      When call do_skip
      The status should equal 1
    End
  End

  Describe "on-main flag"
    setup_release_on_main() {
      export BRIK_RELEASE_TRIGGER_CONFIGURED="true"
      export BRIK_RELEASE_TRIGGER_ON_TAG="false"
      export BRIK_RELEASE_TRIGGER_ON_MAIN="true"
      export BRIK_RELEASE_TRIGGER_MANUAL="false"
    }
    Before 'setup_release_on_main'

    It "runs on push to main (default branch)"
      do_run() {
        export BRIK_COMMIT_BRANCH="main"
        gating.should_run_stage RELEASE
      }
      When call do_run
      The status should equal 0
    End

    It "runs on push to the configured default branch"
      do_run_master() {
        export BRIK_DEFAULT_BRANCH="master"
        export BRIK_COMMIT_BRANCH="master"
        gating.should_run_stage RELEASE
      }
      When call do_run_master
      The status should equal 0
    End

    It "skips on push to a non-main branch"
      do_skip() {
        export BRIK_COMMIT_BRANCH="feat/x"
        gating.should_run_stage RELEASE
      }
      When call do_skip
      The status should equal 1
    End
  End

  Describe "on-feature flag (package/deploy only)"
    setup_package_on_feature() {
      export BRIK_PACKAGE_TRIGGER_CONFIGURED="true"
      export BRIK_PACKAGE_TRIGGER_ON_TAG="false"
      export BRIK_PACKAGE_TRIGGER_ON_MAIN="false"
      export BRIK_PACKAGE_TRIGGER_ON_FEATURE="true"
      export BRIK_PACKAGE_TRIGGER_MANUAL="false"
    }
    Before 'setup_package_on_feature'

    It "runs on a feature branch"
      do_run() {
        export BRIK_COMMIT_BRANCH="feat/login"
        gating.should_run_stage PACKAGE
      }
      When call do_run
      The status should equal 0
    End

    It "skips on the default branch"
      do_skip() {
        export BRIK_COMMIT_BRANCH="main"
        gating.should_run_stage PACKAGE
      }
      When call do_skip
      The status should equal 1
    End

    It "skips when no branch context is available (no feature inference)"
      do_skip_no_branch() {
        gating.should_run_stage PACKAGE
      }
      When call do_skip_no_branch
      The status should equal 1
    End
  End

  Describe "manual flag"
    setup_release_manual() {
      export BRIK_RELEASE_TRIGGER_CONFIGURED="true"
      export BRIK_RELEASE_TRIGGER_ON_TAG="false"
      export BRIK_RELEASE_TRIGGER_ON_MAIN="false"
      export BRIK_RELEASE_TRIGGER_MANUAL="true"
    }
    Before 'setup_release_manual'

    It "runs when BRIK_TRIGGER_MANUAL=true"
      do_run() {
        export BRIK_TRIGGER_MANUAL="true"
        gating.should_run_stage RELEASE
      }
      When call do_run
      The status should equal 0
    End

    It "skips when BRIK_TRIGGER_MANUAL is empty"
      When call gating.should_run_stage RELEASE
      The status should equal 1
    End
  End

  Describe "OR semantics across multiple flags"
    setup_release_all() {
      export BRIK_RELEASE_TRIGGER_CONFIGURED="true"
      export BRIK_RELEASE_TRIGGER_ON_TAG="true"
      export BRIK_RELEASE_TRIGGER_ON_MAIN="true"
      export BRIK_RELEASE_TRIGGER_MANUAL="true"
    }
    Before 'setup_release_all'

    It "runs as soon as one flag matches the context (main)"
      do_run() {
        export BRIK_COMMIT_BRANCH="main"
        gating.should_run_stage RELEASE
      }
      When call do_run
      The status should equal 0
    End

    It "skips only when no flag matches the context"
      do_skip() {
        export BRIK_COMMIT_BRANCH="feat/x"
        gating.should_run_stage RELEASE
      }
      When call do_skip
      The status should equal 1
    End
  End

  Describe "input validation"
    It "rejects an empty prefix with rc=2"
      When call gating.should_run_stage ""
      The status should equal 2
      The stderr should include "prefix is required"
    End
  End
End
