/**
 * brikPipeline - Orchestrates the Brik fixed CI/CD flow on Jenkins.
 *
 * Usage in Jenkinsfile:
 *   @Library('brik') _
 *   brikPipeline()
 *
 * Parameters:
 *   brikHome    - Override path to Brik shared library (default: auto-detected)
 *   nodeLabel   - Jenkins agent label to run on (default: empty = any agent)
 *   timeoutMin  - Pipeline timeout in minutes (default: 60)
 *
 * The fixed flow:
 *   Init -> Release -> Build -> Quality || Security -> Test -> Package -> Deploy -> Notify
 *
 * All business logic lives in portable Bash stages (runtime/bash/lib/stages/).
 * This Groovy file is a thin orchestrator only.
 */
def call(Map params = [:]) {
    def label = params.nodeLabel ?: ''
    def timeoutMinutes = params.timeoutMin ?: 60

    node(label) {
        timeout(time: timeoutMinutes, unit: 'MINUTES') {
            checkout scm

            // Jenkins clones Global Libraries into ${WORKSPACE}@libs/<hash>/
            // Discover the repo root by finding the directory with runtime/
            def brikHome = params.brikHome ?: sh(
                script: '''#!/bin/bash
                    libs_dir="${WORKSPACE}@libs"
                    if [ -d "$libs_dir" ]; then
                        for d in "$libs_dir"/*/; do
                            if [ -d "${d}runtime" ]; then
                                printf '%s' "${d%/}"
                                exit 0
                            fi
                        done
                    fi
                    printf '%s' "${libs_dir}/brik"
                ''',
                returnStdout: true
            ).trim()

            try {
                stage('Init')    { brikStage('init', brikHome) }
                stage('Release') { brikStage('release', brikHome) }
                stage('Build')   { brikStage('build', brikHome) }
                stage('Quality & Security') {
                    parallel(
                        'Quality': { brikStage('quality', brikHome) },
                        'Security': { brikStage('security', brikHome) }
                    )
                }
                stage('Test')    { brikStage('test', brikHome) }
                stage('Package') { brikStage('package', brikHome) }
                stage('Deploy')  { brikStage('deploy', brikHome) }
            } finally {
                stage('Notify') { brikStage('notify', brikHome) }
            }
        }
    }
}
