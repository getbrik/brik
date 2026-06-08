/**
 * brikRunStage - Run a Brik stage inside a Docker container.
 *
 * Wraps `docker.image(image).inside(args) { brikStage(name, brikHome) }`
 * for the bootstrap helpers in brikIntegrate (runInBase, runInDeploy) and
 * the generic stage loop, which all resolve their image via
 * brikDriver.resolveImage. BRIK_RUNNER_IMAGE is injected so
 * report.write_fragment records the actual execution image rather than the
 * stack default computed by config.export_runner_vars.
 *
 * Usage:
 *   brikRunStage(image: 'ghcr.io/getbrik/brik-runner-base:latest',
 *                stageName: 'init',
 *                brikHome: brikHome,
 *                dockerArgs: dockerArgs)
 */
def call(Map config) {
    def image = config.image      ?: error('brikRunStage: image is required')
    def name  = config.stageName  ?: error('brikRunStage: stageName is required')
    def home  = config.brikHome   ?: error('brikRunStage: brikHome is required')
    // Forward BRIK_PLAN_FILE when set (D.5b of the architecture refactor
    // chantier). When an operator runs a single stage via `brik stage`
    // through the wrapper, the in-container brik picks up the plan and
    // honours the same skip semantics as the orchestrated path.
    def planEnv = env.BRIK_PLAN_FILE ? "-e BRIK_PLAN_FILE=${env.BRIK_PLAN_FILE} " : ''
    // Forward the runner-class registry override (mirror / air-gapped / e2e
    // stub fleet). A relative value is resolved against the brik library root
    // (home) -- the Jenkins shared lib is checked out at ${WORKSPACE}@libs/<hash>/,
    // so callers cannot hardcode an absolute path; absolute values pass through
    // unchanged. Empty param = bundled default registry.
    def rcFile = env.BRIK_RUNNER_CLASSES_FILE?.trim()
    def rcEnv = ''
    if (rcFile) {
        def resolved = rcFile.startsWith('/') ? rcFile : "${home}/${rcFile}"
        rcEnv = "-e BRIK_RUNNER_CLASSES_FILE=${resolved} "
    }
    def args = "-e BRIK_RUNNER_IMAGE=${image} ${planEnv}${rcEnv}${config.dockerArgs ?: ''}"
    docker.image(image).inside(args) { brikStage(name, home) }
}
