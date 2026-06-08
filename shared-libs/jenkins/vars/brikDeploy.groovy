/**
 * brikDeploy - Explicit Brik CD run on Jenkins (mode 2).
 *
 * Usage in a Jenkinsfile dedicated to deployments:
 *   @Library('brik') _
 *   brikDeploy()
 *
 * This is the Jenkins analogue of
 * shared-libs/gitlab/templates/brik-deploy.yml. It is intentionally
 * separate from brikIntegrate (the event-driven CI flow): a CD run is NOT
 * the fixed CI flow, it is a single `brik deploy` invocation parameterized
 * by (version, environment). The verb resolves the version to a
 * digest-pinned image in the channel the environment accepts, enforces the
 * require_digest gate, resolves the deployment definition at the version's
 * git ref, and runs the deploy stage. All business logic stays in lib/;
 * this var only maps params -> `brik deploy` and archives the evidence.
 *
 * Parameters:
 *   brikHome      - Override path to the Brik shared library (default: auto)
 *   nodeLabel     - Jenkins agent label (default: empty = any agent)
 *   timeoutMin    - Pipeline timeout in minutes (default: 30)
 *   dockerNetwork - Docker network attached to the deploy container
 *
 * The job parameters (BRIK_DEPLOY_VERSION / BRIK_DEPLOY_ENVIRONMENT) mirror
 * lib/registry/pipeline-params.yml (single SoT) and the GitLab CD variables
 * 1:1 (spec/integration/adapter-parity/pipeline_params_parity_spec.sh).
 */
def call(Map params = [:]) {
    def label = params.nodeLabel ?: ''
    def timeoutMinutes = params.timeoutMin ?: 30

    node(label) {
        // Declare the CD inputs up-front: buildWithParameters rejects a
        // trigger carrying unknown parameters. BRIK_DRY_RUN mirrors the CI
        // surface (and the GitLab CD form) so a deploy can be rehearsed.
        properties([
            parameters([
                string(
                    name: 'BRIK_DEPLOY_VERSION',
                    defaultValue: '',
                    description: 'Artifact version to deploy (e.g. v1.2.3). Required.'
                ),
                string(
                    name: 'BRIK_DEPLOY_ENVIRONMENT',
                    defaultValue: '',
                    description: 'Target environment key from deploy.environments. Required.'
                ),
                booleanParam(
                    name: 'BRIK_DRY_RUN',
                    defaultValue: false,
                    description: 'Skip destructive deploy actions; print what would run instead.'
                )
            ])
        ])

        ansiColor('xterm') {
        timeout(time: timeoutMinutes, unit: 'MINUTES') {
            // Input validation of the entry params (not business logic): a CD
            // run is meaningless without both. GitLab suppresses the pipeline
            // via workflow:rules; Jenkins has no native suppression for an
            // explicit buildWithParameters, so fail fast with a clear message.
            def version = (env.BRIK_DEPLOY_VERSION ?: '').trim()
            def environment = (env.BRIK_DEPLOY_ENVIRONMENT ?: '').trim()
            if (!version || !environment) {
                error('[brik] brikDeploy requires both BRIK_DEPLOY_VERSION and BRIK_DEPLOY_ENVIRONMENT')
            }

            cleanWs()
            checkout scm

            def brikHome = params.brikHome ?: brikResolveHome()
            def deployImage = brikDriver.resolveImage('deploy', '')

            def args = brikDockerArgs(networkOverride: params.dockerNetwork)
            def deployDockerArgs = args.deployDockerArgs

            try {
                stage('Deploy') {
                    try {
                        docker.image(deployImage).inside(deployDockerArgs) {
                            // The deploy verb is platform-agnostic: it sets up
                            // the local runtime, resolves the digest in the
                            // channel, enforces require_digest, pins the ref on
                            // every target, and runs the deploy stage. Creds
                            // arrive via the --env-file in deployDockerArgs.
                            sh """
                                ${brikHome}/bin/brik deploy \\
                                  --version "${version}" \\
                                  --environment "${environment}" \\
                                  --workspace "\${WORKSPACE}"
                            """
                        }
                    } finally {
                        // The deploy container runs as root (-u 0:0), leaving
                        // root-owned .ssh/.kube in the workspace. Chown them
                        // back to the Jenkins uid via a throwaway container so
                        // the next cleanWs can remove them. Docker-out-of-docker:
                        // --volumes-from the Jenkins container so the helper
                        // sees the same /var/jenkins_home tree (see the same
                        // pattern in brikIntegrate.runInDeploy).
                        def jenkinsUid = sh(script: 'id -u', returnStdout: true).trim()
                        def jenkinsGid = sh(script: 'id -g', returnStdout: true).trim()
                        def deployHostContainer = sh(
                            script: 'docker ps --no-trunc --filter "label=com.docker.compose.service=jenkins" --format "{{.ID}}" | head -1',
                            returnStdout: true
                        ).trim()
                        if (deployHostContainer) {
                            sh """
                                docker run --rm -u 0:0 --volumes-from ${deployHostContainer} alpine:latest chown -R ${jenkinsUid}:${jenkinsGid} "\${WORKSPACE}" 2>/dev/null || true
                            """
                        }
                    }
                }
            } finally {
                // Archive the same evidence the CI flow does: the deploy
                // artifacts and the full log dir (plan.json + pipeline.env),
                // minus lock/context churn.
                archiveArtifacts artifacts: 'brik-artifacts/**/*,.brik-logs/**/*',
                                 excludes: '.brik-logs/*.lock,.brik-logs/context-*',
                                 allowEmptyArchive: true
                sh "rm -f '${args.envFile}' || true"
            }
        }
        }
    }
}
