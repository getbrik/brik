/**
 * brikPipeline - Orchestrate the Brik fixed CI/CD flow on Jenkins.
 *
 * Usage in Jenkinsfile:
 *   @Library('brik') _
 *   brikPipeline()
 *
 * Parameters:
 *   brikHome        - Override path to the Brik shared library (default: auto-detected)
 *   nodeLabel       - Jenkins agent label (default: empty = any agent)
 *   timeoutMin      - Pipeline timeout in minutes (default: 60)
 *   dockerNetwork   - Docker network attached to runner containers
 *                     (default: auto-detected from the Jenkins container)
 *
 * Fixed flow:
 *   Init -> Release -> Build -> Lint||SAST||Scan||Test -> Package
 *        -> Container Scan -> Deploy -> Notify
 *
 * All business logic lives in portable Bash stages (lib/stages/). This
 * Groovy file is a thin orchestrator: every stage runs inside a
 * brik-runner Docker image, with the master only handling SCM checkout,
 * stash/unstash, archiveArtifacts, and the Notify finally block.
 */
def call(Map params = [:]) {
    def label = params.nodeLabel ?: ''
    def timeoutMinutes = params.timeoutMin ?: 60

    node(label) {
        // Declare job parameters up-front: Jenkins's buildWithParameters API
        // rejects triggers carrying unknown parameters.
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
            // Rescue any root-owned files left over from a prior aborted
            // build before cleanWs runs. The deploy stage runs as root
            // (brik-runner-deploy lacks a uid-1000 user) and writes
            // .ssh/.kube into the workspace. The post-deploy chown at
            // the end of runInDeploy normally restores ownership, but
            // if the build crashed mid-deploy or the user aborted it,
            // those root-owned paths persist and the next cleanWs --
            // running as the jenkins uid -- cannot delete them, which
            // wedges the project until manual intervention. Chown the
            // entire workspace via a throwaway alpine container so the
            // next cleanWs always has permission to proceed.
            def rescueUid = sh(script: 'id -u', returnStdout: true).trim()
            def rescueGid = sh(script: 'id -g', returnStdout: true).trim()
            sh """
                docker run --rm -u 0:0 \
                    -v "\${WORKSPACE}:/ws" \
                    alpine:latest \
                    chown -R ${rescueUid}:${rescueGid} /ws 2>/dev/null \
                    || true
            """
            // Selective cleanup: drop build outputs and materialised dep
            // trees (node_modules, .venv, ...), keep tool-level caches
            // (.npm, .m2, .cache/pip, ...) so the install step on the
            // next build stays fast. Materialised installs are the output
            // of `npm ci` / `pip install` and must be regenerated when
            // their inputs change; keeping them across builds requires
            // every consumer to detect drift, which is a leaky contract.
            cleanWs(
                deleteDirs: true,
                patterns: [
                    [pattern: '.npm/**', type: 'EXCLUDE'],
                    [pattern: '.cache/**', type: 'EXCLUDE'],
                    [pattern: '.m2/**', type: 'EXCLUDE'],
                    [pattern: '.gradle/**', type: 'EXCLUDE'],
                    [pattern: '.cargo/**', type: 'EXCLUDE'],
                    [pattern: '.nuget/**', type: 'EXCLUDE'],
                    [pattern: '.git/**', type: 'EXCLUDE'],
                ]
            )
            def scmVars = checkout scm

            // Pick the most specific build cause (userId for manual trigger,
            // shortDescription for SCM/timer/upstream/remote triggers) and
            // expose it as BRIK_TRIGGERED_BY. _pipeline.detect_metadata
            // honors the pre-set value via set_if_unset.
            def triggeredBy = currentBuild.getBuildCauses().collect { c ->
                c.userId ?: c.shortDescription ?: ''
            }.findAll { it }.join(' / ')

            // Propagate SCM and trigger metadata via withEnv so they reach
            // the docker.image().inside() containers.
            def scmEnv = [
                "GIT_BRANCH=${scmVars.GIT_BRANCH ?: ''}",
                "GIT_COMMIT=${scmVars.GIT_COMMIT ?: ''}",
                "BRIK_TRIGGERED_BY=${triggeredBy}",
            ]

            withEnv(scmEnv) {

            def brikHome = params.brikHome ?: brikResolveHome()

            // Stage runner images. resolvedImage is filled after Init reads
            // brik-init.env and exposes BRIK_CI_IMAGE.
            def baseImage     = 'ghcr.io/getbrik/brik-runner-base:latest'
            def analysisImage = 'ghcr.io/getbrik/brik-runner-analysis:latest'
            def scannerImage  = 'ghcr.io/getbrik/brik-runner-scanner:latest'
            def deployImage   = 'ghcr.io/getbrik/brik-runner-deploy:latest'
            def resolvedImage = ''

            // Wrap each stage in try/catch so the stage view records the
            // failed stage even when an inner sh aborts the surrounding try.
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

            def args = brikDockerArgs(networkOverride: params.dockerNetwork)
            def dockerArgs       = args.dockerArgs
            def deployDockerArgs = args.deployDockerArgs
            def envFile          = args.envFile

            // Stash each stage's brik-artifacts/ subdirectory so the Notify
            // stage can unstash and aggregate them via report.aggregate_fragments.
            // The include glob is scoped to brik-artifacts/<stage>/** rather
            // than the full tree so concurrent verify branches (lint/sast/scan
            // /test share the same Jenkins workspace) cannot race on each
            // other's mktemp/mv atomic writes -- e.g. Lint's stash walking the
            // tree while Scan is mid-rename of scan.json.XXXXXX, which
            // surfaces as java.nio.file.NoSuchFileException in TarArchiver.
            // allowEmpty:true tolerates skipped or report-disabled stages.
            def stashBrikArtifacts = { name ->
                stash includes: "brik-artifacts/${name}/**",
                      name: "brik-artifacts-${name}",
                      allowEmpty: true
            }

            // Per-image stage helpers. Every stage runs in its dedicated
            // brik-runner image; the only variation is the image (and
            // deploy's root override + chown). runInBase covers init and
            // notify, both targeted at the same minimal Alpine image.
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
            // Deploy ran as root, so root-owned files (.ssh, .kube) end up
            // in the workspace. Chown them back to the Jenkins uid via a
            // throwaway alpine container so cleanWs can remove them next
            // build.
            def runInDeploy = { name ->
                try {
                    brikRunStage(image: deployImage, stageName: name,
                                 brikHome: brikHome, dockerArgs: deployDockerArgs)
                } finally {
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
                // Init produces brik-init.env in the workspace. brikReadDotenv
                // extracts BRIK_CI_IMAGE so subsequent stages run in the
                // stack-specific runner. Same contract as GitLab's
                // artifacts.reports.dotenv.
                runStageWithReporting('Init') { runInBase('init') }

                def initEnv = brikReadDotenv("${env.WORKSPACE}/brik-init.env")
                resolvedImage = initEnv['BRIK_CI_IMAGE'] ?: ''
                if (resolvedImage) {
                    docker.image(resolvedImage).pull()
                }

                // release: gate-at-platform on tag presence. Multibranch
                // sets env.TAG_NAME on tag-scan builds. Skipping at this
                // level avoids pulling the stack runner just to short-
                // circuit in stages.release.
                if (env.TAG_NAME?.trim()) {
                    runStageWithReporting('Release') { runStage('release') }
                }
                runStageWithReporting('Build')          { runStage('build') }
                runStageWithReporting('Verify') {
                    parallel(
                        'Lint': { runStage('lint') },
                        'SAST': { runInAnalysis('sast') },
                        'Scan': { runInScanner('scan') },
                        'Test': { runStage('test') }
                    )
                    // brik-artifacts/test/junit/**/*.xml covers the Java surefire/gradle layout;
                    // brik-artifacts/test/junit.xml covers node/python/dotnet.
                    junit testResults: 'brik-artifacts/test/junit.xml,brik-artifacts/test/junit/**/*.xml',
                          allowEmptyResults: true
                    // Surface SARIF findings in the Warnings NG dashboard
                    // (Jenkins free / community plugin). Wrapped in try/catch
                    // so instances without Warnings NG installed log a notice
                    // and continue; the SARIF files still ship as build
                    // artifacts via archiveArtifacts below.
                    //
                    // The aggregate.sarif (chantier 20260508 P6) merges every
                    // stage's findings.sarif into one document and is the
                    // preferred Warnings NG source. Per-stage entries stay as
                    // a fallback so the dashboard still surfaces findings on
                    // pipelines that ran before the notify stage produced the
                    // aggregate (e.g. early-fail builds).
                    try {
                        recordIssues(
                            enabledForFailure: true,
                            aggregatingResults: true,
                            tools: [
                                sarif(pattern: 'brik-artifacts/aggregate.sarif',
                                      id: 'brik-aggregate', name: 'Brik findings (aggregate)'),
                                sarif(pattern: 'brik-artifacts/sast/sast.sarif',
                                      id: 'brik-sast',   name: 'SAST (semgrep)'),
                                sarif(pattern: 'brik-artifacts/scan/deps.sarif',
                                      id: 'brik-deps',   name: 'Dependencies (osv-scanner)'),
                                sarif(pattern: 'brik-artifacts/scan/secret.sarif',
                                      id: 'brik-secret', name: 'Secrets (gitleaks)')
                            ]
                        )
                    } catch (Exception e) {
                        echo "[brik] recordIssues skipped (Warnings NG plugin unavailable): ${e.message}"
                    }
                }
                runStageWithReporting('Package')        { runStage('package') }
                runStageWithReporting('Container Scan') { runInScanner('container-scan') }
                runStageWithReporting('Deploy') {
                    sh 'mkdir -p "${WORKSPACE}/.kube" && cp /opt/brik/kubeconfig "${WORKSPACE}/.kube/config" 2>/dev/null || true'
                    runInDeploy('deploy')
                }
            } finally {
                // Notify always runs, even on upstream failure. Inner
                // try/catch prevents a webhook hiccup from flipping a
                // SUCCESS into a FAILURE.
                stage('Notify') {
                    try {
                        ['init', 'release', 'build', 'lint', 'sast', 'scan',
                         'test', 'package', 'container-scan', 'deploy'].each { s ->
                            try {
                                unstash "brik-artifacts-${s}"
                            } catch (Exception ue) {
                                echo "[brik] no stash for ${s} (likely skipped)"
                            }
                        }
                        runInBase('notify')
                        archiveArtifacts artifacts: 'brik-artifacts/**/*',
                            allowEmptyArchive: true,
                            fingerprint: false
                    } catch (Exception e) {
                        echo "[brik] stage Notify failed: ${e.message}"
                    }
                }
                sh """rm -f '${envFile}' 2>/dev/null || true"""
            }

            } // withEnv(scmEnv)
        }
        }
    }
}
