/**
 * brikRunStage - Run a Brik stage inside a Docker container.
 *
 * Wraps the docker.image(image).inside(args) { brikStage(name, brikHome) }
 * pattern used by every per-stage helper in brikPipeline. Centralizes the
 * docker.inside() invocation so the helpers (runInBase, runStage,
 * runInAnalysis, runInScanner, runInDeploy) reduce to a one-line call.
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
    // Inject the actual execution image so report.write_fragment records
    // it as runner.image, instead of the stack-derived default computed
    // by config.export_runner_vars.
    def args  = "-e BRIK_RUNNER_IMAGE=${image} ${config.dockerArgs ?: ''}"
    docker.image(image).inside(args) { brikStage(name, home) }
}
