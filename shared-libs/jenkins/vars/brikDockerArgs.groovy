/**
 * brikDockerArgs - Build the docker.image().inside() argument strings.
 *
 * Returns a Map:
 *   - dockerArgs       : args used by every regular stage container
 *   - deployDockerArgs : same as dockerArgs plus `-u 0:0` so the deploy
 *                        container runs as root (brik-runner-deploy lacks
 *                        a uid-1000 user, ssh/helm/argocd CLI rely on
 *                        getpwuid)
 *   - envFile          : path of the temporary env-file created for
 *                        --env-file, returned so the caller can clean it up
 *
 * The args carry:
 *   - HOME=$WORKSPACE           redirect npm/pip/cargo/nuget caches into the workspace
 *   - MAVEN_OPTS / GRADLE_USER_HOME  same redirection for the JVM (which
 *                                    ignores HOME and reads /etc/passwd)
 *   - --memory=2g               cap container memory
 *   - -v /var/run/docker.sock   mount Docker socket for in-container builds
 *   - --network <id>            attach to Jenkins's own Docker network so
 *                               brik-runner containers reach Nexus/Gitea/
 *                               ArgoCD by hostname
 *   - --env-file <path>         propagate NEXUS_/BRIK_/REGISTRY_/ARGOCD_/
 *                               CARGO_/SSH_ env vars into the runner. Lives
 *                               under /tmp so secret scanners do not flag
 *                               ARGOCD_AUTH_TOKEN and friends in the
 *                               workspace
 *
 * Usage:
 *   def args = brikDockerArgs(networkOverride: params.dockerNetwork)
 *   docker.image(image).inside(args.dockerArgs)        { ... }
 *   docker.image(deployImage).inside(args.deployDockerArgs) { ... }
 *   // in finally:
 *   sh "rm -f '${args.envFile}' || true"
 */
def call(Map config = [:]) {
    def network = config.networkOverride ?: sh(
        script: '''CID=$(grep -oP 'containers/\\K[a-f0-9]+' /proc/self/mountinfo 2>/dev/null | head -1)
            [ -n "$CID" ] && docker inspect "$CID" --format '{{range .NetworkSettings.Networks}}{{.NetworkID}}{{end}}' 2>/dev/null | head -1 || echo ''
        ''',
        returnStdout: true
    ).trim()
    def networkArg = network ? "--network ${network}" : ''

    // Discover the host source path of /etc/brik/policy mounted into this
    // Jenkins container. Docker-in-Docker mounts use host paths, so we
    // cannot just forward /etc/brik/policy from inside the container; the
    // nested runner container would try to bind a path that does not exist
    // on the host. Inspect our own container to recover the original
    // source. When BRIK_POLICY_URL is unset or the file is not mounted,
    // policyArg stays empty and the runtime falls back to the built-in
    // policy presets (pragmatic/strict/permissive).
    def policyHost = sh(
        script: '''CID=$(grep -oP 'containers/\\K[a-f0-9]+' /proc/self/mountinfo 2>/dev/null | head -1)
            [ -n "$CID" ] && docker inspect "$CID" --format '{{range .Mounts}}{{if eq .Destination "/etc/brik/policy"}}{{.Source}}{{end}}{{end}}' 2>/dev/null | head -1 || echo ''
        ''',
        returnStdout: true
    ).trim()
    def policyArg = policyHost ? "-v ${policyHost}:/etc/brik/policy:ro" : ''

    // BRIK_RUNNER_CLASSES_FILE is excluded from the env-file: brikRunStage
    // forwards it explicitly as `-e BRIK_RUNNER_CLASSES_FILE=<absolute>`
    // (a relative param value resolved against brikHome). The env-file is
    // appended AFTER that -e on the docker run line, and Docker lets the
    // rightmost source win -- so leaving the raw (relative) param value in
    // the env-file would clobber the resolved absolute path. Inside the
    // stage container the CWD is the workspace, not the @libs/<hash>
    // checkout, so the relative path would not resolve and the registry
    // override would silently fall back to the bundled default. Drop it
    // here and let the explicit -e be the single source.
    def envFile = "/tmp/brik-env-${env.BUILD_TAG}"
    sh """env | grep -E '^(NEXUS_|BRIK_|REGISTRY_|ARGOCD_|CARGO_|SSH_)' | grep -v '^BRIK_RUNNER_CLASSES_FILE=' > '${envFile}' 2>/dev/null || true"""
    def envFileArg = fileExists(envFile) && readFile(envFile).trim() ? "--env-file ${envFile}" : ''

    def javaEnvArgs = "-e MAVEN_OPTS=\"-Dmaven.repo.local=${env.WORKSPACE}/.m2/repository\" -e GRADLE_USER_HOME=${env.WORKSPACE}/.gradle"
    def dockerArgs = "-e HOME=${env.WORKSPACE} ${javaEnvArgs} --memory=4g -v /var/run/docker.sock:/var/run/docker.sock ${networkArg} ${envFileArg} ${policyArg}"

    return [
        dockerArgs:       dockerArgs,
        deployDockerArgs: "-u 0:0 ${dockerArgs}",
        envFile:          envFile,
    ]
}
