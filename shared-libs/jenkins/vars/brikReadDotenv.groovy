/**
 * brikReadDotenv - Parse a dotenv file into a Groovy Map.
 *
 * Reads KEY=VALUE lines, skips blank lines and # comments. Returns an
 * empty Map when the file does not exist; the caller decides how to react.
 *
 * Usage:
 *   def initEnv = brikReadDotenv("${env.WORKSPACE}/.brik-logs/pipeline.env")
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
            def value = kv.size() > 1 ? kv[1] : ''
            // Strip a single layer of surrounding quotes. A stage that fails
            // to resolve a value can emit KEY='' (two literal quote chars);
            // without stripping, that reads back as the truthy string "''"
            // and downstream docker.image("''") aborts with "Name must
            // follow the pattern ...". Unwrapping yields the intended empty
            // string so callers' ?: fallbacks fire correctly.
            if (value.length() >= 2 &&
                ((value.startsWith("'") && value.endsWith("'")) ||
                 (value.startsWith('"') && value.endsWith('"')))) {
                value = value.substring(1, value.length() - 1)
            }
            result[kv[0]] = value
        }
    }
    return result
}
