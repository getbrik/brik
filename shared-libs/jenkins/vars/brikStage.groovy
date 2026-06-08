/**
 * brikStage - Executes a single Brik stage via the Jenkins wrapper.
 *
 * Usage:
 *   brikStage('build', brikHome)
 *
 * Sources jenkins-wrapper.sh, runs setup, then dispatches to the
 * portable stage logic via brik.jenkins.run_stage. Maps the bash exit
 * code into Jenkins outcomes:
 *   - 0    : success
 *   - else : error() so the surrounding try/catch in brikIntegrate marks
 *            the build FAILURE. The stage's business outcome
 *            (success / warning / error) is reported separately via
 *            aggregate-report.json; warnings do not fail the job.
 */
def call(String stageName, String brikHome) {
    // Stage name validation removed in Lot 4 of chantier 20260526: the
    // registry is the single source of truth for stage ids, and
    // brik.jenkins.run_stage validates against it natively. A duplicated
    // hardcoded list here was the exact drift pattern the chantier
    // closes (it had omitted promote, surfacing as the trigger bug).

    def rc
    withEnv(["BRIK_HOME=${brikHome}", "BRIK_STAGE_NAME=${stageName}"]) {
        rc = sh(
            returnStatus: true,
            script: '''#!/bin/bash
                . "${BRIK_HOME}/shared-libs/jenkins/scripts/jenkins-wrapper.sh"
                brik.jenkins.setup "${BRIK_HOME}" || exit $?
                brik.jenkins.run_stage "${BRIK_STAGE_NAME}"
            '''
        )
    }

    if (rc != 0) {
        error("Stage ${stageName} failed with exit code ${rc}")
    }
}
