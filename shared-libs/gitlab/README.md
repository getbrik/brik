# Brik GitLab Shared Library

GitLab CI templates that implement the Brik **fixed flow** pipeline.

## Quick Start

Add this to your `.gitlab-ci.yml`:

```yaml
include:
  - project: 'brik/gitlab-templates'
    ref: v0.3.0
    file: '/templates/pipeline.yml'
```

And create a `brik.yml` in your project root:

```yaml
version: 1

project:
  name: my-app
  stack: node
```

That's it. Your project now has a full CI/CD pipeline.

## Fixed Flow

The pipeline implements this stage sequence:

```
Init -> Release -> Build -> Lint||SAST||Scan||Test -> Package -> Container Scan -> Deploy -> Notify
```

- **Init**: Detects stack, validates `brik.yml`, sets up environment
- **Release**: Computes semantic version (conditional, on tags)
- **Build**: Compiles/builds via `brik-lib` (`build.run`)
- **Lint**: Code quality checks (parallel with SAST/Scan/Test)
- **SAST**: Static analysis, license, IaC scans (parallel, uses `brik-runner-analysis` image)
- **Scan**: Dependency audit + secret scanning (parallel, uses `brik-runner-scanner` image)
- **Test**: Runs tests via `brik-lib` (parallel with Lint/SAST/Scan)
- **Package**: Container build (conditional, on tags)
- **Container Scan**: Image vulnerability scan (uses `brik-runner-scanner` image)
- **Deploy**: Deploy to target environment (conditional, uses `brik-runner-deploy` image)
- **Notify**: Pipeline summary (always runs)

Lint, SAST, Scan, and Test run in **parallel** (GitLab `verify` stage with separate `needs`).

## Setup on Your GitLab Instance

### 1. Push the Brik runtime

Create a `brik/brik` project on your GitLab instance and push the Brik source:

```bash
git clone https://github.com/getbrik/brik.git
cd brik
git remote add gitlab http://your-gitlab.com/brik/brik.git
git push gitlab main --tags
```

### 2. Push the GitLab templates

Create a `brik/gitlab-templates` project and push this directory:

```bash
cd shared-libs/gitlab
git init -b main
git add -A
git commit -m "Initial commit"
git remote add origin http://your-gitlab.com/brik/gitlab-templates.git
git push -u origin main
git tag v0.1.0
git push origin v0.1.0
```

### 3. Add the bootstrap file to your project

Create `.gitlab-ci.yml` in your project root (see Quick Start above).

## Runner Images

The pipeline uses specialized [brik-images](https://github.com/getbrik/brik-images) for each stage:

| Variable | Default image | Used by |
|----------|---------------|---------|
| `BRIK_CI_IMAGE` | `ghcr.io/getbrik/brik-runner-base:latest` | Init, Release, Build, Lint, Test, Package, Notify |
| `BRIK_ANALYSIS_IMAGE` | `ghcr.io/getbrik/brik-runner-analysis:latest` | SAST (semgrep, checkov, scancode, license_finder) |
| `BRIK_SCANNER_IMAGE` | `ghcr.io/getbrik/brik-runner-scanner:latest` | Scan, Container Scan (grype, syft, osv-scanner, gitleaks, trufflehog, hadolint, dockle) |
| `BRIK_DEPLOY_IMAGE` | `ghcr.io/getbrik/brik-runner-deploy:latest` | Deploy (helm, kubectl, argocd, docker compose, ssh, rsync) |

All images include Brik prerequisites (bash, yq, jq, git, docker-cli). Images tagged with `/.brik-runner`
marker file skip prerequisite installation automatically.

### Stack-specific images

The Init stage automatically resolves `BRIK_CI_IMAGE` from `project.stack` and
`project.stack_version` in your `brik.yml`. No manual configuration needed.

| Stack | Resolved image | Includes |
|-------|----------------|----------|
| node | `ghcr.io/getbrik/brik-runner-node:22` (or `:24`) | Node.js + npm + Brik prereqs |
| java | `ghcr.io/getbrik/brik-runner-java:21` (or `:25`) | JDK + Maven + Brik prereqs |
| python | `ghcr.io/getbrik/brik-runner-python:3.13` (or `:3.14`) | Python + pip + Brik prereqs |
| rust | `ghcr.io/getbrik/brik-runner-rust:1` | Rust + Cargo + Clippy + Rustfmt + Brik prereqs |
| dotnet | `ghcr.io/getbrik/brik-runner-dotnet:9.0` (or `:10.0`) | .NET SDK + Brik prereqs |

If `stack` is not set or not recognized, the pipeline falls back to `brik-runner-base:latest`.

> **Note**: Overriding `BRIK_CI_IMAGE` via `.gitlab-ci.yml` variables is not yet supported.
> The Init stage always resolves the image from `brik.yml` and overwrites the variable.

### Using custom images

If you prefer your own images, ensure they have:
- bash 4+, git, yq, jq (or let the `before_script` install them automatically)
- Your stack tools (node, java, python, etc.)

The `before_script` detects the package manager (apk, apt-get, yum, dnf) and installs
missing prerequisites on the fly. Brik-runner images skip this step (detected via `/.brik-runner`).

## How It Works

Each GitLab CI job:

1. Checks for `/.brik-runner` marker (skips prereq install if present)
2. Otherwise installs yq, jq, git, bash via the detected package manager
3. Clones the `brik/brik` repo to `/opt/brik` (depth 1, pinned to `BRIK_LIB_REF`)
4. Sources the GitLab wrapper script
5. Calls `brik.gitlab.run_stage <stage_name>`
6. The stage wrapper invokes `stage.run` from the Brik runtime

The runtime handles logging, context, hooks, error handling, and summary generation.

### Cache relocation

GitLab CI requires caches to be within `$CI_PROJECT_DIR`. The pipeline template
sets environment variables to redirect tool caches:

| Variable | Path |
|----------|------|
| `PIP_CACHE_DIR` | `$CI_PROJECT_DIR/.cache/pip` |
| `MAVEN_OPTS` | `-Dmaven.repo.local=$CI_PROJECT_DIR/.m2/repository` |
| `GRADLE_USER_HOME` | `$CI_PROJECT_DIR/.gradle` |
| `CARGO_HOME` | `$CI_PROJECT_DIR/.cargo` |
| `NUGET_PACKAGES` | `$CI_PROJECT_DIR/.nuget/packages` |

## Configuration

See the [brik.yml specification](../../docs/specs/01-brik-yml.md) for all configuration options.

### Pipeline variables

| Variable | Default | Description |
|----------|---------|-------------|
| `BRIK_LIB_REF` | `v0.3.0` | Git ref of the Brik runtime to clone |
| `BRIK_REPO` | `${CI_SERVER_URL}/brik/brik.git` | URL of the Brik runtime repository |
| `BRIK_HOME` | `/opt/brik` | Path where the runtime is cloned |
| `BRIK_LOG_LEVEL` | `info` | Log verbosity (debug, info, warn, error) |
| `BRIK_CI_IMAGE` | `ghcr.io/getbrik/brik-runner-base:latest` | Default runner image |
| `BRIK_ANALYSIS_IMAGE` | `ghcr.io/getbrik/brik-runner-analysis:latest` | Analysis stage image |
| `BRIK_SCANNER_IMAGE` | `ghcr.io/getbrik/brik-runner-scanner:latest` | Scanner stage image |
| `BRIK_DEPLOY_IMAGE` | `ghcr.io/getbrik/brik-runner-deploy:latest` | Deploy stage image |

### Stack Defaults

When `project.stack` is set, default tools are applied:

| Stack | Build | Test | Lint | Format |
|-------|-------|------|------|--------|
| node | `npm run build` | `jest` | `eslint` | `prettier` |
| java | `mvn package` | `junit` | `checkstyle` | `google-java-format` |
| python | `pip install .` | `pytest` | `ruff` | `ruff format` |

### Coverage reports

The `brik-test` job ships a `coverage_report` block so GitLab can render a
coverage badge on merge requests. GitLab's YAML schema only accepts
`cobertura` or `jacoco` for `coverage_format` and validates this at YAML
parse time -- **before** any job runs -- so the value cannot be driven by an
init-stage dotenv. The template therefore hardcodes the cobertura defaults:

```yaml
coverage_report:
  coverage_format: cobertura
  path: coverage/coverage.xml
```

Out of the box:

| Stack | Coverage format produced | GitLab badge |
|-------|--------------------------|--------------|
| `python` (pytest-cov) | cobertura -> `coverage/coverage.xml` | works |
| `dotnet` (XPlat Code Coverage) | cobertura -> `coverage/<guid>/coverage.cobertura.xml` | flatten or override path |
| `java` (jacoco) | jacoco -> `coverage/jacoco.xml` | override format to jacoco |
| `node` (jest --coverage) | lcov -> `coverage/lcov.info` | override or accept no badge |
| `rust` (cargo-llvm-cov) | lcov -> `coverage/lcov.info` | override or accept no badge |

Stacks where the badge does not match still get their coverage files
archived under `artifacts.paths` and the pipeline stays green -- only the
inline GitLab MR-diff badge is missing.

#### Coverage percentage badge (automatic)

The pipeline-level **coverage % badge** (visible on the project page,
the MR widget, and the pipeline trend) is wired automatically: after
the test stage runs, brik emits a single canonical line on the job
log:

```
[brik] coverage: 87.42%
```

The brik-test job in this template ships a `coverage:` regex that
parses that line:

```yaml
brik-test:
  coverage: '/\[brik\] coverage: ([\d\.]+)%/'
```

`lib/transverse/coverage.sh` reads either `coverage/coverage.xml`
(Cobertura) or `coverage/jacoco.xml` (Jacoco) and computes the line
percentage. No per-project regex needed -- works for python, node,
java, rust, dotnet without override.

#### Project-level override

To enable the badge for jacoco, lcov, or a non-default path, override the
`brik-test` job in your own `.gitlab-ci.yml`. GitLab merges the override
hash into the templated job:

```yaml
include:
  - project: 'brik/gitlab-templates'
    ref: v0.3.0
    file: '/templates/pipeline.yml'

# java example: switch the format to jacoco and point at the file the
# Jacoco maven/gradle plugin produces.
brik-test:
  artifacts:
    reports:
      coverage_report:
        coverage_format: jacoco
        path: coverage/jacoco.xml
```

If you keep your coverage report under a non-default directory, set the
matching `path:` value in the override. The rest of the templated `brik-test`
job (script, cache, dependencies, paths, junit) continues to apply.

## Requirements

- GitLab CI Runner with **Docker executor**
- Access to `ghcr.io/getbrik/*` images (or mirror them to your private registry)
- `brik/brik` and `brik/gitlab-templates` repos on the same GitLab instance

## Troubleshooting

**yq not found**: The `before_script` downloads yq automatically. If it fails, ensure the runner
has internet access or use a `brik-runner-*` image which has yq pre-installed.

**Runtime not cloned**: Check that `brik/brik` exists on your GitLab instance and has the correct
tag. Verify the runner can access the repo URL.

**Runner not registered**: Ensure the GitLab Runner is registered and has the Docker executor configured.

**Private registry**: If your runners cannot pull from `ghcr.io`, mirror the brik-images to your
private registry and override `BRIK_CI_IMAGE`, `BRIK_ANALYSIS_IMAGE`, `BRIK_SCANNER_IMAGE`, and
`BRIK_DEPLOY_IMAGE` in your `.gitlab-ci.yml`.

## Directory Structure

```
shared-libs/gitlab/
  scripts/
    config-reader.sh    - Reads brik.yml via yq
    condition-eval.sh   - Evaluates deploy conditions
    gitlab-wrapper.sh   - Bridges GitLab CI to stage.run
  templates/
    pipeline.yml        - Main entry point (stages, defaults, includes)
    jobs/
      init.yml          - Init stage job
      release.yml       - Release stage job (conditional)
      build.yml         - Build stage job
      lint.yml          - Lint stage job (verify, parallel)
      sast.yml          - SAST stage job (verify, parallel, analysis image)
      scan.yml          - Scan stage job (verify, parallel, scanner image)
      test.yml          - Test stage job (verify, parallel)
      package.yml       - Package stage job (conditional)
      container-scan.yml - Container scan job (scanner image)
      deploy.yml        - Deploy stage job (conditional, deploy image)
      notify.yml        - Notify stage job (always)
  spec/                 - ShellSpec tests
```
