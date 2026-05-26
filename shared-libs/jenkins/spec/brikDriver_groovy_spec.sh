#shellcheck shell=bash
# Contract for shared-libs/jenkins/vars/brikDriver.groovy (Lot 4 of
# chantier 20260526_pipeline-invariants-centralization.md).
#
# brikDriver factors out the per-stage orchestration that used to live as
# imperative `runStageWithPlan('Foo', 'foo') {...}` calls in
# brikPipeline.groovy. It reads `brik registry stages --format json` at
# pipeline start to obtain the structural stage list, then exposes 4
# helpers consumed by the slim brikPipeline.groovy loop.

Describe "shared-libs/jenkins/vars/brikDriver.groovy - Lot 4 driver"
  DRIVER="${BRIK_HOME}/shared-libs/jenkins/vars/brikDriver.groovy"

  It "file exists"
    When run test -f "$DRIVER"
    The status should be success
  End

  Describe "declares the 4 helpers consumed by brikPipeline.groovy"
    Parameters
      "stagesList"
      "resolveImage"
      "planSaysRun"
      "parallelStages"
    End

    It "brikDriver declares the helper '$1'"
      When run grep -qE "def $1\\b" "$DRIVER"
      The status should be success
    End
  End

  Describe "stagesList consumes the brik CLI"
    It "stagesList invokes 'brik registry stages'"
      When run grep -qF "brik registry stages" "$DRIVER"
      The status should be success
    End
  End

  Describe "resolveImage uses the runner_classes contract"
    It "resolveImage references BRIK_IMG_ environment variables"
      When run grep -qE "BRIK_IMG_" "$DRIVER"
      The status should be success
    End

    It "resolveImage special-cases the 'stack' class (dynamic per-project)"
      When run grep -qE "stack" "$DRIVER"
      The status should be success
    End
  End

  Describe "planSaysRun invokes the plan-gate CLI"
    It "planSaysRun calls 'brik plan gate'"
      When run grep -qF "brik plan gate" "$DRIVER"
      The status should be success
    End
  End
End

Describe "shared-libs/jenkins/vars/brikPipeline.groovy - Lot 4 refactor"
  GROOVY="${BRIK_HOME}/shared-libs/jenkins/vars/brikPipeline.groovy"

  Describe "hardcoded runStageWithPlan calls have been removed"
    # Lot 4 replaces these imperative calls with a loop over brikDriver.
    Parameters
      "Release"
      "Build"
      "Package"
      "Container Scan"
      "Deploy"
    End

    It "brikPipeline.groovy no longer contains runStageWithPlan('$1', ..."
      When run grep -qF "runStageWithPlan('$1'" "$GROOVY"
      The status should be failure
    End
  End

  Describe "the driver is wired in"
    It "brikPipeline.groovy references brikDriver"
      When run grep -qF "brikDriver" "$GROOVY"
      The status should be success
    End
  End

  Describe "unstash list is no longer hardcoded as a literal array"
    It "no literal array of stage ids in the Notify finally block"
      # The pre-refactor block contained:
      #   ['init', 'release', 'build', 'lint', 'sast', 'scan',
      #    'test', 'package', 'container-scan', 'deploy'].each { s ->
      # which is replaced with a driver-derived iteration.
      When run grep -qF "'container-scan', 'deploy'].each" "$GROOVY"
      The status should be failure
    End
  End

  Describe "file size budget"
    # Pre-refactor: 518 lines. Post-refactor the file stays in the same
    # ballpark (~520) because Lot 4 only targets the per-stage block;
    # the setup/cleanup infrastructure (cleanWs rescue, credential
    # resolution, container-id resolution, deploy chown helper) is
    # Jenkins-specific and stays in place. The real Lot 4 win is
    # qualitative (no hardcoded stage list), enforced by the grep
    # asserts above. This budget catches an accidental ballooning of
    # the file without demanding an arbitrary reduction.
    It "brikPipeline.groovy stays within 600 lines"
      under_600() {
        local n
        n="$(wc -l < "$GROOVY" | tr -d ' ')"
        [[ "$n" -lt 600 ]]
      }
      When call under_600
      The status should be success
    End
  End
End
