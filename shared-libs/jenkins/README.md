# Brik Jenkins Shared Library

Jenkins Global Pipeline Library that implements the Brik
[fixed flow](../../docs/concepts/fixed-flows.md).

This README is an **implementation annex**. The user-facing documentation is
canonical and lives in the docs tree:

- [Getting started: Jenkins](../../docs/getting-started/jenkins.md) -- first-time setup
- [Jenkins platform reference](../../docs/reference/platforms/jenkins.md) -- runner images, parameters, Docker agents, variable mapping, cache management, troubleshooting
- [`brik.yml` configuration](../../docs/reference/configuration/overview.md) -- the project config file

## Directory structure

```
shared-libs/jenkins/
  scripts/
    jenkins-wrapper.sh       - normalizes Jenkins env to BRIK_* and dispatches to stage.run
  vars/
    brikIntegrate.groovy      - entry point: node {}, SCM checkout, fixed flow, Notify finally
    brikStage.groovy         - stage executor (sources jenkins-wrapper.sh)
    brikRunStage.groovy      - wraps docker.image(...).inside(...) { brikStage(...) }
    brikResolveHome.groovy   - locates the shared library under ${WORKSPACE}@libs/
    brikDockerArgs.groovy    - builds the Docker run args (HOME, caches, network, env-file)
    brikReadDotenv.groovy    - parses .brik-logs/pipeline.env to extract BRIK_CI_IMAGE
  spec/                      - ShellSpec tests
```

## How it works

```
Jenkinsfile (2 lines)
  -> brikIntegrate.groovy   (orchestrator)
    -> brikStage.groovy    (stage executor)
      -> jenkins-wrapper.sh (Jenkins env -> BRIK_* normalization)
        -> portable stages  (lib/stages/*.sh via stage.run)
```

All stage logic lives in portable Bash; the Groovy layer only handles SCM
checkout, stash/unstash, `archiveArtifacts`, and the Notify `finally`
orchestration. Jenkins clones the library into `${WORKSPACE}@libs/brik/`, which
is used directly as `BRIK_HOME` (the brik repo carries both the runtime and the
shared library, so no extra clone is needed).

The per-var responsibilities and the Jenkins-to-`BRIK_*` variable mapping are
documented in the
[Jenkins platform reference](../../docs/reference/platforms/jenkins.md).

## Tests

```bash
shellspec shared-libs/jenkins/spec/
```
