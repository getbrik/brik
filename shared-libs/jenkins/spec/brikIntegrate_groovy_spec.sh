Describe "shared-libs/jenkins brikIntegrate.groovy - artifact layout"
  GROOVY="${BRIK_HOME}/shared-libs/jenkins/vars/brikIntegrate.groovy"

  It "junit testResults pattern points at brik-artifacts/test/"
    When call grep -F "junit testResults: 'brik-artifacts/test/junit.xml,brik-artifacts/test/junit/**/*.xml'" "$GROOVY"
    The status should be success
    The output should be present
  End

  It "no longer ships an intermediate coverage/reports archiveArtifacts block"
    When call grep -F "'coverage/**,reports/**'" "$GROOVY"
    The status should not equal 0
  End

  It "archives both brik-artifacts and .brik-logs in the final block"
    When call grep -F "archiveArtifacts artifacts: 'brik-artifacts/**/*,.brik-logs/**/*'" "$GROOVY"
    The status should be success
    The output should be present
  End

  It "excludes lock files and context-* churn from the .brik-logs archive"
    When call grep -F "excludes: '.brik-logs/*.lock,.brik-logs/context-*'" "$GROOVY"
    The status should be success
    The output should be present
  End

  Describe "Warnings NG SARIF surfacing"
    It "calls recordIssues to surface SARIF in the Warnings NG dashboard"
      When call grep -F "recordIssues(" "$GROOVY"
      The status should be success
      The output should be present
    End

    It "wires the sast SARIF tool"
      When call grep -F "brik-artifacts/sast/sast.sarif" "$GROOVY"
      The status should be success
      The output should be present
    End

    It "wires the deps SARIF tool"
      When call grep -F "brik-artifacts/scan/deps.sarif" "$GROOVY"
      The status should be success
      The output should be present
    End

    It "wraps recordIssues in try/catch so missing plugin does not break the build"
      When call grep -F "recordIssues skipped" "$GROOVY"
      The status should be success
      The output should be present
    End

    # When recordIssues was invoked in Verify with aggregate.sarif as a
    # pattern, the Warnings NG plugin logged `[-ERROR-] No files found
    # for pattern 'brik-artifacts/aggregate.sarif'` on every build (the
    # aggregate is produced later, by notify). The fix splits the calls:
    # per-stage SARIFs stay in Verify, the aggregate moves to the Notify
    # try-block where the file already exists.
    It "records the aggregate.sarif AFTER the notify invocation, not before"
      # Anchor on line numbers: every sarif(pattern: '..aggregate.sarif')
      # line must be located strictly below the runInBase('notify') call.
      # If aggregate.sarif still appeared in the Verify-side recordIssues
      # (which is before notify), this check would fail.
      check_aggregate_below_notify() {
        local notify_line aggregate_pattern_line
        notify_line=$(grep -n "runInBase('notify')" "$GROOVY" | head -1 | cut -d: -f1)
        aggregate_pattern_line=$(grep -n "pattern: 'brik-artifacts/aggregate.sarif'" "$GROOVY" | head -1 | cut -d: -f1)
        [[ -n "$notify_line" && -n "$aggregate_pattern_line" \
           && "$aggregate_pattern_line" -gt "$notify_line" ]]
      }
      When call check_aggregate_below_notify
      The status should be success
    End

    It "wraps the aggregate recordIssues in try/catch with a dedicated skip message"
      When call grep -F "recordIssues aggregate skipped" "$GROOVY"
      The status should be success
      The output should be present
    End
  End

  Describe "deterministic Notify unstash messages"
    It "no longer emits the speculative 'likely skipped' phrasing"
      When call grep -F "(likely skipped)" "$GROOVY"
      The status should not equal 0
    End

    It "reads plan.json via env.BRIK_PLAN_FILE in the Notify unstash catch block"
      When call grep -F "env.BRIK_PLAN_FILE" "$GROOVY"
      The status should be success
      The output should be present
    End

    It "emits a 'skipped per plan (reason=...)' message when the plan decided skip"
      When call grep -F "skipped per plan (reason=" "$GROOVY"
      The status should be success
      The output should be present
    End

    It "distinguishes 'plan=run but no artifact' from 'skipped per plan'"
      When call grep -F "no stash found despite plan=run" "$GROOVY"
      The status should be success
      The output should be present
    End

    It "still degrades gracefully when plan.json is unreadable"
      When call grep -F "plan decision unknown" "$GROOVY"
      The status should be success
      The output should be present
    End
  End

  # When notify fails (business.status = error), wfapi must report the
  # Notify stage as FAILED -- not SUCCESS -- so consumers reading the
  # stage statuses are consistent with the build result. catchError is
  # the idiomatic Pipeline construct that achieves this without aborting
  # the surrounding archiveArtifacts call.
  Describe "Notify stage marks itself FAILURE on notify failure"
    It "uses catchError around runInBase('notify') instead of a swallowing try/catch"
      When call grep -F "catchError(message: '[brik] notify stage signalled failure'" "$GROOVY"
      The status should be success
      The output should be present
    End

    It "propagates the failure to both stageResult and buildResult"
      When call grep -F "stageResult: 'FAILURE', buildResult: 'FAILURE'" "$GROOVY"
      The status should be success
      The output should be present
    End

    It "no longer mutates currentBuild.result manually around notify"
      # The legacy block set currentBuild.result = 'FAILURE' inside a
      # try/catch around runInBase('notify'). catchError handles both
      # results now, so the manual mutation should be gone.
      check_no_manual_mutation() {
        # Allow currentBuild.result elsewhere in the file but not on the
        # line immediately following 'notify stage signalled failure'.
        awk '
          /notify stage signalled failure/ { found=NR; window=NR+6 }
          found && NR > found && NR <= window && /currentBuild\.result *= *.FAILURE/ {
            print "leak at line " NR; bad=1
          }
          END { exit (bad ? 1 : 0) }
        ' "$GROOVY"
      }
      When call check_no_manual_mutation
      The status should equal 0
    End
  End

  # Image selection is uniform: every stage resolves its runner image from
  # runner_classes.yml via brikDriver.resolveImage (BRIK_IMG_<CLASS>, posted
  # by init's dotenv). brikIntegrate declares no image literal of its own --
  # the single accepted bootstrap literal lives in brikDriver.resolveImage's
  # fallback, used before init's dotenv exists.
  Describe "uniform image selection via the runner_classes registry"
    It "declares no hardcoded brik-runner image literal"
      When call grep -F "ghcr.io/getbrik/brik-runner" "$GROOVY"
      The status should not equal 0
    End

    It "resolves the base image via brikDriver.resolveImage"
      When call grep -F "brikDriver.resolveImage('base'" "$GROOVY"
      The status should be success
      The output should be present
    End

    It "resolves the deploy image via brikDriver.resolveImage"
      When call grep -F "brikDriver.resolveImage('deploy'" "$GROOVY"
      The status should be success
      The output should be present
    End

    It "no longer defines the unused runStage closure"
      When call grep -F "def runStage =" "$GROOVY"
      The status should not equal 0
    End

    It "no longer defines the unused runInAnalysis closure"
      When call grep -F "def runInAnalysis =" "$GROOVY"
      The status should not equal 0
    End

    It "no longer defines the unused runInScanner closure"
      When call grep -F "def runInScanner =" "$GROOVY"
      The status should not equal 0
    End
  End

  # Concurrent builds of the same branch/job race on the shared @libs cache
  # and on the workspace checkout. The CI flow must serialize them; the CD
  # flow lives in a separate job, so deploys are not serialized against CI.
  Describe "serializes concurrent builds of the same job"
    It "declares disableConcurrentBuilds in the job properties"
      When call grep -F "disableConcurrentBuilds()" "$GROOVY"
      The status should be success
      The output should be present
    End
  End

  Describe "scopes the signing credential to the container-scan container"
    It "runs container-scan with signingDockerArgs, the other stages with dockerArgs"
      When call grep -F "(sid == 'container-scan') ? signingDockerArgs : dockerArgs" "$GROOVY"
      The status should be success
      The output should be present
    End

    It "cleans up the signing env-file with the others"
      When call grep -F "rm -f '\${envFile}' '\${deployEnvFile}' '\${signingEnvFile}'" "$GROOVY"
      The status should be success
      The output should be present
    End
  End
End
