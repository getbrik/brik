# Brik Jenkins Shared Library

Jenkins integration for the Brik CI/CD pipeline system.

## Quick Start

1. Add Brik as a **trusted** Global Pipeline Library in Jenkins (via CasC or UI):

   ```yaml
   unclassified:
     globalLibraries:
       libraries:
         - name: "brik"
           defaultVersion: "main"
           retriever:
             modernSCM:
               scm:
                 git:
                   remote: "https://github.com/getbrik/brik.git"
   ```

2. Create a `Jenkinsfile` in your project:

   ```groovy
   @Library('brik') _
   brikPipeline()
   ```

3. Create a `brik.yml` in your project root (see [brik.yml spec](../../docs/specs/01-brik-yml.md)).

That's it. The fixed flow runs automatically.

## Fixed Flow

```
Init -> Release -> Build -> Lint||SAST||Scan||Test -> Package -> Container Scan -> Deploy -> Notify
```

- **Lint**, **SAST**, **Scan**, and **Test** run in **parallel** (Verify stage)
- **SAST** runs in `brik-runner-analysis` image (semgrep, checkov, scancode, license_finder)
- **Scan** and **Container Scan** run in `brik-runner-scanner` image (grype, syft, osv-scanner, gitleaks, trufflehog, hadolint, dockle)
- **Deploy** runs in `brik-runner-deploy` image (helm, kubectl, argocd, docker compose, ssh, rsync)
- **Notify** runs in a `finally` block (always executes)
- **Release** and **Package** are conditional (tag-based)
- All stage logic lives in portable Bash (no business logic in Groovy)

## Runner Images

By default (`useDockerAgent: true`), each stage runs inside a Docker container.
The Init stage reads `project.stack` and `project.stack_version` from `brik.yml`
to resolve the correct [brik-image](https://github.com/getbrik/brik-images).

### Stack images (Build, Lint, Test, Package)

The image is automatically resolved from `project.stack` and `project.stack_version` in `brik.yml`.

| Stack | Resolved image | Includes |
|-------|----------------|----------|
| node | `ghcr.io/getbrik/brik-runner-node:22` (or `:24`) | Node.js + npm + Brik prereqs |
| java | `ghcr.io/getbrik/brik-runner-java:21` (or `:25`) | JDK + Maven + Brik prereqs |
| python | `ghcr.io/getbrik/brik-runner-python:3.13` (or `:3.14`) | Python + pip + Brik prereqs |
| rust | `ghcr.io/getbrik/brik-runner-rust:1` | Rust + Cargo + Clippy + Rustfmt + Brik prereqs |
| dotnet | `ghcr.io/getbrik/brik-runner-dotnet:9.0` (or `:10.0`) | .NET SDK + Brik prereqs |

If `stack` is not set or not recognized, no Docker image is resolved and stages run
directly on the Jenkins agent (same behavior as `useDockerAgent: false`).

### Specialized images

| Image | Used by | Includes |
|-------|---------|----------|
| `ghcr.io/getbrik/brik-runner-analysis:latest` | SAST | semgrep, checkov, scancode, license_finder |
| `ghcr.io/getbrik/brik-runner-scanner:latest` | Scan, Container Scan | grype, syft, osv-scanner, gitleaks, trufflehog, hadolint, dockle |
| `ghcr.io/getbrik/brik-runner-deploy:latest` | Deploy | helm, kubectl, argocd, docker compose, ssh, rsync |

All images include Brik prerequisites: bash 4+, yq, jq, git, docker-cli.

### Without Docker agents

Set `useDockerAgent: false` to run directly on the Jenkins agent:

```groovy
@Library('brik') _
brikPipeline(useDockerAgent: false)
```

In this case, all tools must be installed on the agent node (see Prerequisites below).

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `brikHome` | auto-detected | Path to Brik shared library |
| `nodeLabel` | `''` (any) | Jenkins agent label |
| `timeoutMin` | `60` | Pipeline timeout in minutes |
| `useDockerAgent` | `true` | Run stages in brik-runner Docker containers |
| `dockerNetwork` | auto-detected | Docker network for runner containers |

## Architecture

```
Jenkinsfile (2 lines)
  -> brikPipeline.groovy (orchestrator)
    -> brikStage.groovy (stage executor)
      -> jenkins-wrapper.sh (Jenkins -> BRIK_* normalization)
        -> portable stages (runtime/bash/lib/stages/*.sh)
```

### Variable Mapping

| Jenkins Variable | Brik Variable | Notes |
|-----------------|---------------|-------|
| `GIT_BRANCH` | `BRIK_BRANCH` | `origin/` prefix stripped |
| `TAG_NAME` | `BRIK_TAG` | |
| `GIT_COMMIT` | `BRIK_COMMIT_SHA` | |
| `GIT_COMMIT[0:7]` | `BRIK_COMMIT_SHORT_SHA` | |
| `BRIK_TAG` or `BRIK_BRANCH` | `BRIK_COMMIT_REF` | Tag takes priority |
| (default) | `BRIK_PIPELINE_SOURCE` | Always "push" |
| `CHANGE_ID` | `BRIK_MERGE_REQUEST_ID` | Multibranch PRs |
| `WORKSPACE` | `BRIK_PROJECT_DIR` | |

### BRIK_HOME

Jenkins clones Global Libraries into `${WORKSPACE}@libs/brik/`. Since the brik repo
contains everything (runtime + shared-libs), this path is used as `BRIK_HOME`.
No additional clone needed.

### Docker integration

When `useDockerAgent: true` (default), `brikPipeline`:

1. Runs Init on the Jenkins agent to read `brik.yml`
2. Resolves the stack-specific image from `project.stack` and `project.stack_version`
3. Pulls the image and runs Build, Lint, Test, Package stages inside it
4. Uses specialized images for SAST (analysis), Scan (scanner), and Deploy (deploy)
5. Auto-detects the Docker network from the Jenkins container
6. Mounts `/var/run/docker.sock` for container build/push in Package stage
7. Sets `HOME=$WORKSPACE` to redirect all tool caches into the workspace

### Cache management

Docker containers use `HOME=$WORKSPACE` and explicit environment variables to keep
caches persistent across builds:

| Tool | Cache location |
|------|---------------|
| npm | `$WORKSPACE/.npm` |
| pip | `$WORKSPACE/.cache/pip` |
| Maven | `$WORKSPACE/.m2/repository` |
| Gradle | `$WORKSPACE/.gradle` |
| Cargo | `$WORKSPACE/.cargo` |
| NuGet | `$WORKSPACE/.nuget` |

The `cleanWs` step preserves these cache directories between builds.

### Environment propagation

Environment variables matching `NEXUS_*`, `BRIK_*`, `REGISTRY_*`, or `ARGOCD_*`
are automatically forwarded to Docker containers via an env file.

## Prerequisites

When using Docker agents (default), the Jenkins **controller node** needs:
- Docker installed and running
- Access to `ghcr.io/getbrik/*` images (or mirror them to your private registry)

When running without Docker agents (`useDockerAgent: false`), the Jenkins **agent node** needs:
- bash 4.0+
- [yq](https://github.com/mikefarah/yq) (Go binary) for YAML parsing
- [jq](https://jqlang.github.io/jq/) for JSON manipulation
- git
- Tools required by your stack (node, npm, java, mvn, etc.)
- Tools required by your stages (semgrep, grype, helm, etc.)

## Troubleshooting

### Scripts not executable

If stages fail with "permission denied", ensure the shell scripts have execute permission
in the repository, or override the brik home path:

```groovy
brikPipeline(brikHome: '/custom/path/to/brik')
```

### yq/jq not found

With Docker agents (default), yq and jq are pre-installed in brik-runner images.
Without Docker agents, install yq and jq on the Jenkins node.

### Sandbox restrictions

The Brik library must be configured as a **trusted** Global Library (not sandboxed) since
it uses `sh` steps. This is the default when configuring via CasC with `modernSCM`.

### GIT_BRANCH has origin/ prefix

The jenkins-wrapper.sh automatically strips the `origin/` prefix from `GIT_BRANCH`.
No manual intervention needed.

### Docker network issues

If Docker containers cannot reach external services (registries, Git servers, ArgoCD),
pass the correct network:

```groovy
brikPipeline(dockerNetwork: 'my-network')
```

By default, `brikPipeline` auto-detects the Docker network from the Jenkins container.

### Private registry

If your agents cannot pull from `ghcr.io`, mirror the brik-images to your private registry.
The stack image is resolved automatically from `brik.yml`. For specialized images, configure
Jenkins environment variables or update the image names in a fork.
