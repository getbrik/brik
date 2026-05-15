# Jenkins

The canonical reference for running Brik on Jenkins. For first-time setup see
[getting-started/jenkins.md](../getting-started/jenkins.md). For implementation
detail of the `vars/` wrappers see
[`shared-libs/jenkins/README.md`](../../shared-libs/jenkins/README.md).

## How it fits together

```
Jenkinsfile (2 lines)
  -> brikPipeline.groovy   (orchestrator: node {}, SCM checkout, fixed flow, Notify finally)
    -> brikStage.groovy    (stage executor)
      -> jenkins-wrapper.sh (Jenkins env -> BRIK_* normalization)
        -> portable stages  (lib/stages/*.sh via stage.run)
```

All stage logic lives in portable Bash. The Groovy layer only handles SCM
checkout, stash/unstash, `archiveArtifacts`, and the Notify `finally`
orchestration. `shared-libs/jenkins/vars/` defines six small variables:

| Var | Responsibility |
|-----|----------------|
| `brikPipeline` | Entry point. Declares `node {}`, runs SCM checkout, sets up helpers, runs the fixed flow plus Notify in `finally`. |
| `brikStage` | Sources `jenkins-wrapper.sh` and dispatches to a portable Bash stage via `brik.jenkins.run_stage`. |
| `brikRunStage` | Wraps `docker.image(image).inside(args) { brikStage(...) }` and injects `-e BRIK_RUNNER_IMAGE` so each fragment records its real execution image. |
| `brikResolveHome` | Locates the Brik shared library inside `${WORKSPACE}@libs/`. |
| `brikDockerArgs` | Builds the Docker run args (HOME redirection, JVM cache paths, memory cap, network attachment, `--env-file` for `NEXUS_` / `BRIK_` / `REGISTRY_` / `ARGOCD_` / `CARGO_` / `SSH_` vars). |
| `brikReadDotenv` | Parses `.brik-logs/pipeline.env` so the controller can extract `BRIK_CI_IMAGE`, mirroring GitLab's dotenv contract (single-file, projected from the report env section). |

`brikPipeline` exposes five per-image stage helpers -- `runInBase`, `runStage`,
`runInAnalysis`, `runInScanner`, `runInDeploy` -- all routed through
`brikRunStage`.

## Runner images

With `useDockerAgent: true` (the default), each stage runs inside a Docker
container. The Init stage reads `project.stack` and `project.stack_version` from
`brik.yml` to resolve the stack image:

| Stack | Resolved image |
|-------|----------------|
| node | `ghcr.io/getbrik/brik-runner-node:22` (or `:24`) |
| java | `ghcr.io/getbrik/brik-runner-java:21` (or `:25`) |
| python | `ghcr.io/getbrik/brik-runner-python:3.13` (or `:3.14`) |
| rust | `ghcr.io/getbrik/brik-runner-rust:1` |
| dotnet | `ghcr.io/getbrik/brik-runner-dotnet:9.0` (or `:10.0`) |

Specialized images, same as on GitLab:

| Image | Used by |
|-------|---------|
| `ghcr.io/getbrik/brik-runner-analysis:latest` | SAST |
| `ghcr.io/getbrik/brik-runner-scanner:latest` | Scan, Container Scan |
| `ghcr.io/getbrik/brik-runner-deploy:latest` | Deploy |

If `stack` is unset or unrecognized, no image is resolved and stages run
directly on the Jenkins agent (same as `useDockerAgent: false`).

## Parameters

`brikPipeline` accepts:

| Parameter | Default | Description |
|-----------|---------|-------------|
| `brikHome` | auto-detected | Path to the Brik shared library |
| `nodeLabel` | `''` (any) | Jenkins agent label |
| `timeoutMin` | `60` | Pipeline timeout in minutes |
| `useDockerAgent` | `true` | Run stages in `brik-runner` Docker containers |
| `dockerNetwork` | auto-detected | Docker network for runner containers |

```groovy
@Library('brik') _
brikPipeline(useDockerAgent: false)   // run on the agent instead of containers
```

### Job parameters (user-overridable inputs)

`brikPipeline.groovy` declares two job parameters via
`properties([parameters([...])])`:

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `BRIK_DRY_RUN` | `booleanParam` | `false` | Skip destructive deploy actions (compose up, k8s apply, helm upgrade, argocd sync, rsync). Print what would run instead. |
| `BRIK_TAG` | `stringParam` | `""` | Release tag for this build (e.g. `v0.1.0`). Leave empty for snapshot builds. Mirrors GitLab `CI_COMMIT_TAG`. |

**First-build gotcha**: Jenkins registers parameters declared via
`properties([parameters([...])])` only *after* the first build of a job
runs. On a freshly-created job the UI shows "Build Now" instead of
"Build with Parameters" -- one warm-up build is enough to surface the
form for subsequent runs. If you provision jobs through Job DSL
(Configuration-as-Code, seed job, `pipelineJob` script), redeclare the
same parameters on the job itself to make them visible from creation.

## Variable mapping

`jenkins-wrapper.sh` normalizes Jenkins environment variables to `BRIK_*`:

| Jenkins variable | Brik variable | Notes |
|------------------|---------------|-------|
| `GIT_BRANCH` | `BRIK_BRANCH` | `origin/` prefix stripped automatically |
| `TAG_NAME` | `BRIK_TAG` | |
| `GIT_COMMIT` | `BRIK_COMMIT_SHA` | |
| `GIT_COMMIT[0:7]` | `BRIK_COMMIT_SHORT_SHA` | |
| `BRIK_TAG` or `BRIK_BRANCH` | `BRIK_COMMIT_REF` | Tag takes priority |
| (default) | `BRIK_PIPELINE_SOURCE` | Always `push` |
| `CHANGE_ID` | `BRIK_MERGE_REQUEST_ID` | Multibranch PRs |
| `WORKSPACE` | `BRIK_PROJECT_DIR` | |

### BRIK_HOME

Jenkins clones Global Libraries into `${WORKSPACE}@libs/brik/`. The brik repo
contains both the runtime and the shared library, so that path is used directly
as `BRIK_HOME` -- no extra clone.

### Docker integration and caches

With `useDockerAgent: true`, `brikPipeline` runs Init on the agent to read
`brik.yml`, resolves the stack image, pulls it, and runs Build, Lint, Test, and
Package inside it; SAST, Scan, and Deploy use their specialized images. It
auto-detects the Docker network from the Jenkins container, mounts
`/var/run/docker.sock` for the Package stage, and sets `HOME=$WORKSPACE` so tool
caches (`npm`, `pip`, `Maven`, `Gradle`, `Cargo`, `NuGet`) persist in the
workspace across builds. The `cleanWs` step preserves those cache directories.

Environment variables matching `NEXUS_*`, `BRIK_*`, `REGISTRY_*`, or `ARGOCD_*`
are forwarded into the containers via an env file.

## Prerequisites

With Docker agents (default), the Jenkins **controller** needs Docker running
and access to `ghcr.io/getbrik/*` images (or a private mirror).

Without Docker agents (`useDockerAgent: false`), the **agent node** needs
`bash 4+`, `yq`, `jq`, `jv` (or `check-jsonschema` as a fallback), `git`, plus
the tools required by your stack and stages.

## See also

- [Getting started: Jenkins](../getting-started/jenkins.md) -- first-time setup
- [Configuration overview](../configuration/overview.md) -- `brik.yml`
- [Credentials](../operations/credentials.md) -- wiring secrets
- [Troubleshooting](../operations/troubleshooting.md) -- common failures
