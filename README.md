<p align="center">
  <img src="docs/brik.jpg" alt="Brik">
</p>

<p align="center">
  <b>CI/CD as configuration, not code.</b><br>
  Write it once. Run it on GitLab, Jenkins, GitHub Actions, and your laptop.<br>
  <i>Stop maintaining pipelines. Start shipping.</i>
</p>

<p align="center">
  <a href="https://github.com/getbrik/brik/actions/workflows/ci.yml"><img src="https://img.shields.io/github/actions/workflow/status/getbrik/brik/ci.yml?label=CI" alt="CI"></a>
  <a href="https://codecov.io/gh/getbrik/brik"><img src="https://codecov.io/gh/getbrik/brik/graph/badge.svg?token=QMN3W4XI8Y" alt="codecov"></a>
  <a href="#quality-in-numbers"><img src="https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/getbrik/brik/main/docs/badges/ccn.json" alt="CCN"></a>
  <a href="#quality-in-numbers"><img src="https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/getbrik/brik/main/docs/badges/functions.json" alt="Functions"></a>
  <a href="#quality-in-numbers"><img src="https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/getbrik/brik/main/docs/badges/lloc.json" alt="LLOC"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MPL--2.0-blue" alt="License"></a>
</p>

<p align="center">
  <a href="docs/README.md">Documentation</a> -
  <a href="https://github.com/getbrik/brik/issues">Issues</a> -
  <a href="https://github.com/getbrik/briklab">Briklab</a>
</p>

---

## The problem Brik solves

CI/CD logic is the same everywhere. Build the code. Run the tests. Scan for
vulnerabilities. Push the image. Deploy. Notify. Yet every team rewrites it --
per project, per platform, per migration.

- Move from GitLab to GitHub Actions? Rewrite the pipeline.
- Add Jenkins for a customer? Rewrite again, in Groovy.
- Onboard a new repo? Copy-paste the last one and pray.
- Tighten a coverage threshold across 40 services? Forty pull requests.

Brik treats CI/CD like the solved problem it is. The logic lives in one place.
Platforms are thin adapters. **You describe your project, not the pipeline.**

## What you write

A realistic `brik.yml` for a deployable Node service, deployed via GitOps:

```yaml
version: 1

project:
  name: orders-api
  stack: node                 # auto-detected; pin the toolchain when you need to
  stack_version: "22"

publish:
  docker:
    registry: registry.example.com
    username_var: BRIK_PUBLISH_DOCKER_USER       # credentials are references,
    password_var: BRIK_PUBLISH_DOCKER_PASSWORD   #   never values

artifacts:
  channels:
    release:                                     # CI publishes here; CD resolves a digest here
      registry: registry.example.com/orders/orders-api
  evidence:                                      # append-only journal: promotions + deployments
    repo: https://git.example.com/orders/evidence.git
    token_var: BRIK_GIT_TOKEN

deploy:
  environments:
    staging:
      target: gitops                             # ArgoCD reconciles a config repo (pull-based)
      controller: argocd
      repo: https://git.example.com/orders/config-deploy.git
      app_name: orders-staging
      accepts_channel: release
      config_ref: main                           # env config redeploys without a new version
      validates_for: production                  # a green staging deploy grants production
      gates:
        require_digest: true                     # never deploy a mutable tag
    production:
      target: gitops
      controller: argocd
      repo: https://git.example.com/orders/config-deploy-prod.git
      app_name: orders-prod
      accepts_channel: release
      gates:
        require_digest: true
        require_attestation: true                        # verify the signed SBOM + SLSA provenance
        requires_eligibility: [artifact_validated_for]   # staging vouched for this digest
```

That is the entire definition -- the CI flow, the CD flow, the promotion chain
between environments, and the gates that protect production. No 400-line
`.gitlab-ci.yml`. No custom-Groovy `Jenkinsfile`. No bash glue you maintain.

Only `version` and `project.name` are required: the stack is auto-detected and
every other field has a per-stack default. The rest of `brik.yml` is where you
override what matters for *your* project -- thresholds, deploy targets,
registries, secrets. You configure your project. You never write pipeline logic.

> Wondering how to configure each part above? The
> **[`brik.yml` reference](docs/reference/configuration/README.md)** lists every
> top-level section, each with a dedicated page: what it is for, what it does,
> when it runs, and how to configure it.

## Two flows, one configuration

Brik is not one pipeline. It is **two fixed flows selected by the trigger**,
running from the same repository and the same `brik.yml`:

- a **push, tag, or merge request** runs the **CI flow**, which builds and
  publishes one immutable, signed artifact;
- an explicit **deploy trigger** (`brik deploy`, a `Run pipeline` form, or a
  parameterized Jenkins job) runs the **CD flow**, which takes an artifact that
  already exists and proves it before deploying it.

The two flows are **decoupled in time**: build once, deploy that version to any
environment, any number of times, days later.

```mermaid
flowchart LR
    init["Init"] --> release["Release"]
    release --> build["Build"]
    build --> lint["Lint"]
    build --> sast["SAST"]
    build --> scan["Dep Scan"]
    build --> test["Test"]
    lint -. quality gate .-> package["Package"]
    sast -. quality gate .-> package
    scan -. quality gate .-> package
    test --> package
    package --> cscan["Container<br/>Scan"]
    cscan --> promote["Promote"]
    promote --> notify["Notify"]
```

> **CI** -- the quality gate sits at Package: nothing is packaged unless tests
> pass and the security stages succeed. Container Scan signs an SBOM and SLSA
> provenance onto the image digest; Promote copies the artifact *and its
> evidence* to the release channel.

```mermaid
flowchart LR
    resolve["Resolve<br/>version to digest"] --> gates["Gates<br/>digest, attestation,<br/>eligibility"]
    gates --> deploy["Deploy<br/>pinned digest"]
    deploy --> health["Rollout<br/>health"]
    health --> readback["Read-back<br/>live state"]
    readback --> journal["Journal<br/>deployed + validates_for"]
    journal --> notify["Notify"]
```

> **CD** -- resolve the version to a digest, walk the fail-closed gates, deploy
> the pinned digest, read the live state back, and journal the result.
> `brik status --environment <e>` then reports the environment as three layers
> and flags any drift.

You cannot accidentally ship broken or unverified code by editing the pipeline,
because there is no pipeline to edit. See **[Fixed flows](docs/concepts/fixed-flows.md)**.

## Core concepts

Brik is a small set of ideas. Each links to a dedicated page that goes from the
functional "what it does for you" to the configuration and the source of truth.

| Concept | In one sentence | Learn more |
|---------|-----------------|------------|
| **Fixed flows** | Two flows -- CI builds one signed artifact, CD deploys a pinned digest -- selected by trigger, never one monolith you edit. | [fixed-flows](docs/concepts/fixed-flows.md) |
| **The plan** | A reproducible per-commit JSON document that decides which stages run and why, identical on every platform (`brik plan --explain`). | [plan](docs/concepts/plan.md) |
| **Declarations everywhere** | Your project, the pipeline, the operator knobs, and your infrastructure are all schema-validated declarations, enforced fail-closed at runtime. | [declarations](docs/concepts/declarations.md) |
| **Runner classes** | Each stage runs in a pinned, provable OCI image chosen by its declared class -- the same image on your laptop and in CI. | [runner-classes](docs/concepts/runner-classes.md) |
| **Supply-chain gates** | CI signs evidence; CD enforces three fail-closed gates -- digest, attestation, eligibility -- before deploying. | [supply-chain](docs/concepts/supply-chain.md) |
| **Business vs technical** | A pure decision matrix separating "did it exit zero" from "does that block the release", so a daily pipeline neither cries wolf nor ships known-broken. | [business-outcome](docs/concepts/business-outcome.md) |
| **Local execution** | The same Bash code path and runner images on your laptop, with divergences from CI declared, not silent. | [local-execution](docs/concepts/local-execution.md) |

For the layered architecture behind these, see
[architecture](docs/concepts/architecture.md).

## Supported stacks

| Stack | Auto-detected from | Build | Test | Lint |
|-------|--------------------|-------|------|------|
| **node** | `package.json` | npm / yarn / pnpm | jest / npm test | eslint / biome |
| **java** | `pom.xml` / `build.gradle(.kts)` | maven / gradle | junit / gradle | checkstyle |
| **python** | `pyproject.toml` / `requirements.txt` | pip / poetry / uv / pipenv | pytest / unittest / tox | ruff |
| **dotnet** | `*.csproj` / `*.sln` | dotnet build | dotnet test | dotnet format |
| **rust** | `Cargo.toml` | cargo build | cargo test | clippy |
| **docker** | `Dockerfile` / `Containerfile` | docker build | -- | -- |

Each stack is itself a declarative manifest and ships with a runner image from
[brik-images](https://github.com/getbrik/brik-images) (multi-arch, scanned,
rebuilt weekly for CVE fixes).

## Platform support

| Platform | Status | How it ships |
|----------|--------|--------------|
| **GitLab CI** | ✅ Functional | Shared library + pipeline template (`include:` one line) |
| **Jenkins** | ✅ Functional | Jenkins Shared Library (works with Configuration-as-Code + Gitea) |
| **GitHub Actions** | 🚧 Bootstrap shipped, reusable workflows in progress | `brik init --platform github` scaffolds today |
| **Local CLI** | ✅ Functional | `brik integrate` |

## Get started

| You use | Start here |
|---------|------------|
| GitLab CI | [docs/getting-started/gitlab.md](docs/getting-started/gitlab.md) |
| Jenkins | [docs/getting-started/jenkins.md](docs/getting-started/jenkins.md) |
| Local CLI | [docs/getting-started/local.md](docs/getting-started/local.md) |

Install Brik on macOS or Linux:

```bash
brew tap getbrik/tap
brew install brik

brik doctor    # check prerequisites
brik init      # scaffold brik.yml + your platform bootstrap
brik validate  # confirm the config is valid
brik integrate # run the full CI flow locally
```

Full documentation: **[docs/README.md](docs/README.md)**.

## Quality, in numbers

- ✅ **5100+** ShellSpec examples in the core suite, 0 failures -- plus dedicated suites for the GitLab, Jenkins, and local adapters
- ✅ **80%** Codecov gate on project and patch, enforced in CI
- ✅ **22** live end-to-end scenarios against real GitLab and Jenkins instances in [briklab](https://github.com/getbrik/briklab) -- digest-pinned CD, signed-attestation keystones, promotion-chain refusals, channel immutability
- ✅ **29** JSON Schemas govern every contract (config, referential, plan, journal events, reports), validated fail-closed at runtime
- ✅ **Drift gates in CI**: the generated config reference, the compiled registry cache, and every platform parameter surface must all match their source of truth
- ✅ **ShellCheck** clean on every file; **shellmetrics** tracks complexity, function count, and LLOC on every push to `main` (the badges above are live)

## Related projects

- [brik-images](https://github.com/getbrik/brik-images) - official Docker images for Brik runners. Multi-arch, scanned, rebuilt weekly.
- [briklab](https://github.com/getbrik/briklab) - local Docker infrastructure for testing Brik pipelines against real GitLab and Jenkins.
- [homebrew-tap](https://github.com/getbrik/homebrew-tap) - the Homebrew tap for `brew install brik`.

## Transparency notice

We use AI-assisted development to accelerate implementation. Every contribution,
human or AI-generated, goes through the same gates: code review, ShellSpec
coverage, ShellCheck, end-to-end runs on briklab, and CI.

## License

[MPL-2.0](LICENSE)
