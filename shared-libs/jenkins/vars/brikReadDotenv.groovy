/**
 * brikReadDotenv - Parse a dotenv file into a Groovy Map.
 *
 * Reads KEY=VALUE lines from a dotenv file and returns them as a Map.
 * Skips blank lines and comments (lines starting with '#'). Returns an
 * empty Map if the file does not exist (caller decides how to react).
 *
 * Used by brikPipeline to consume brik-init.env produced by stages.init
 * (lib/stages/init.sh:_write_dotenv). Same contract as GitLab's
 * artifacts.reports.dotenv mechanism: a single source of truth for
 * BRIK_CI_IMAGE and other downstream-job env vars.
 *
 * Usage:
 *   def initEnv = brikReadDotenv("${env.WORKSPACE}/brik-init.env")
 *   def image = initEnv['BRIK_CI_IMAGE'] ?: ''
 */
def call(String path) {
    if (!fileExists(path)) {
        return [:]
    }
    def result = [:]
    readFile(path).readLines().each { line ->
        def trimmed = line.trim()
        if (trimmed && !trimmed.startsWith('#') && trimmed.contains('=')) {
            def kv = trimmed.split('=', 2)
            result[kv[0]] = kv.size() > 1 ? kv[1] : ''
        }
    }
    return result
}
