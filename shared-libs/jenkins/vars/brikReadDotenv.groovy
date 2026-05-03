/**
 * brikReadDotenv - Parse a dotenv file into a Groovy Map.
 *
 * Reads KEY=VALUE lines, skips blank lines and # comments. Returns an
 * empty Map when the file does not exist; the caller decides how to react.
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
