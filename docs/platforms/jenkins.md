# Jenkins

The canonical reference for running Brik on Jenkins. For first-time setup see
[getting-started/jenkins.md](../getting-started/jenkins.md). For implementation
detail of the `vars/` wrappers see
[`shared-libs/jenkins/README.md`](../../shared-libs/jenkins/README.md).

## How it fits together

```
Jenkinsfile (2 lines)
  -> brikIntegrate.groovy   (orchestrator: node {}, SCM checkout, fixed flow, Notify finally)
    -> brikStage.groovy    (stage executor)
      -> jenkins-wrapper.sh (Jenkins env -> BRIK_* normalization)
        -> portable stages  (lib/stages/*.sh via stage.run)
```

The fixed flow is:

```
Init -> Plan -> Release -> Build -> Lint||SAST||Scan||Test -> Package
     -> Container Scan -> Deploy -> Notify
```

All stage logic lives in portable Bash. The Groovy layer only handles SCM
checkout, stash/unstash, `archiveArtifacts`, and the Notify `finally`
orchestration. `shared-libs/jenkins/vars/` defines six small variables:

| Var | Responsibility |
|-----|----------------|
| `brikIntegrate` | Entry point. Declares `node {}`, runs SCM checkout, sets up helpers, runs the fixed flow plus Notify in `finally`. |
| `brikStage` | Sources `jenkins-wrapper.sh` and dispatches to a portable Bash stage via `brik.jenkins.run_stage`. |
| `brikRunStage` | Wraps `docker.image(image).inside(args) { brikStage(...) }` and injects `-e BRIK_RUNNER_IMAGE` so each fragment records its real execution image. |
| `brikResolveHome` | Locates the Brik shared library inside `${WORKSPACE}@libs/`. |
| `brikDockerArgs` | Builds the Docker run args (HOME redirection, JVM cache paths, memory cap, network attachment, `--env-file` for `NEXUS_` / `BRIK_` / `REGISTRY_` / `ARGOCD_` / `CARGO_` / `SSH_` vars). |
| `brikReadDotenv` | Parses `.brik-logs/pipeline.env` so the controller can extract `BRIK_CI_IMAGE`, mirroring GitLab's dotenv contract (single-file, projected from the report env section). |

`brikIntegrate` exposes five per-image stage helpers -- `runInBase`, `runStage`,
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

Specialized images, same as on GitLab (resolved from the runner-class
registry and read by `brikDriver.resolveImage`):

| Image | Used by |
|-------|---------|
| `ghcr.io/getbrik/brik-runner-analysis:latest` | SAST |
| `ghcr.io/getbrik/brik-runner-scanner:latest` | Scan, Container Scan |
| `ghcr.io/getbrik/brik-runner-deploy:latest` | Deploy |

To override every image at once (mirror / private registry), pass
`BRIK_RUNNER_CLASSES_FILE` as a build parameter; a path relative to the
brik library root is resolved to absolute before it reaches the stage
containers. See [runner-classes.md](../registry/runner-classes.md).

If `stack` is unset or unrecognized, no image is resolved and stages run
directly on the Jenkins agent (same as `useDockerAgent: false`).

## Stage selection

After Init, `brikIntegrate` runs a **Plan** stage. The planner runs on the
agent (it only needs `jq`/`yq`/`git`) and writes `.brik-logs/plan.json`,
pointed at via the `BRIK_PLAN_FILE` env var. Every subsequent stage is
plan-driven: the `runStageWithPlan` helper still creates the Jenkins stage
block -- so the Stage View records skipped entries -- but the stage body
only runs when `brik plan gate <stage>` (the `planSaysRun` check) returns
zero. On a skip, the gate records a not-applicable fragment so the
aggregate report explains why the stage did not run.

The planner gates Release, Package, and Deploy off by default. `brikIntegrate`
translates CI context into the matching opt-in flags: a tag context
(`BRIK_TAG` or `TAG_NAME` set) enables `--with-release` and `--with-package`,
and the `BRIK_WITH_DEPLOY` job parameter enables `--with-deploy`. If the
planner fails, the pipeline echoes a notice and falls back to the legacy
unconditional flow (`BRIK_PLAN_FILE` unset means every gate returns true).

## Parameters

`brikIntegrate` accepts:

| Parameter | Default | Description |
|-----------|---------|-------------|
| `brikHome` | auto-detected | Path to the Brik shared library |
| `nodeLabel` | `''` (any) | Jenkins agent label |
| `timeoutMin` | `60` | Pipeline timeout in minutes |
| `useDockerAgent` | `true` | Run stages in `brik-runner` Docker containers |
| `dockerNetwork` | auto-detected | Docker network for runner containers |

There is no parameter for the infrastructure referential: mount it at
`/etc/brik/infra` in the Jenkins controller container, and the shared
library discovers the host source of that mount and forwards it read-only
into every stage container (brik validates it eagerly at init).

```groovy
@Library('brik') _
brikIntegrate(useDockerAgent: false)   // run on the agent instead of containers
```

### Job parameters (user-overridable inputs)

`brikIntegrate.groovy` declares three job parameters via
`properties([parameters([...])])`:

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `BRIK_DRY_RUN` | `booleanParam` | `false` | Skip destructive deploy actions (compose up, k8s apply, helm upgrade, argocd sync, rsync). Print what would run instead. |
| `BRIK_TAG` | `stringParam` | `""` | Release tag for this build (e.g. `v0.1.0`). Leave empty for snapshot builds. Mirrors GitLab `CI_COMMIT_TAG`. |
| `BRIK_WITH_DEPLOY` | `booleanParam` | `false` | Opt into the deploy stage. The planner skips deploy by default even on tag pushes; set to true to actually run it. |

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
| `TAG_NAME` | `BRIK_TAG` | Precedence: a pre-existing `BRIK_TAG` env var (e.g. set via `buildWithParameters`) wins, then `TAG_NAME`, then `git describe --tags --exact-match` on true tag-scan builds. |
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

With `useDockerAgent: true`, `brikIntegrate` runs Init on the agent to read
`brik.yml`, resolves the stack image, pulls it, and runs Build, Lint, Test, and
Package inside it. Init and Notify run in the base image; SAST runs in the
analysis image; Scan and Container Scan run in the scanner image; Deploy runs
in the deploy image. It
auto-detects the Docker network from the Jenkins container, mounts
`/var/run/docker.sock` for the Package stage, and sets `HOME=$WORKSPACE` so tool
caches (`npm`, `pip`, `Maven`, `Gradle`, `Cargo`, `NuGet`) persist in the
workspace across builds. The `cleanWs` step preserves those cache directories.

Environment variables matching `NEXUS_*`, `BRIK_*`, `REGISTRY_*`, `ARGOCD_*`,
`CARGO_*`, or `SSH_*` are forwarded into the containers via an env file.

### Signing credential isolation

The shared library writes three per-phase env-files (CI stages, the deploy
stage, the signing stage) and mounts the signing one -- the `BRIK_SIGNING_*`
and `COSIGN_*` variables -- only on the `container-scan` container, where the
attestations are signed.

Caveat for an isolation claim: `docker.inside()` re-injects the whole build
environment as trailing `-e` flags on every stage container, which beat any
`--env-file` on the run line. A signing secret declared as a controller
global (JCasC `globalNodeProperties`) therefore reaches every container,
env-files or not. To actually isolate it, deliver the secret per stage --
for example bind it with `withCredentials` around the signing work in a
custom pipeline -- and never as a build global.

The registry write identity follows the same model: signing attaches the
attestation referrers to the digest (a registry write), so declare
`BRIK_SIGNING_REGISTRY_USER`/`_PASSWORD` and the shared library remaps them
onto the standard `BRIK_REGISTRY_*` names for the container-scan stage only
(at the `withEnv` level, where the plugin reads its `-e` values), while
every other container keeps the read-only registry account. See
[credentials.md](../operations/credentials.md) and
[artifact-attestation.md](../concepts/artifact-attestation.md).

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
