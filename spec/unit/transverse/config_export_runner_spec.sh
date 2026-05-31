#shellcheck shell=bash
# Contract for lib/transverse/config/exports/runner.sh::config.export_runner_vars.
#
# Resolution order (first match wins):
#   1. an explicit BRIK_RUNNER_IMAGE already in the environment (Jenkins
#      injects the per-stage image via -e BRIK_RUNNER_IMAGE)
#   2. CI_JOB_IMAGE (GitLab exposes the resolved job image there) -- this is
#      what keeps the stage banner and report fragment showing the image the
#      stage ACTUALLY runs in (e.g. a stub image under a
#      BRIK_RUNNER_CLASSES_FILE override), not the project's stack default
#   3. stack + version via runner.resolve_image
#   4. base runner image fallback

Describe "config.export_runner_vars - runner image coherence"
  Include "$BRIK_HOME/lib/transverse/config.sh"

  cleanup_runner_env() {
    unset BRIK_RUNNER_IMAGE CI_JOB_IMAGE BRIK_BUILD_STACK BRIK_BUILD_STACK_VERSION
  }
  Before 'cleanup_runner_env'
  After  'cleanup_runner_env'

  It "respects a pre-set BRIK_RUNNER_IMAGE (Jenkins injection) over everything"
    export BRIK_RUNNER_IMAGE="injected/image:tag"
    export CI_JOB_IMAGE="ignored:job"
    export BRIK_BUILD_STACK="node"
    export BRIK_BUILD_STACK_VERSION="22"
    When call config.export_runner_vars
    The status should be success
    The variable BRIK_RUNNER_IMAGE should equal "injected/image:tag"
  End

  It "prefers CI_JOB_IMAGE over the stack default (GitLab coherence)"
    # The fix for the banner/report incoherence: the stage must report the
    # image it actually runs in, not node:22, when GitLab resolved a
    # different job image (e.g. a stub under BRIK_RUNNER_CLASSES_FILE).
    export CI_JOB_IMAGE="brik-runner-stub:spike"
    export BRIK_BUILD_STACK="node"
    export BRIK_BUILD_STACK_VERSION="22"
    When call config.export_runner_vars
    The status should be success
    The variable BRIK_RUNNER_IMAGE should equal "brik-runner-stub:spike"
  End

  It "falls back to stack resolution when neither override is set"
    export BRIK_BUILD_STACK="node"
    export BRIK_BUILD_STACK_VERSION="22"
    When call config.export_runner_vars
    The status should be success
    The variable BRIK_RUNNER_IMAGE should equal "ghcr.io/getbrik/brik-runner-node:22"
  End

  It "falls back to the base image when stack is auto"
    export BRIK_BUILD_STACK="auto"
    When call config.export_runner_vars
    The status should be success
    The variable BRIK_RUNNER_IMAGE should equal "ghcr.io/getbrik/brik-runner-base:latest"
  End
End
