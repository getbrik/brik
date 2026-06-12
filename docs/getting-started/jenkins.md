# Getting Started: Jenkins

This is the happy path to a working Brik pipeline on Jenkins. For the full
integration reference -- runner images, parameters, Docker agents, variable
mapping, cache management, troubleshooting -- see
[platforms/jenkins.md](../platforms/jenkins.md).

## Prerequisites

- A Jenkins controller where you can configure a Global Pipeline Library.
- When using Docker agents (the default), the controller needs Docker and access
  to `ghcr.io/getbrik/*` images (or a mirror of
  [brik-images](https://github.com/getbrik/brik-images)).
- The Brik repo on a Git server Jenkins can reach (GitHub, Gitea, ...).

## 1. Add Brik as a trusted Global Pipeline Library

Configure it via Configuration as Code (CasC) or the Jenkins UI. It must be
**trusted** (not sandboxed), because the library uses `sh` steps:

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

The brik repo contains both the runtime and the shared library, so no separate
clone is needed -- Jenkins clones the library into `${WORKSPACE}@libs/brik/` and
uses that path as `BRIK_HOME`.

## 2. Add a `Jenkinsfile`

Add a two-line `Jenkinsfile` to your project root:

```groovy
@Library('brik') _
brikIntegrate()
```

## 3. Add a `brik.yml`

Add a `brik.yml` to your project root. The minimum is two fields:

```yaml
version: 1
project:
  name: my-app
  stack: node
```

`brik init --platform jenkins` can scaffold both files for you; see
[getting-started/local.md](local.md).

That is it. The next build runs the full [fixed flow](../concepts/fixed-flow.md).
Init reads the stack and resolves the runner image; Build, the parallel
Lint / SAST / Scan / Test group, Package, Container Scan, and Deploy run in
order; Notify runs in a `finally` block so it always executes. Every run
produces an [aggregate report](../operations/pipeline-report.md).

## Next steps: Enable supply-chain security

Once CI is working, to use the **CD flow** with attestation verification:

1. Create an infrastructure referential with endpoints, credentials, policies,
   and trust material. See [artifact attestation](../concepts/artifact-attestation.md).
2. Store the referential on a path Jenkins can mount into containers
   (a shared volume, a Git repo, etc.).
3. Pass `brikInfraDir` to `brikIntegrate()`:

```groovy
@Library('brik') _
brikIntegrate(brikInfraDir: '/path/to/infra-referential')
```

The deploy job resolves versions to digests, verifies attestations, and checks
the promotion journal. See [platforms/jenkins.md](../platforms/jenkins.md) for
the full setup.

## Other next steps

- [Configuration overview](../configuration/overview.md) -- what you can put in `brik.yml`
- [Jenkins platform reference](../platforms/jenkins.md) -- parameters, Docker agents, variable mapping, signing credential isolation
- [Credentials](../operations/credentials.md) -- wiring secrets for publish and deploy
- [Troubleshooting](../operations/troubleshooting.md) -- common failures and fixes
