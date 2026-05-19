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
        //
        // BRIK_TAG is the explicit "this build represents a tag trigger"
        // signal. Multibranch jobs set TAG_NAME automatically for tag-scan
        // builds, but pipelineJob-based projects (e.g. the briklab test
        // fixtures) always build the configured branch -- there's no native
        // way to say "act as if a tag was pushed". Passing BRIK_TAG via
        // buildWithParameters makes the trigger-side intent reach the
        // brik runtime (jenkins-wrapper exports BRIK_TAG -> stage.sh maps
        // it to BRIK_COMMIT_TAG -> context resolves to "release"). For
        // snapshot triggers, the harness omits the parameter or passes an
        // empty value, matching GitLab's CI_COMMIT_TAG semantics.
        properties([
            parameters([
                booleanParam(
                    name: 'BRIK_DRY_RUN',
                    defaultValue: false,
                    description: 'Skip destructive deploy actions (compose up, k8s apply, helm upgrade, argocd sync, rsync). Print what would run instead.'
                ),
                string(
                    name: 'BRIK_TAG',
                    defaultValue: '',
                    description: 'Release tag to associate with this build (e.g. v0.1.0). Leave empty for snapshot builds. Mirrors GitLab CI_COMMIT_TAG.'
                ),
                booleanParam(
                    name: 'BRIK_WITH_DEPLOY',
                    defaultValue: false,
                    description: 'Opt into the deploy stage. The planner skips deploy by default even on tag pushes; set to true to actually run it.'
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
            // Drop .ssh / .kube outright before chown: the deploy stage
            // leaves an ssh-agent unix domain socket under .ssh/agent/ that
            // Jenkins' cleanWs (Java File.delete) refuses to remove and wedges
            // the next build. These dirs only hold transient credentials
            // materialised at deploy time, so wiping them between builds is
            // safe.
            //
            // Mount caveat: Jenkins runs as a docker-out-of-docker container,
            // so a plain -v "${WORKSPACE}:/ws" asks the HOST daemon to bind a
            // path that only exists inside the Jenkins container -- the host
            // sees nothing and creates an empty dir, leaving the real
            // workspace untouched. Use --volumes-from on the Jenkins container
            // so the alpine helper sees the same /var/jenkins_home tree.
            //
            // Container id resolution: /proc/self/cgroup is "0::/" under
            // Docker Desktop's cgroup v2 unified hierarchy, so the legacy
            // cgroup parse no longer yields an id. Query the docker socket
            // for the container that matches our /etc/hostname (set by
            // docker-compose's hostname:). Returns empty if not found, in
            // which case the cleanup degrades to a best-effort no-op via
            // the `|| true` guards.
            //
            // Quoting note: each docker command goes on its own line --
            // Groovy's """...""" interpolation strips embedded single quotes,
            // so an alpine "sh -c '...'" wrapper would collapse to a single
            // bare token. Each line is one argv chain, no nested quoting.
            def jenkinsContainer = sh(
                script: 'docker ps --no-trunc --filter "label=com.docker.compose.service=jenkins" --format "{{.ID}}" | head -1',
                returnStdout: true
            ).trim()
            if (jenkinsContainer) {
                sh """
                    docker run --rm -u 0:0 --volumes-from ${jenkinsContainer} alpine:latest rm -rf "\${WORKSPACE}/.ssh" "\${WORKSPACE}/.kube" 2>/dev/null || true
                    docker run --rm -u 0:0 --volumes-from ${jenkinsContainer} alpine:latest chown -R ${rescueUid}:${rescueGid} "\${WORKSPACE}" 2>/dev/null || true
                """
            } else {
                echo "[brik] Jenkins container id unresolved; skipping privileged workspace rescue"
            }
            // Selective cleanup: drop build outputs and materialised dep
            // trees (node_modules, .venv, ...), keep tool-level caches
            // (.npm, .m2, .cache/pip, ...) so the install step on the
            // next build stays fast. Materialised installs are the output
            // of `npm ci` / `pip install` and must be regenerated when
            // their inputs change; keeping them across builds requires
            // every consumer to detect drift, which is a leaky contract.
            //
            // EXCLUDE patterns below mirror the top-level directories
            // emitted by lib/stacks/_deps.sh::stacks.cache_paths. The
            // master cannot source bash before cleanWs (the brik library
            // is resolved later by brikResolveHome), so the list is kept
            // inline. Drift against the canonical SoT is caught by
            // spec/integration/cache_paths_parity_spec.sh.
            // .git/** is excluded too (not part of stacks.cache_paths --
            // it's an unconditional protection for the SCM metadata).
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
            // .brik-logs/pipeline.env and exposes BRIK_CI_IMAGE.
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
                    // Same docker-out-of-docker + container-resolution caveats
                    // as the rescue at pipeline start: query the docker socket
                    // for the Jenkins container by its compose service label,
                    // then --volumes-from it so the alpine chown sees the
                    // same /var/jenkins_home tree.
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
                stashBrikArtifacts(name)
            }

            // Plan-driven gate helper (D.5b of the architecture refactor
            // chantier). Returns true when the stage should run, false when
            // the plan said skip. On skip, `brik plan gate` has already
            // recorded the per-stage fragment so the aggregate-report
            // surfaces the stage as a not-applicable skip with reason.
            // When BRIK_PLAN_FILE is unset (legacy pipelines), the gate
            // returns true and the stage runs as before.
            def planSaysRun = { stageId ->
                if (!env.BRIK_PLAN_FILE?.trim()) {
                    return true
                }
                def rc = sh(
                    script: "${brikHome}/bin/brik plan gate '${stageId}'",
                    returnStatus: true
                )
                return rc == 0
            }

            // Wrap a stage with the plan gate: the Jenkins stage block is
            // still created so the Stage View records "skipped" entries,
            // but the body only runs when the plan allows it. The fragment
            // is stashed in both branches so Notify's aggregator sees
            // either the run output or the skip marker written by
            // `brik plan gate`.
            def runStageWithPlan = { stageName, stageId, body ->
                runStageWithReporting(stageName) {
                    if (planSaysRun(stageId)) {
                        body()
                    } else {
                        echo "[brik] ${stageId}: skipped per plan (BRIK_PLAN_FILE=${env.BRIK_PLAN_FILE})"
                        stashBrikArtifacts(stageId)
                    }
                }
            }

            try {
                // Init publishes its env contract through report.record env;
                // the post-stage projection hook materialises it as
                // .brik-logs/pipeline.env in the workspace. brikReadDotenv
                // extracts BRIK_CI_IMAGE so subsequent stages run in the
                // stack-specific runner. Same single-file contract as GitLab's
                // artifacts.reports.dotenv (which reads the same path).
                runStageWithReporting('Init') { runInBase('init') }

                def initEnv = brikReadDotenv("${env.WORKSPACE}/.brik-logs/pipeline.env")
                resolvedImage = initEnv['BRIK_CI_IMAGE'] ?: ''
                if (resolvedImage) {
                    docker.image(resolvedImage).pull()
                }

                // Plan stage (D.5b). Produces .brik-logs/plan.json and
                // points the gate helpers at it via BRIK_PLAN_FILE. Runs
                // on the master without Docker because the planner only
                // needs jq/yq/git (already on the Jenkins agent). A
                // planner failure is non-fatal: we echo and fall back to
                // the legacy unconditional flow.
                runStageWithReporting('Plan') {
                    // Mirror gitlab/_plan.yml's flag resolution. The planner
                    // defaults gate release/package/deploy off; the wrapper
                    // is responsible for translating CI context into the
                    // matching --with-* flags:
                    //   - tag context (BRIK_TAG or TAG_NAME set) -> release+package
                    //   - BRIK_WITH_DEPLOY=true                  -> deploy
                    //   - BRIK_WITH_RELEASE/PACKAGE override for finer control.
                    def tagSet = (env.BRIK_TAG?.trim() || env.TAG_NAME?.trim()) as boolean
                    def planOpts = []
                    if (tagSet || env.BRIK_WITH_RELEASE == 'true') {
                        planOpts << '--with-release'
                    }
                    if (tagSet || env.BRIK_WITH_PACKAGE == 'true') {
                        planOpts << '--with-package'
                    }
                    if (env.BRIK_WITH_DEPLOY == 'true') {
                        planOpts << '--with-deploy'
                    }
                    // The planner derives context (release vs snapshot) from
                    // BRIK_COMMIT_TAG, with BRIK_TAG as a final fallback (see
                    // _pipeline.detect_metadata). On a Multibranch tag scan
                    // Jenkins sets TAG_NAME but not BRIK_TAG, so the planner
                    // would otherwise classify a tag build as snapshot and
                    // reject release with context-mismatch even when the
                    // opt-in flag matches. Bridge the two so the planner
                    // sees the same context the wrapper does.
                    if (env.TAG_NAME?.trim() && !env.BRIK_TAG?.trim()) {
                        env.BRIK_TAG = env.TAG_NAME
                    }
                    def planRc = sh(
                        script: "${brikHome}/bin/brik plan --out .brik-logs/plan.json ${planOpts.join(' ')}",
                        returnStatus: true
                    )
                    if (planRc == 0 && fileExists('.brik-logs/plan.json')) {
                        env.BRIK_PLAN_FILE = "${env.WORKSPACE}/.brik-logs/plan.json"
                        echo "[brik] plan written: ${env.BRIK_PLAN_FILE}"
                    } else {
                        echo "[brik] planner failed (rc=${planRc}); falling back to legacy flow"
                    }
                }

                // release: gate-at-platform on tag presence. Two routes:
                //   - Multibranch tag-scan: Jenkins sets env.TAG_NAME on
                //     the build automatically.
                //   - pipelineJob (briklab fixtures): the harness passes
                //     BRIK_TAG via buildWithParameters; Jenkins exposes
                //     parameters as env vars to subsequent steps but the
                //     `params` map is only populated after this build's
                //     `properties([parameters(...)])` block completes, so
                //     params.BRIK_TAG reads null on the first stage even
                //     when env.BRIK_TAG is already "v0.1.0". Check env
                //     directly to cover both routes.
                if (env.TAG_NAME?.trim() || env.BRIK_TAG?.trim()) {
                    runStageWithPlan('Release', 'release') { runStage('release') }
                }
                runStageWithPlan('Build', 'build')          { runStage('build') }
                runStageWithReporting('Verify') {
                    // Verify groups four checks; the gate applies per child
                    // so a docs-only commit can skip individual scanners
                    // without dropping the whole Verify stage.
                    parallel(
                        'Lint': { if (planSaysRun('lint')) { runStage('lint') }      else { echo "[brik] lint: skipped per plan";  stashBrikArtifacts('lint') } },
                        'SAST': { if (planSaysRun('sast')) { runInAnalysis('sast') } else { echo "[brik] sast: skipped per plan";  stashBrikArtifacts('sast') } },
                        'Scan': { if (planSaysRun('scan')) { runInScanner('scan') }  else { echo "[brik] scan: skipped per plan";  stashBrikArtifacts('scan') } },
                        'Test': { if (planSaysRun('test')) { runStage('test') }      else { echo "[brik] test: skipped per plan";  stashBrikArtifacts('test') } }
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
                runStageWithPlan('Package', 'package')              { runStage('package') }
                runStageWithPlan('Container Scan', 'container-scan') { runInScanner('container-scan') }
                runStageWithPlan('Deploy', 'deploy') {
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
                        try {
                            runInBase('notify')
                        } catch (Exception ne) {
                            // The notify stage doubles as the pipeline
                            // gatekeeper: it exits non-zero whenever the
                            // aggregate-report's business.status is
                            // "error" (a real product failure). Catch
                            // that here so the archiveArtifacts call
                            // below still runs -- without it, the
                            // brik-artifacts/aggregate-report.json that
                            // proves the failure is never published,
                            // which makes CI parity diffs against GitLab
                            // (where artifacts upload regardless of job
                            // exit code) impossible.
                            echo "[brik] notify stage signalled failure: ${ne.message}"
                            currentBuild.result = 'FAILURE'
                        }
                        archiveArtifacts artifacts: 'brik-artifacts/**/*,.brik-logs/**/*',
                            excludes: '.brik-logs/*.lock,.brik-logs/context-*',
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
