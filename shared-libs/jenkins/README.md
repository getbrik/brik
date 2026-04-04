# Brik Jenkins Shared Library

Jenkins integration for the Brik CI/CD pipeline system.

## Quick Start

1. Add Brik as a **Global Pipeline Library** in Jenkins (via CasC or UI):

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
Init -> Release -> Build -> Quality || Security -> Test -> Package -> Deploy -> Notify
```

- **Quality** and **Security** run in parallel
- **Notify** runs in a `finally` block (always executes)
- **Release** and **Package** are conditional (tag-based)
- All stage logic lives in portable Bash (no business logic in Groovy)

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

Jenkins clones Global Libraries into `${WORKSPACE}@libs/brik/`. Since the brik repo contains everything (runtime + shared-libs), this path is used as `BRIK_HOME`. No additional clone needed.

## Prerequisites

The Jenkins node must have:

- **bash** 4.0+
- **yq** (Go binary) for YAML parsing
- **jq** for JSON manipulation
- Tools required by your stack (node, npm, etc.)

## Troubleshooting

### Scripts not executable

If stages fail with "permission denied", ensure the shell scripts have execute permission in the repository, or add a pre-step:

```groovy
brikPipeline(brikHome: '/custom/path/to/brik')
```

### yq/jq not found

Install yq and jq on the Jenkins node or agent image. For Docker-based agents, include them in your Dockerfile.

### Sandbox restrictions

The Brik library must be configured as a **trusted** Global Library (not sandboxed) since it uses `sh` steps. This is the default when configuring via CasC with `modernSCM`.

### GIT_BRANCH has origin/ prefix

The jenkins-wrapper.sh automatically strips the `origin/` prefix from `GIT_BRANCH`. No manual intervention needed.
