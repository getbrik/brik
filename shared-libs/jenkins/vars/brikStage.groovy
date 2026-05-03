/**
 * brikStage - Executes a single Brik stage via the Jenkins wrapper.
 *
 * Usage:
 *   brikStage('build', brikHome)
 *
 * Sources jenkins-wrapper.sh, runs setup, then dispatches to the
 * portable stage logic via brik.jenkins.run_stage. Maps the bash exit
 * code into Jenkins outcomes:
 *   - 0  : success
 *   - 99 : stage.skip_with_warning. Marks the stage UNSTABLE in the
 *          stage view and sets currentBuild.result = 'UNSTABLE'.
 *   - else: error() so the surrounding try/catch in brikPipeline marks
 *          the build FAILURE.
 */
def call(String stageName, String brikHome) {
    def validStages = ['init', 'release', 'build', 'lint', 'sast', 'scan', 'test', 'package', 'container-scan', 'deploy', 'notify']
    if (!validStages.contains(stageName)) {
        error("brikStage: unknown stage '${stageName}'. Valid: ${validStages.join(', ')}")
    }

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

    if (rc == 99) {
        unstable("Stage ${stageName} skipped with warning (user disabled outside release)")
    } else if (rc != 0) {
        error("Stage ${stageName} failed with exit code ${rc}")
    }
}
