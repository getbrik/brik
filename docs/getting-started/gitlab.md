# Getting Started: GitLab CI

This is the happy path to a working Brik pipeline on a GitLab instance. For the
full integration reference -- runner images, pipeline variables, cache
relocation, coverage reports, troubleshooting -- see
[platforms/gitlab.md](../platforms/gitlab.md).

## Prerequisites

- A GitLab instance where you can create projects.
- A GitLab Runner with the **Docker executor**.
- Access to `ghcr.io/getbrik/*` images, or a mirror of
  [brik-images](https://github.com/getbrik/brik-images) on your own registry.

## 1. Push the Brik runtime

Create a `brik/brik` project on your GitLab instance and push the Brik source:

```bash
git clone https://github.com/getbrik/brik.git
cd brik
git remote add gitlab http://your-gitlab.example.com/brik/brik.git
git push gitlab main --tags
```

## 2. Push the GitLab templates

Create a `brik/gitlab-templates` project and push the `shared-libs/gitlab`
directory:

```bash
cd shared-libs/gitlab
git init -b main
git add -A
git commit -m "Initial commit"
git remote add origin http://your-gitlab.example.com/brik/gitlab-templates.git
git push -u origin main
git tag v0.7.0
git push origin v0.7.0
```

## 3. Add the bootstrap file to your project

Add a `.gitlab-ci.yml` to your project root:

```yaml
include:
  - project: 'brik/gitlab-templates'
    ref: v0.7.0
    file: '/templates/brik-integrate.yml'
```

This is a single classic pipeline: a `brik-plan` job computes the
execution plan, then every stage job consults it and skips itself when
the plan marks the stage not-applicable -- a docs-only commit shows the
skipped stages as green "skipped (per plan)" jobs without running their
work. See [platforms/gitlab.md](../platforms/gitlab.md) for the full
job graph.

## 4. Add a `brik.yml`

Add a `brik.yml` to your project root. The minimum is two fields:

```yaml
version: 1
project:
  name: my-app
  stack: node
```

`brik init --platform gitlab` can scaffold both files for you; see
[getting-started/local.md](local.md).

That is it. Your next push runs the full [fixed flow](../concepts/fixed-flow.md):
Init detects the stack and resolves the runner image, then Build, the parallel
Lint / SAST / Scan / Test group, Package, Container Scan, Deploy, and Notify run
in order. Every run produces an
[aggregate report](../operations/pipeline-report.md).

## Next steps: Enable supply-chain security

Once CI is working, to use the **CD flow** with attestation verification:

1. Create an infrastructure referential (endpoints, credentials, policies,
   trust material) and mount it on the runner at `/etc/brik/infra`. See
   [artifact attestation](../concepts/artifact-attestation.md).
2. Select CI or CD per run with `include:rules`: one repository, two flows,
   discriminated by the `BRIK_DEPLOY_VERSION` trigger variable:

```yaml
include:
  - project: 'brik/gitlab-templates'
    ref: v0.7.0
    file: '/templates/brik-integrate.yml'
    rules:
      - if: '$BRIK_DEPLOY_VERSION !~ /.+/'
  - project: 'brik/gitlab-templates'
    ref: v0.7.0
    file: '/templates/brik-deploy.yml'
    rules:
      - if: '$BRIK_DEPLOY_VERSION =~ /.+/'
```

A push or tag runs the CI flow; a "Run pipeline" (or API trigger) with
`BRIK_DEPLOY_VERSION` and `BRIK_DEPLOY_ENVIRONMENT` runs the CD flow, which
resolves the version to a digest, verifies the attestations and checks the
promotion journal before deploying. See
[platforms/gitlab.md](../platforms/gitlab.md) for the full setup.

## Other next steps

- [Configuration overview](../configuration/overview.md) -- what you can put in `brik.yml`
- [GitLab platform reference](../platforms/gitlab.md) -- runner images, variables, coverage badge
- [Credentials](../operations/credentials.md) -- wiring secrets for publish and deploy, signing credential isolation
- [Troubleshooting](../operations/troubleshooting.md) -- common failures and fixes
