/**
 * brikPipeline - Orchestrates the Brik fixed CI/CD flow on Jenkins.
 *
 * Usage in Jenkinsfile:
 *   @Library('brik') _
 *   brikPipeline()
 *
 * Parameters:
 *   brikHome        - Override path to Brik shared library (default: auto-detected)
 *   nodeLabel       - Jenkins agent label to run on (default: empty = any agent)
 *   timeoutMin      - Pipeline timeout in minutes (default: 60)
 *   useDockerAgent  - Run stages in resolved brik-runner Docker container (default: true)
 *   dockerNetwork   - Docker network for runner containers (default: auto-detected from Jenkins container)
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
    def useDocker = params.useDockerAgent != null ? params.useDockerAgent : true

    node(label) {
        ansiColor('xterm') {
        timeout(time: timeoutMinutes, unit: 'MINUTES') {
            cleanWs()
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

            // Resolve runner image after init when Docker agent mode is enabled
            def resolvedImage = ''

            try {
                // Init stage always runs on the Jenkins agent (needs brik.yml)
                stage('Init') { brikStage('init', brikHome) }

                if (useDocker) {
                    resolvedImage = sh(
                        script: """#!/bin/bash
                            . "${brikHome}/runtime/bash/lib/runtime/runner-images.sh"
                            STACK=\$(yq '.project.stack // "auto"' brik.yml 2>/dev/null || echo "auto")
                            VERSION=\$(yq '.project.stack_version // ""' brik.yml 2>/dev/null || echo "")
                            runner.resolve_image "\$STACK" "\$VERSION" 2>/dev/null || echo ""
                        """,
                        returnStdout: true
                    ).trim()

                    if (resolvedImage) {
                        docker.image(resolvedImage).pull()
                    }
                }

                // Helper closure: run stage in Docker container or directly
                def dockerNetwork = params.dockerNetwork ?: sh(
                    script: 'docker inspect $(hostname) --format "{{range .NetworkSettings.Networks}}{{.NetworkID}}{{end}}" 2>/dev/null | head -1',
                    returnStdout: true
                ).trim()
                def networkArg = dockerNetwork ? "--network ${dockerNetwork}" : ''
                def dockerArgs = "-e HOME=${env.WORKSPACE} --memory=2g -v /var/run/docker.sock:/var/run/docker.sock ${networkArg}"
                def runStage = { name ->
                    if (useDocker && resolvedImage) {
                        docker.image(resolvedImage).inside(dockerArgs) { brikStage(name, brikHome) }
                    } else {
                        brikStage(name, brikHome)
                    }
                }

                stage('Release') { runStage('release') }
                stage('Build')   { runStage('build') }
                stage('Quality & Security') {
                    parallel(
                        'Quality': { runStage('quality') },
                        'Security': { runStage('security') }
                    )
                }
                stage('Test')    { runStage('test') }
                stage('Package') { runStage('package') }
                stage('Deploy')  { runStage('deploy') }
            } finally {
                stage('Notify') { brikStage('notify', brikHome) }
            }
        }
        }
    }
}
