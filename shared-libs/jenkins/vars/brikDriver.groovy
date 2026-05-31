/**
 * brikDriver - Generic stage iterator for brikPipeline.groovy.
 *
 * Replaces the 130-line block of hardcoded `runStageWithPlan('Foo', 'foo')
 * { runStage('foo') }` calls in brikPipeline.groovy with a single loop
 * driven by `brik registry stages --format json`. The same registry data
 * is consumed by the GitLab adapter (via the static jobs/*.yml templates
 * verified by the parity specs); Jenkins reads it dynamically at pipeline
 * start so adding a stage in the registry propagates automatically.
 *
 * Lot 4 of docs/chantiers/20260526_pipeline-invariants-centralization.md.
 *
 * Public helpers:
 *   stagesList(brikHome)             returns List<Map> from `brik registry stages`
 *   resolveImage(runnerClass, fallbackStackImage)
 *                                    maps runner_class -> OCI image, using
 *                                    BRIK_IMG_<CLASS> env vars posted by init
 *   planSaysRun(stageId, brikHome)   returns true unless plan.json marks skip
 *   parallelStages(stages, brikHome, dockerArgs, runStashClosure)
 *                                    builds the Map<String,Closure> consumed
 *                                    by Jenkins' parallel{} step
 */

def stagesList(brikHome) {
    // Parse via jq + TSV to avoid the readJSON step (provided by the
    // Pipeline Utility Steps plugin, which the briklab Jenkins instance
    // does not ship). jq emits one TSV row per stage; we split into a
    // List<Map> in Groovy. needs[] is encoded with ':' separator inside
    // its field since needs values are bare ids (no colons possible).
    def tsv = sh(returnStdout: true, script: """
        ${brikHome}/bin/brik registry stages --format json | jq -r '
            .[] | [.id, .display_name, .runner_class, .parallel_group, (.needs | join(":"))] | @tsv
        '
    """).trim()
    def stages = []
    if (!tsv) {
        return stages
    }
    tsv.split('\n').each { line ->
        def cols = line.split('\t', -1)
        stages << [
            id:             cols[0],
            display_name:   cols[1],
            runner_class:   cols[2],
            parallel_group: cols[3],
            needs:          (cols.length > 4 && cols[4]) ? cols[4].split(':').toList() : []
        ]
    }
    return stages
}

def resolveImage(runnerClass, fallbackStackImage = '') {
    // A value is usable only if it is non-blank AND not a leftover quoted
    // empty ('' or ""). init emits KEY='' when a class fails to resolve;
    // brikReadDotenv now unwraps those quotes, but a value sourced directly
    // from env (set before that unwrap, or by another producer) can still
    // carry them. Treating them as blank keeps a malformed dotenv from
    // reaching docker.image("''"), which aborts with "Name must follow the
    // pattern ...".
    def usable = { v ->
        if (!v?.trim()) { return false }
        def t = v.trim()
        return !(t == "''" || t == '""')
    }
    // The 'stack' class is dynamic per project: init's _resolve_runner_image
    // computes it and exports BRIK_IMG_STACK (and the legacy BRIK_CI_IMAGE).
    // The fallback parameter is the value resolved at pipeline init time
    // (brikReadDotenv extracts it from .brik-logs/pipeline.env) for callers
    // that prefer not to round-trip through env on every call.
    if (runnerClass == 'stack') {
        if (usable(fallbackStackImage)) {
            return fallbackStackImage.trim()
        }
        def stackEnv = usable(env.BRIK_IMG_STACK) ? env.BRIK_IMG_STACK : env.BRIK_CI_IMAGE
        if (usable(stackEnv)) {
            return stackEnv.trim()
        }
        return 'ghcr.io/getbrik/brik-runner-base:latest'
    }
    // Static classes: BRIK_IMG_BASE / ANALYSIS / SCANNER / DEPLOY, all
    // posted by init's dotenv contract (Lot 3 of the same chantier).
    def envVar = "BRIK_IMG_${runnerClass.toUpperCase()}"
    def value = env[envVar]
    if (usable(value)) {
        return value.trim()
    }
    // Safe fallback so pipelines on legacy fixtures (no init dotenv) still
    // resolve to something runnable instead of an empty string.
    return "ghcr.io/getbrik/brik-runner-${runnerClass}:latest"
}

def planSaysRun(stageId, brikHome) {
    if (!env.BRIK_PLAN_FILE?.trim()) {
        return true
    }
    // BRIK_WORKSPACE must be set so the gate's report.write_fragment lands
    // in the job workspace (not /tmp/brik/logs/). Without it the SKIP
    // fragment was orphaned, the stash was empty, and the Notify aggregate
    // missed the stage. GitLab side sets these too in pipeline.yml's
    // /tmp/brik-plan-gate.sh helper -- this is the Jenkins-side equivalent.
    def rc = sh(
        script: "BRIK_WORKSPACE='${env.WORKSPACE}' " +
                "BRIK_LOG_DIR='${env.WORKSPACE}/.brik-logs' " +
                "${brikHome}/bin/brik plan gate '${stageId}'",
        returnStatus: true
    )
    return rc == 0
}

/**
 * Build the Map<String,Closure> consumed by Jenkins' parallel{} step
 * from a list of stages belonging to the same parallel_group.
 *
 * Each closure consults the plan via planSaysRun: skipped stages echo
 * a [SKIP] line and still call runStashClosure so the Notify aggregator
 * unstash loop stays uniform.
 */
def parallelStages(stages, brikHome, dockerArgs, runStashClosure) {
    def branches = [:]
    stages.each { s ->
        def display = s.display_name
        def stageId = s.id
        def runnerClass = s.runner_class
        branches[(display)] = {
            if (planSaysRun(stageId, brikHome)) {
                def image = resolveImage(runnerClass, env.BRIK_CI_IMAGE)
                brikRunStage(image: image, stageName: stageId,
                             brikHome: brikHome, dockerArgs: dockerArgs)
            } else {
                echo "[brik] [SKIP] ${stageId}: per plan"
            }
            runStashClosure(stageId)
        }
    }
    return branches
}
