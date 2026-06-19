/**
 * brikIntegrate - Orchestrate the Brik fixed CI/CD flow on Jenkins.
 *
 * Usage in Jenkinsfile:
 *   @Library('brik') _
 *   brikIntegrate()
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
                ),
                string(
                    name: 'BRIK_RUNNER_CLASSES_FILE',
                    defaultValue: '',
                    description: 'Override the runner-class image registry (lib/registry/runner_classes.yml). Absolute path, or a path relative to the brik library root (resolved per stage container). Used for mirrors, air-gapped registries, or an e2e stub image fleet. Empty = bundled default.'
                ),
                // CD inputs (mode 2): set both to run an explicit deploy
                // (planType=deploy). Declared in lib/registry/pipeline-params.yml
                // (single SoT) and mirrored 1:1 by the GitLab BRIK_DEPLOY_* variables.
                string(
                    name: 'BRIK_DEPLOY_VERSION',
                    defaultValue: '',
                    description: 'Artifact version to deploy (e.g. v1.2.3). Set together with BRIK_DEPLOY_ENVIRONMENT to trigger an explicit CD run.'
                ),
                string(
                    name: 'BRIK_DEPLOY_ENVIRONMENT',
                    defaultValue: '',
                    description: 'Target environment key from deploy.environments. Set together with BRIK_DEPLOY_VERSION to trigger an explicit CD run.'
                )
            ]),
            // Serialize builds of the same job: concurrent builds of one branch
            // race on the shared @libs cache and on the workspace checkout,
            // which can corrupt the runtime clone. The CD flow is a separate
            // job, so this never serializes deploys against integrations.
            disableConcurrentBuilds()
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

            // Normalize BRIK_RUNNER_CLASSES_FILE to an absolute path in the
            // Jenkins env itself. The build parameter is supplied relative to
            // the brik library root (callers cannot hardcode the
            // ${WORKSPACE}@libs/<hash> path), but Jenkins promotes the raw
            // parameter into env, and docker.image().inside() injects that env
            // into EVERY stage container. Inside a container the CWD is the
            // workspace, not the @libs checkout, so a relative value fails to
            // resolve (registry.runner_class.image returns IO_FAILURE and the
            // override silently degrades to the default image). Resolving it
            // here against brikHome makes the absolute path the single value
            // every container inherits, independent of brikRunStage's per-call
            // -e forwarding. An absolute value (or empty) passes through.
            if (env.BRIK_RUNNER_CLASSES_FILE?.trim() &&
                !env.BRIK_RUNNER_CLASSES_FILE.startsWith('/')) {
                env.BRIK_RUNNER_CLASSES_FILE = "${brikHome}/${env.BRIK_RUNNER_CLASSES_FILE}"
            }

            // Stage runner images are resolved uniformly from
            // runner_classes.yml via brikDriver.resolveImage (BRIK_IMG_<CLASS>,
            // posted by Init's dotenv); brikIntegrate holds no image literal of
            // its own. resolvedImage carries the stack image once Init reads
            // .brik-logs/pipeline.env and exposes BRIK_CI_IMAGE, and is passed
            // to resolveImage as the stack fallback.
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
            def dockerArgs        = args.dockerArgs
            def deployDockerArgs  = args.deployDockerArgs
            // container-scan signs the attestations, so it alone receives the
            // signing env-file (BRIK_SIGNING_/COSIGN_) on top of the CI args.
            def signingDockerArgs = args.signingDockerArgs
            def envFile           = args.envFile
            def deployEnvFile     = args.deployEnvFile
            def signingEnvFile    = args.signingEnvFile

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

            // Per-image stage helpers. runInBase covers the bootstrap stages
            // init and notify (the 'base' class): resolveImage('base') returns
            // BRIK_IMG_BASE once Init's dotenv exists, and falls back to the
            // base bootstrap literal for Init itself (which runs first, before
            // any dotenv). Every other stage resolves its image inline via
            // brikDriver.resolveImage in the generic loop below.
            def runInBase = { name ->
                brikRunStage(image: brikDriver.resolveImage('base', ''), stageName: name,
                             brikHome: brikHome, dockerArgs: dockerArgs)
                stashBrikArtifacts(name)
            }
            // Deploy ran as root, so root-owned files (.ssh, .kube) end up
            // in the workspace. Chown them back to the Jenkins uid via a
            // throwaway alpine container so cleanWs can remove them next
            // build.
            def runInDeploy = { name ->
                try {
                    brikRunStage(image: brikDriver.resolveImage('deploy', ''), stageName: name,
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
                // BRIK_WORKSPACE must be exported so the gate's SKIP
                // fragment lands in the job workspace (see same fix in
                // vars/brikDriver.groovy::planSaysRun for the loop path).
                def rc = sh(
                    script: "BRIK_WORKSPACE='${env.WORKSPACE}' " +
                            "BRIK_LOG_DIR='${env.WORKSPACE}/.brik-logs' " +
                            "${brikHome}/bin/brik plan gate '${stageId}'",
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
                        // Plain "[SKIP]" tag: matches render.status format
                        // (color omitted -- Groovy cannot call render.status).
                        echo "[brik] [SKIP] ${stageId}: per plan (BRIK_PLAN_FILE=${env.BRIK_PLAN_FILE})"
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
                // No explicit docker.image().pull(): the briklab Docker
                // daemon is seeded by scripts/lib/setup/sync-brik-images.sh
                // and the subsequent docker.image().inside() reuses the
                // local cache. The previous unconditional pull failed
                // every offline build on a transient ghcr.io issue even
                // though the image was cached locally.

                // Propagate init's dotenv into Jenkins env so brikDriver
                // helpers (resolveImage) can substitute ${BRIK_IMG_<CLASS>}
                // without re-reading the file. GitLab gets this for free
                // via artifacts.reports.dotenv; Jenkins needs the explicit
                // bridge because dotenv is not a Jenkins-native concept.
                ['BRIK_CI_IMAGE',
                 'BRIK_IMG_STACK',
                 'BRIK_IMG_BASE',
                 'BRIK_IMG_ANALYSIS',
                 'BRIK_IMG_SCANNER',
                 'BRIK_IMG_DEPLOY'].each { k ->
                    if (initEnv[k]) {
                        env[k] = initEnv[k]
                    }
                }

                // Plan stage (D.5b). Produces .brik-logs/plan.json and
                // points the gate helpers at it via BRIK_PLAN_FILE.
                runStageWithReporting('Plan') {
                    def tagSet = (env.BRIK_TAG?.trim() || env.TAG_NAME?.trim()) as boolean
                    def planOpts = []
                    if (tagSet || env.BRIK_WITH_RELEASE == 'true') { planOpts << '--with-release' }
                    if (tagSet || env.BRIK_WITH_PACKAGE == 'true') { planOpts << '--with-package' }
                    if (env.BRIK_WITH_DEPLOY  == 'true')           { planOpts << '--with-deploy' }
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

                // Generic stage iteration driven by `brik registry stages`
                // (Lot 4 of chantier 20260526). The driver returns the
                // 12 stages of the fixed flow in topological order with
                // their runner_class, parallel_group, and needs. We
                // iterate, batching consecutive stages of the same
                // parallel_group (currently only 'verify': lint/sast/scan/test)
                // into a single parallel{} block. init, plan, and notify
                // are handled out-of-band (init/plan already ran above;
                // notify is in the finally block below). Stage-specific
                // pre-work that does NOT fit the generic loop -- the
                // verify post-block (junit + recordIssues), the deploy
                // kubeconfig prep -- is dispatched inline by id.
                def stages = brikDriver.stagesList(brikHome)
                def stashCallback = { sid -> stashBrikArtifacts(sid) }
                def i = 0
                while (i < stages.size()) {
                    def s = stages[i]
                    def sid = s.id

                    if (sid in ['init', 'notify']) { i++; continue }

                    // release runs only when a tag triggered the build.
                    if (sid == 'release' && !(env.TAG_NAME?.trim() || env.BRIK_TAG?.trim())) {
                        i++; continue
                    }

                    // Parallel group: collect all consecutive stages of the
                    // same group and run them in a parallel{} block, with a
                    // single Jenkins stage() wrapper named after the group.
                    if (s.parallel_group && i + 1 < stages.size() && stages[i + 1].parallel_group == s.parallel_group) {
                        def groupName = s.parallel_group
                        def group = []
                        while (i < stages.size() && stages[i].parallel_group == groupName) {
                            group << stages[i]
                            i++
                        }
                        runStageWithReporting(groupName.capitalize()) {
                            parallel(brikDriver.parallelStages(group, brikHome, dockerArgs, stashCallback))
                            // verify post-block: junit + Warnings NG SARIF surfacing.
                            // These hang off the verify group only; other parallel
                            // groups (if any are added later) won't have this.
                            if (groupName == 'verify') {
                                junit testResults: 'brik-artifacts/test/junit.xml,brik-artifacts/test/junit/**/*.xml',
                                      allowEmptyResults: true
                                try {
                                    recordIssues(
                                        enabledForFailure: true,
                                        aggregatingResults: true,
                                        tools: [
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
                        }
                        continue
                    }

                    // Single sequential stage.
                    runStageWithPlan(s.display_name, sid) {
                        if (sid == 'deploy') {
                            // Deploy needs the kubeconfig in the workspace
                            // (mounted into the deploy runner image at /root/.kube).
                            sh 'mkdir -p "${WORKSPACE}/.kube" && cp /opt/brik/kubeconfig "${WORKSPACE}/.kube/config" 2>/dev/null || true'
                            runInDeploy(sid)
                        } else {
                            def image = brikDriver.resolveImage(s.runner_class, resolvedImage)
                            if (sid == 'container-scan') {
                                // docker.inside() re-injects the whole build
                                // env as trailing -e flags, which beat any
                                // --env-file on the run line: when the write
                                // identity comes from a controller global,
                                // the remap must happen at the withEnv level
                                // to actually win. The env-file remap still
                                // covers values that are not build globals.
                                def signingEnv = []
                                if (env.BRIK_SIGNING_REGISTRY_USER) {
                                    signingEnv << "BRIK_REGISTRY_USER=${env.BRIK_SIGNING_REGISTRY_USER}"
                                }
                                if (env.BRIK_SIGNING_REGISTRY_PASSWORD) {
                                    signingEnv << "BRIK_REGISTRY_PASSWORD=${env.BRIK_SIGNING_REGISTRY_PASSWORD}"
                                }
                                withEnv(signingEnv) {
                                    brikRunStage(image: image, stageName: sid, brikHome: brikHome, dockerArgs: signingDockerArgs)
                                }
                            } else if (sid == 'package' || sid == 'promote') {
                                // package pushes the built image and promote retags
                                // it candidate->release: both write to the registry,
                                // so they need the WRITE identity. As with
                                // container-scan, the read-only BRIK_REGISTRY_USER
                                // casc global is re-injected by docker.inside() as a
                                // trailing -e that beats any --env-file, so the
                                // publish write identity must be remapped at the
                                // withEnv level to win. Build/test/CD containers keep
                                // the read-only brik-cd account.
                                def publishEnv = []
                                if (env.BRIK_PUBLISH_REGISTRY_USER) {
                                    publishEnv << "BRIK_REGISTRY_USER=${env.BRIK_PUBLISH_REGISTRY_USER}"
                                }
                                if (env.BRIK_PUBLISH_REGISTRY_PASSWORD) {
                                    publishEnv << "BRIK_REGISTRY_PASSWORD=${env.BRIK_PUBLISH_REGISTRY_PASSWORD}"
                                }
                                withEnv(publishEnv) {
                                    brikRunStage(image: image, stageName: sid, brikHome: brikHome, dockerArgs: dockerArgs)
                                }
                            } else {
                                brikRunStage(image: image, stageName: sid, brikHome: brikHome, dockerArgs: dockerArgs)
                            }
                        }
                        stashBrikArtifacts(sid)
                    }
                    i++
                }
            } finally {
                // Notify always runs, even on upstream failure. Inner
                // try/catch prevents a webhook hiccup from flipping a
                // SUCCESS into a FAILURE.
                stage('Notify') {
                    try {
                        // Consult plan.json to turn an unstash miss into a
                        // deterministic message: the planner has already
                        // decided run-vs-skip for each stage at the Plan
                        // step, so "likely" speculation is unwarranted.
                        // Returns [decision: run|skip|unknown, reason: ...].
                        def planDecisionForStage = { sid ->
                            if (!env.BRIK_PLAN_FILE || !fileExists(env.BRIK_PLAN_FILE)) {
                                return [decision: 'unknown', reason: 'no-plan-file']
                            }
                            def out = sh(
                                script: """jq -r --arg id '${sid}' '(.stages[]? | select(.id == \$id)) | "\\(.decision // "unknown")|\\(.reason // "")"' '${env.BRIK_PLAN_FILE}' 2>/dev/null || echo 'unknown|read-error'""",
                                returnStdout: true
                            ).trim()
                            if (!out) { return [decision: 'unknown', reason: 'not-in-plan'] }
                            def parts = out.split('\\|', 2)
                            return [decision: parts[0] ?: 'unknown',
                                    reason:   parts.length > 1 ? parts[1] : '']
                        }
                        // Unstash list derived from the registry (Lot 4 of
                        // chantier 20260526). Adding a stage to the
                        // registry now propagates here automatically; no
                        // more hardcoded list to forget like the original
                        // omission of promote that triggered the chantier.
                        // notify is excluded: it is THIS stage so no stash
                        // exists yet.
                        brikDriver.stagesList(brikHome).collect { it.id }
                            .findAll { it != 'notify' }
                            .each { s ->
                            try {
                                unstash "brik-artifacts-${s}"
                            } catch (Exception ue) {
                                def d = planDecisionForStage(s)
                                if (d.decision == 'skip') {
                                    echo "[brik] ${s}: skipped per plan (reason=${d.reason ?: 'unspecified'})"
                                } else if (d.decision == 'run') {
                                    echo "[brik] ${s}: no stash found despite plan=run (stage likely failed before producing artifacts)"
                                } else {
                                    echo "[brik] ${s}: no stash, plan decision unknown (${d.reason ?: 'unspecified'})"
                                }
                            }
                        }
                        // catchError lets the surrounding stage report
                        // FAILURE in wfapi (instead of swallowing the
                        // exception and showing SUCCESS for a stage that
                        // actually failed), while still letting the
                        // archiveArtifacts call below run. The notify
                        // stage doubles as the pipeline gatekeeper: it
                        // exits non-zero whenever the aggregate-report's
                        // business.status is "error" (a real product
                        // failure). Publishing the proof
                        // (aggregate-report.json) must survive that exit
                        // so CI parity diffs against GitLab (which
                        // always uploads artifacts regardless of job
                        // exit code) remain possible.
                        catchError(message: '[brik] notify stage signalled failure',
                                   stageResult: 'FAILURE', buildResult: 'FAILURE') {
                            runInBase('notify')
                        }
                        // aggregate.sarif now exists (notify writes it).
                        // Recording it here, rather than in Verify, avoids
                        // the misleading "[-ERROR-] No files found for
                        // pattern 'brik-artifacts/aggregate.sarif'" line
                        // that polluted every build before this split.
                        // On early-fail builds (notify never reached), the
                        // per-stage SARIFs already registered in Verify
                        // remain visible in the Warnings NG dashboard.
                        try {
                            recordIssues(
                                enabledForFailure: true,
                                aggregatingResults: false,
                                tools: [
                                    sarif(pattern: 'brik-artifacts/aggregate.sarif',
                                          id: 'brik-aggregate', name: 'Brik findings (aggregate)')
                                ]
                            )
                        } catch (Exception are) {
                            echo "[brik] recordIssues aggregate skipped (Warnings NG plugin unavailable): ${are.message}"
                        }
                        archiveArtifacts artifacts: 'brik-artifacts/**/*,.brik-logs/**/*',
                            excludes: '.brik-logs/*.lock,.brik-logs/context-*',
                            allowEmptyArchive: true,
                            fingerprint: false
                    } catch (Exception e) {
                        echo "[brik] stage Notify failed: ${e.message}"
                    }
                }
                sh """rm -f '${envFile}' '${deployEnvFile}' '${signingEnvFile}' 2>/dev/null || true"""
            }

            } // withEnv(scmEnv)
        }
        }
    }
}
