/**
 * brikStage - Executes a single Brik stage via the Jenkins wrapper.
 *
 * Usage:
 *   brikStage('build', brikHome)
 *
 * This sources the jenkins-wrapper.sh, runs setup, then dispatches
 * to the portable stage logic via brik.jenkins.run_stage.
 */
def call(String stageName, String brikHome) {
    def validStages = ['init', 'release', 'build', 'quality', 'security', 'test', 'package', 'deploy', 'notify']
    if (!validStages.contains(stageName)) {
        error("brikStage: unknown stage '${stageName}'. Valid: ${validStages.join(', ')}")
    }

    withEnv(["BRIK_HOME=${brikHome}", "BRIK_STAGE_NAME=${stageName}"]) {
        sh '''#!/bin/bash
            set -euo pipefail
            . "${BRIK_HOME}/shared-libs/jenkins/scripts/jenkins-wrapper.sh"
            brik.jenkins.setup "${BRIK_HOME}"
            brik.jenkins.run_stage "${BRIK_STAGE_NAME}"
        '''
    }
}
