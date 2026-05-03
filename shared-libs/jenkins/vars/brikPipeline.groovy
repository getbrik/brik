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
 *   dockerNetwork   - Docker network for runner containers (default: auto-detected from Jenkins container)
 *
 * The fixed flow:
 *   Init -> Release -> Build -> Lint||SAST||Scan||Test -> Package -> Container Scan -> Deploy -> Notify
 *
 * All business logic lives in portable Bash stages (lib/stages/).
 * This Groovy file is a thin orchestrator only.
 */
def call(Map params = [:]) {
    def label = params.nodeLabel ?: ''
    def timeoutMinutes = params.timeoutMin ?: 60

    node(label) {
        // Register job parameters that the shared library interprets.
        // Jenkins's buildWithParameters API rejects triggers carrying unknown
        // parameters, so these must be declared up-front for CI callers
        // (and E2E harnesses) to be able to pass them in.
        properties([
            parameters([
                booleanParam(
                    name: 'BRIK_DRY_RUN',
                    defaultValue: false,
                    description: 'Skip destructive deploy actions (compose up, k8s apply, helm upgrade, argocd sync, rsync). Print what would run instead.'
                )
            ])
        ])

        ansiColor('xterm') {
        timeout(time: timeoutMinutes, unit: 'MINUTES') {
            // Selective cleanup: remove build outputs but preserve dependency caches
            // for inter-build performance. checkout scm overwrites source files.
            cleanWs(
                deleteDirs: true,
                patterns: [
                    [pattern: '.npm/**', type: 'EXCLUDE'],
                    [pattern: '.cache/**', type: 'EXCLUDE'],
                    [pattern: '.m2/**', type: 'EXCLUDE'],
                    [pattern: '.gradle/**', type: 'EXCLUDE'],
                    [pattern: '.cargo/**', type: 'EXCLUDE'],
                    [pattern: '.nuget/**', type: 'EXCLUDE'],
                    [pattern: '.venv/**', type: 'EXCLUDE'],
                    [pattern: '.git/**', type: 'EXCLUDE'],
                    [pattern: 'node_modules/**', type: 'EXCLUDE'],
                ]
            )
            def scmVars = checkout scm

            // Capture SCM variables from checkout and propagate via withEnv
            // so they are available inside Docker containers (docker.image().inside())
            def scmEnv = [
                "GIT_BRANCH=${scmVars.GIT_BRANCH ?: ''}",
                "GIT_COMMIT=${scmVars.GIT_COMMIT ?: ''}",
            ]

            withEnv(scmEnv) {

            // Jenkins clones Global Libraries into ${WORKSPACE}@libs/<hash>/
            // Discover the repo root by finding the directory with runtime/
            def brikHome = params.brikHome ?: sh(
                script: '''#!/bin/bash
                    libs_dir="${WORKSPACE}@libs"
                    if [ -d "$libs_dir" ]; then
                        for d in "$libs_dir"/*/; do
                            if [ -d "${d}lib" ]; then
                                printf '%s' "${d%/}"
                                exit 0
                            fi
                        done
                    fi
                    printf '%s' "${libs_dir}/brik"
                ''',
                returnStdout: true
            ).trim()

            // Stage runner images. baseImage runs init; resolvedImage is
            // assigned after init from brik-init.env (BRIK_CI_IMAGE) and
            // covers stack-specific stages (build/lint/test/package/release/notify).
            def baseImage = 'ghcr.io/getbrik/brik-runner-base:latest'
            def resolvedImage = ''
            def analysisImage = 'ghcr.io/getbrik/brik-runner-analysis:latest'
            def scannerImage = 'ghcr.io/getbrik/brik-runner-scanner:latest'
            def deployImage = 'ghcr.io/getbrik/brik-runner-deploy:latest'

            // Helper: wrap a stage in try/catch so the stage view shows the
            // stage even when an earlier sh fails. Without this, an exception
            // thrown by `sh` aborts the surrounding try block and the stages
            // declared *after* the failure are never registered with the stage
            // engine -- the pipeline log would only show "Init" and "Notify"
            // even when Build/Verify/Deploy actually crashed.
            def runStageWithReporting = { stageName, body ->
                stage(stageName) {
                    try {
                        body()
                    } catch (Exception e) {
                        currentBuild.result = 'FAILURE'
                        echo "[brik] stage ${stageName} failed: ${e.message}"
                        throw e
                    }
                }
            }

            // Build dockerArgs first so all stage helpers (including
            // runInBase for init and notify) share the same Docker
            // invocation contract: workspace mount, env-file, network,
            // memory cap. Defined outside the try{} block so the Notify
            // stage in finally{} can also use runInBase.
            def dockerNetwork = params.dockerNetwork ?: sh(
                script: '''CID=$(grep -oP 'containers/\\K[a-f0-9]+' /proc/self/mountinfo 2>/dev/null | head -1)
                    [ -n "$CID" ] && docker inspect "$CID" --format '{{range .NetworkSettings.Networks}}{{.NetworkID}}{{end}}' 2>/dev/null | head -1 || echo ''
                ''',
                returnStdout: true
            ).trim()
            def networkArg = dockerNetwork ? "--network ${dockerNetwork}" : ''
            // Export global node env vars to a file so Docker containers
            // can access them via --env-file. The file lives outside the
            // workspace because it contains tokens (ARGOCD_AUTH_TOKEN,
            // ...) that secret scanners would otherwise flag.
            def envFile = "/tmp/brik-env-${env.BUILD_TAG}"
            sh """env | grep -E '^(NEXUS_|BRIK_|REGISTRY_|ARGOCD_|CARGO_|SSH_)' > '${envFile}' 2>/dev/null || true"""
            def globalEnvArgs = fileExists(envFile) && readFile(envFile).trim() ? "--env-file ${envFile}" : ''
            // HOME=$WORKSPACE redirects npm, pip, cargo, nuget caches into workspace.
            // Java needs explicit overrides: JVM user.home ignores $HOME (uses getpwuid).
            def javaEnvArgs = "-e MAVEN_OPTS=\"-Dmaven.repo.local=${env.WORKSPACE}/.m2/repository\" -e GRADLE_USER_HOME=${env.WORKSPACE}/.gradle"
            def dockerArgs = "-e HOME=${env.WORKSPACE} ${javaEnvArgs} --memory=2g -v /var/run/docker.sock:/var/run/docker.sock ${networkArg} ${globalEnvArgs}"
            // Deploy tools (ssh, rsync, helm, argocd CLI) read $HOME from
            // /etc/passwd via getpwuid. brik-runner-deploy has no uid-1000
            // user, so Jenkins's default "-u <jenkinsUid>:<gid>" launch
            // breaks ssh with "No user exists for uid 1000". Run the
            // deploy container as root to keep those tools happy.
            def deployDockerArgs = "-u 0:0 ${dockerArgs}"

            // Stash the per-stage report fragment produced by
            // report.write_fragment so the Notify stage can unstash all
            // fragments and aggregate them via report.aggregate_fragments.
            // allowEmpty:true keeps stages that did not emit a fragment
            // (e.g. BRIK_DISABLE_REPORT_FRAGMENTS=1 or skipped stage)
            // from breaking the pipeline.
            def stashBrikArtifacts = { name ->
                stash includes: 'brik-artifacts/**',
                      name: "brik-artifacts-${name}",
                      allowEmpty: true
            }

            // Per-image stage helpers. Every stage runs inside its
            // dedicated brik-runner image; the only variation is the
            // image (and deploy's root override + chown). runInBase
            // covers init and notify (both run in brik-runner-base, the
            // same minimal Alpine + bash + yq + jq + jv + curl image).
            def runInBase = { name ->
                brikRunStage(image: baseImage, stageName: name,
                             brikHome: brikHome, dockerArgs: dockerArgs)
                stashBrikArtifacts(name)
            }
            def runStage = { name ->
                brikRunStage(image: resolvedImage, stageName: name,
                             brikHome: brikHome, dockerArgs: dockerArgs)
                stashBrikArtifacts(name)
            }
            def runInAnalysis = { name ->
                brikRunStage(image: analysisImage, stageName: name,
                             brikHome: brikHome, dockerArgs: dockerArgs)
                stashBrikArtifacts(name)
            }
            def runInScanner = { name ->
                brikRunStage(image: scannerImage, stageName: name,
                             brikHome: brikHome, dockerArgs: dockerArgs)
                stashBrikArtifacts(name)
            }
            def runInDeploy = { name ->
                try {
                    brikRunStage(image: deployImage, stageName: name,
                                 brikHome: brikHome, dockerArgs: deployDockerArgs)
                } finally {
                    // The deploy container ran as root and may have
                    // created root-owned files in the workspace
                    // (.ssh/id_rsa, .kube/config). Jenkins (uid 1000)
                    // cannot cleanWs them on the next build. Chown
                    // back to the Jenkins uid using a one-shot root
                    // container.
                    def jenkinsUid = sh(script: 'id -u', returnStdout: true).trim()
                    def jenkinsGid = sh(script: 'id -g', returnStdout: true).trim()
                    sh """
                        docker run --rm -u 0:0 \
                            -v "\${WORKSPACE}:/ws" \
                            alpine:latest \
                            sh -c 'chown -R ${jenkinsUid}:${jenkinsGid} /ws/.ssh /ws/.kube 2>/dev/null || true' \
                            || true
                    """
                }
                stashBrikArtifacts(name)
            }

            try {
                // Init runs in brik-runner-base (same image as GitLab's
                // default). It writes brik-init.env in the workspace, which
                // we read back to resolve the stack-specific runner image
                // (BRIK_CI_IMAGE) for the rest of the pipeline. This mirrors
                // GitLab's artifacts.reports.dotenv contract and removes the
                // need for yq on the master.
                runStageWithReporting('Init') { runInBase('init') }

                def initEnv = brikReadDotenv("${env.WORKSPACE}/brik-init.env")
                resolvedImage = initEnv['BRIK_CI_IMAGE'] ?: ''
                if (resolvedImage) {
                    docker.image(resolvedImage).pull()
                }

                runStageWithReporting('Release')        { runStage('release') }
                runStageWithReporting('Build')          { runStage('build') }
                runStageWithReporting('Verify') {
                    parallel(
                        'Lint': { runStage('lint') },
                        'SAST': { runInAnalysis('sast') },
                        'Scan': { runInScanner('scan') },
                        'Test': { runStage('test') }
                    )
                    // Publish JUnit results and archive coverage/reports.
                    // The single-file path covers node/python/dotnet; the
                    // junit/**/*.xml glob covers the standardized java
                    // surefire/gradle output. allowEmptyResults stays true
                    // because reports.enabled is opt-in.
                    junit testResults: 'reports/junit.xml,reports/junit/**/*.xml',
                          allowEmptyResults: true
                    archiveArtifacts artifacts: 'coverage/**,reports/**',
                                     allowEmptyArchive: true,
                                     fingerprint: false
                }
                runStageWithReporting('Package')        { runStage('package') }
                runStageWithReporting('Container Scan') { runInScanner('container-scan') }
                runStageWithReporting('Deploy') {
                    // Copy kubeconfig to workspace for deploy containers (HOME=$WORKSPACE)
                    sh 'mkdir -p "${WORKSPACE}/.kube" && cp /opt/brik/kubeconfig "${WORKSPACE}/.kube/config" 2>/dev/null || true'
                    runInDeploy('deploy')
                }
            } finally {
                // Notify always runs, even on failure. Wrapped in try/catch
                // without rethrow so a notify channel hiccup (slack token,
                // webhook timeout) does not turn a SUCCESS into a FAILURE.
                stage('Notify') {
                    try {
                        // Unstash all per-stage fragments shipped by upstream
                        // stages so report.aggregate_fragments (called from
                        // stages.notify in CI mode) can merge them into the
                        // pipeline-report. Missing stashes are expected when
                        // a stage was skipped (e.g. release/package/deploy
                        // gated by tag rules) - swallow the exception.
                        ['init', 'release', 'build', 'lint', 'sast', 'scan',
                         'test', 'package', 'container-scan', 'deploy'].each { s ->
                            try {
                                unstash "brik-artifacts-${s}"
                            } catch (Exception ue) {
                                echo "[brik] no stash for ${s} (likely skipped)"
                            }
                        }
                        // Notify runs in brik-runner-base, same as init.
                        // The master no longer carries stack-specific tools
                        // so bootstrap.prepare_env on master would log
                        // [ERROR] when trying to apt-get install nodejs etc.
                        runInBase('notify')
                        archiveArtifacts artifacts: 'brik-artifacts/**/*',
                            allowEmptyArchive: true,
                            fingerprint: false
                    } catch (Exception e) {
                        echo "[brik] stage Notify failed: ${e.message}"
                    }
                }
                // Best-effort cleanup of the temporary env file so we do not
                // accumulate /tmp/brik-env-* across builds.
                sh """rm -f '/tmp/brik-env-${env.BUILD_TAG}' 2>/dev/null || true"""
            }

            } // withEnv(scmEnv)
        }
        }
    }
}
