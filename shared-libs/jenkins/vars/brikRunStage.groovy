/**
 * brikRunStage - Run a Brik stage inside a Docker container.
 *
 * Wraps `docker.image(image).inside(args) { brikStage(name, brikHome) }`
 * for the per-image helpers in brikPipeline (runInBase, runStage,
 * runInAnalysis, runInScanner, runInDeploy). BRIK_RUNNER_IMAGE is
 * injected so report.write_fragment records the actual execution image
 * rather than the stack default computed by config.export_runner_vars.
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
    def args  = "-e BRIK_RUNNER_IMAGE=${image} ${config.dockerArgs ?: ''}"
    docker.image(image).inside(args) { brikStage(name, home) }
}
