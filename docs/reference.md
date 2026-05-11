# Brik Reference

Complete reference for CI platforms, supported stacks, and `brik.yml` configuration.

For architecture and design principles, see [architecture.md](architecture.md).
For a quick overview, see the [README](../README.md).

---

## CI Platforms

| Platform | Status | Integration mechanism | Bootstrap file |
|----------|--------|-----------------------|----------------|
| **GitLab CI** | Functional | Shared library (pipeline template) | `.gitlab-ci.yml` |
| **Jenkins** | Functional | Jenkins Shared Library (CasC + Gitea) | `Jenkinsfile` |
| **GitHub Actions** | Planned | Reusable workflows | `.github/workflows/*.yml` |

### GitLab CI

The GitLab shared library is the primary platform adapter. It implements the fixed
flow as native GitLab CI stages and jobs.

**Bootstrap file** (`.gitlab-ci.yml`):

```yaml
include:
  - project: 'brik/gitlab-templates'
    ref: v0.4.0
    file: '/templates/pipeline.yml'
```

**Pipeline variables** set by the template:

| Variable | Default | Description |
|----------|---------|-------------|
| `BRIK_LIB_REF` | `v0.4.0` | Git ref of the Brik runtime to clone |
| `BRIK_REPO` | `${CI_SERVER_URL}/brik/brik.git` | URL of the Brik runtime repository |
| `BRIK_HOME` | `/opt/brik` | Installation directory on runners |
| `BRIK_LOG_LEVEL` | `info` | Log verbosity (debug, info, warn, error) |
| `BRIK_PLATFORM` | `gitlab` | Platform identifier |
| `BRIK_CI_IMAGE` | `ghcr.io/getbrik/brik-runner-base:latest` | Default runner image (auto-resolved by Init from stack) |
| `BRIK_ANALYSIS_IMAGE` | `ghcr.io/getbrik/brik-runner-analysis:latest` | Analysis stage image |
| `BRIK_SCANNER_IMAGE` | `ghcr.io/getbrik/brik-runner-scanner:latest` | Scanner stage image |
| `BRIK_DEPLOY_IMAGE` | `ghcr.io/getbrik/brik-runner-deploy:latest` | Deploy stage image |

Quality and Security stages run in parallel (same GitLab CI stage).

---

## Supported Stacks

Brik supports 5 technology stacks. The stack can be set explicitly in `brik.yml` or
auto-detected from project files.

### Auto-detection

| Marker file | Detected stack |
|-------------|----------------|
| `package.json` | node |
| `pom.xml`, `build.gradle`, `build.gradle.kts` | java |
| `requirements.txt`, `setup.py`, `pyproject.toml` | python |
| `Cargo.toml` | rust |
| `*.csproj`, `*.sln` | dotnet |

### Stack defaults

Each stack comes with sensible defaults for build, test, lint, and format tools.
These are the effective behaviors when the corresponding `brik.yml` key is omitted.
The actual logic is in stack-specific modules (`build.node.run`, `build.java.run`, etc.).

| | **node** | **java** | **python** | **rust** | **dotnet** |
|---|---|---|---|---|---|
| **Build** | `<pm> run build` | `mvn -B package -DskipTests` | `python -m build` | `cargo build` | `dotnet build` |
| **Test** | `npm test` or `npx jest` | `mvn -B test` or `./gradlew test` | `python -m pytest` | `cargo test` | `dotnet test` |
| **Lint tool** | eslint | checkstyle | ruff | clippy | dotnet-format |
| **Format tool** | prettier | google-java-format (*) | ruff-format | rustfmt | dotnet-format |

- **Node build**: `<pm>` is the detected package manager (npm, yarn, or pnpm). See package manager detection below.
- **Node test**: runs `npm test` if `scripts.test` exists in `package.json`, otherwise falls back to `npx jest`.
- **Java build/test**: Maven runs in batch mode (`-B`). Gradle prefers `./gradlew` when the wrapper is present.
- **Python build**: installs dependencies first, then builds. The build tool varies: `uv build`, `poetry build`, or `python -m build` (with `pip wheel` as fallback for pip/pipenv).
- (*) **Java format**: `google-java-format` is defined as the default formatter but is not yet implemented (logs a warning and skips).

### Package manager detection

**Node** -- detected from lock files:

| Lock file | Package manager | Install command |
|-----------|-----------------|-----------------|
| `pnpm-lock.yaml` | pnpm | `pnpm install --frozen-lockfile` |
| `yarn.lock` | yarn | `yarn install --frozen-lockfile` |
| `package-lock.json` | npm | `npm ci --cache .npm --prefer-offline` |
| (none) | npm | `npm install` |

**Java** -- detected from build files:

| Build file | Build tool | Default goal |
|------------|------------|--------------|
| `pom.xml` | Maven | `-B package -DskipTests` |
| `build.gradle` / `build.gradle.kts` | Gradle (`./gradlew` preferred) | `build -x test` |

**Python** -- detected from project files (in priority order):

| Marker | Package manager | Build command |
|--------|-----------------|---------------|
| `uv.lock` | uv | `uv sync && uv build` |
| `poetry.lock` or `[tool.poetry]` in `pyproject.toml` | poetry | `poetry install && poetry build` |
| `Pipfile` | pipenv | `pipenv install` then `pipenv run python -m build` (fallback: `pip wheel`) |
| `pyproject.toml` | pip | `pip install .` then `python -m build` (fallback: `pip wheel`) |
| `setup.py` | pip | `pip install .` then `python -m build` (fallback: `pip wheel`) |

> **Note:** `requirements.txt` triggers Python stack detection but is not sufficient
> for building. A `pyproject.toml`, `setup.py`, or `Pipfile` must also be present.

---

## `brik.yml` Reference

Only `version` and `project.name` are required. Everything else is optional and
falls back to stack-specific defaults.

JSON Schema: [`schemas/config/v1/brik.schema.json`](../schemas/config/v1/brik.schema.json)

### Minimal example

```yaml
version: 1
project:
  name: my-app
  stack: node
```

### Complete example

```yaml
version: 1

project:
  name: my-java-app
  stack: java
  stack_version: "21"
  root: services/api          # monorepo service root

release:
  strategy: semver
  tag_prefix: v

build:
  command: mvn package -DskipTests

test:
  framework: junit
  coverage:
    threshold: 80
    report: target/site/cobertura/coverage.xml

quality:
  lint:
    tool: checkstyle
    config: checkstyle.xml
    fix: false
  format:
    tool: google-java-format
    check: true

security:
  sast:
    tool: semgrep
    ruleset: auto
  deps:
    tool: osv-scanner
    severity: high
  secrets:
    tool: gitleaks
  license:
    allowed: MIT,Apache-2.0,BSD-3-Clause
    denied: GPL-3.0
  container:
    image: registry.example.com/my-app:latest
    severity: high
  severity_threshold: high

package:
  docker:
    image: registry.example.com/my-app
    dockerfile: Dockerfile
    context: .
    platforms:
      - linux/amd64
      - linux/arm64
    build_args:
      JAVA_VERSION: "21"

publish:
  maven:
    repository: https://nexus.example.com/repository/maven-releases/
    username_var: NEXUS_USERNAME
    password_var: NEXUS_PASSWORD

deploy:
  workflow: trunk-based
  environments:
    staging:
      when: "branch == 'main'"
      target: k8s
      namespace: staging
      manifest: k8s/staging/
    production:
      when: "tag =~ 'v*'"
      target: gitops
      repo: https://oauth2:${GIT_TOKEN}@gitlab.example.com/org/infra.git
      path: apps/my-app/production
      controller: argocd
      app_name: my-app-prod

notify:
  slack:
    channel: "#deployments"
    on: [failure, success]
  email:
    to: team@example.com
    on: [failure]
  webhook:
    url: https://hooks.example.com/pipeline
    on: [always]

hooks:
  pre_build: echo "preparing build environment"
  post_deploy: ./scripts/smoke-test.sh
```

---

### `version`

| Key | Type | Required | Default | Description |
|-----|------|----------|---------|-------------|
| `version` | integer | yes | -- | Schema version. Must be `1`. |

---

### `project`

| Key | Type | Required | Default | Description |
|-----|------|----------|---------|-------------|
| `project.name` | string | yes | -- | Project name. Used in logs, notifications, and artifact labels. |
| `project.stack` | string | no | auto-detected | Technology stack: `node`, `java`, `python`, `dotnet`, `rust`. |
| `project.stack_version` | string | no | -- | Stack version for runner image selection (e.g. `"22"` for node, `"21"` for java). |
| `project.root` | string | no | `.` | Relative path to service root (for monorepos). |
| `project.env` | string | no | `brik.env` (auto-detected) | Path to a project-level env file (`KEY=VALUE` format), relative to the project root. CI environment variables take precedence over file entries. |

---

### `release`

| Key | Type | Required | Default | Description |
|-----|------|----------|---------|-------------|
| `release.strategy` | string | no | `semver` | Release strategy: `semver`, `calver`, `custom`. |
| `release.tag_prefix` | string | no | `v` | Prefix for release tags (e.g. `v1.2.3`). |
| `release.changelog.enabled` | boolean | no | `true` | Whether to generate a changelog on release. |
| `release.changelog.format` | string | no | `conventional` | Changelog format: `conventional`, `keep-a-changelog`. Exported but not yet consumed by the release stage. |
| `release.changelog.file` | string | no | `CHANGELOG.md` | Path to the changelog file. |

---

### `build`

| Key | Type | Required | Default | Description |
|-----|------|----------|---------|-------------|
| `build.command` | string | no | stack default | Build command override (Tier 1). Overrides both tool and stack defaults. |
| `build.tool` | string | no | auto-detected | Build tool (e.g. `npm`, `yarn`, `pnpm`, `maven`, `gradle`, `poetry`, `uv`, `pip`, `pipenv`, `cargo`, `dotnet`). Overrides auto-detection (Tier 2). Ignored when `command` is set. |
| `build.node_version` | string | no | -- | Node.js version (e.g. `"20"`). Only for `stack: node`. |
| `build.java_version` | string | no | -- | Java version (e.g. `"21"`). Only for `stack: java`. |
| `build.python_version` | string | no | -- | Python version (e.g. `"3.12"`). Only for `stack: python`. |
| `build.dotnet_version` | string | no | -- | .NET version (e.g. `"8.0"`). Only for `stack: dotnet`. |
| `build.rust_version` | string | no | -- | Rust version (e.g. `"stable"`). Only for `stack: rust`. |

---

### `test`

| Key | Type | Required | Default | Description |
|-----|------|----------|---------|-------------|
| `test.command` | string | no | stack default | Test command override (Tier 1). |
| `test.framework` | string | no | stack default | Test framework (e.g. `jest`, `junit`, `pytest`). |

#### `test.coverage`

| Key | Type | Required | Default | Description |
|-----|------|----------|---------|-------------|
| `test.coverage.threshold` | integer | no | `80` | Coverage threshold (0-100). Exported as `BRIK_TEST_COVERAGE_THRESHOLD` but **not yet enforced** -- the test stage does not fail on a low score today. |
| `test.coverage.report` | string | no | -- | Path to Cobertura XML coverage report. Exported as `BRIK_TEST_COVERAGE_REPORT` but not yet consumed. |

#### `test.reports`

Opt-in contract for producing coverage and JUnit XML reports during
the test stage. When enabled, Brik injects framework-specific flags
into the test command so `brik-artifacts/test/coverage/` and `brik-artifacts/test/junit.xml` are
populated and surfaced as CI artefacts (GitLab `coverage_report` /
`junit` reports, Jenkins JUnit plugin).

| Key | Type | Required | Default | Description |
|-----|------|----------|---------|-------------|
| `test.reports.enabled` | boolean | no | `false` | Single master switch for both coverage and JUnit emission. When false, the test runner uses its native defaults (no coverage, no JUnit). |
| `test.reports.coverage.format` | enum | no | `auto` | One of `lcov`, `cobertura`, `jacoco`, `auto`. `auto` picks the native format per stack: lcov for node/rust, cobertura for python/dotnet, jacoco for java. |
| `test.reports.coverage.output_dir` | string | no | `brik-artifacts/test/coverage` | Directory where the coverage report is written. |
| `test.reports.junit.output_path` | string | no | `brik-artifacts/test/junit.xml` | Path where the JUnit XML file is written. |

The configured paths are exposed to downstream stages via four
`brik-init.env` variables (`BRIK_TEST_REPORTS_ENABLED`,
`BRIK_TEST_COVERAGE_FORMAT`, `BRIK_TEST_COVERAGE_DIR`,
`BRIK_TEST_JUNIT_PATH`). Per-stack flag injection (jest --coverage,
pytest --cov, surefire/jacoco, cargo-llvm-cov + cargo-nextest, dotnet
--collect "XPlat Code Coverage") is rolled out incrementally; today
only the schema and the dotenv exposure are wired up.

---

### `quality`

#### `quality.lint`

| Key | Type | Required | Default | Description |
|-----|------|----------|---------|-------------|
| `quality.lint.enabled` | boolean | no | `true` | Set to `false` to skip lint checks entirely. |
| `quality.lint.command` | string | no | -- | Lint command override (Tier 1). |
| `quality.lint.tool` | string | no | stack default | Lint tool (e.g. `eslint`, `checkstyle`, `ruff`, `clippy`). |
| `quality.lint.config` | string | no | -- | Path to lint configuration file. Exported as `BRIK_QUALITY_LINT_CONFIG` but not yet consumed by the linter. |
| `quality.lint.fix` | boolean | no | `false` | Run the linter in auto-fix mode. Exported as `BRIK_QUALITY_LINT_FIX` but not yet consumed -- linters always run in check-only mode. |

##### Lint contract per tool

When `quality.lint.tool` is declared (Tier 2 strict resolution),
Brik enforces the following contract per tool. Tier 3 (auto-detect
from project files) keeps a permissive fallback that skips with a
warning when the expected config is missing.

| Tool | Accepted config files | Behaviour if config absent | Behaviour if installed binary missing |
|------|-----------------------|----------------------------|---------------------------------------|
| `eslint` | `eslint.config.{js,mjs,cjs}` (ESLint 9+) ; `.eslintrc.*` (ESLint <= 8 only) | Tier 2: `BRIK_EXIT_CONFIG_ERROR` if eslint major >= 9 and only legacy `.eslintrc.*` is present ; otherwise `skipped` with warn. Tier 3: silent `skipped`. | `BRIK_EXIT_MISSING_DEP` (no fallback to `npx` registry-pull which would silently break legacy configs). |
| `biome` | `biome.json` (recommended, optional -- biome ships defaults) | `skipped` with warn | `BRIK_EXIT_MISSING_DEP` |
| `ruff` | `pyproject.toml` `[tool.ruff]`, `ruff.toml`, or `.ruff.toml` | Ruff applies its defaults; no skip | `BRIK_EXIT_MISSING_DEP` |
| `checkstyle` | `pom.xml` (`maven-checkstyle-plugin`) or `build.gradle` (`apply plugin: 'checkstyle'`) | `BRIK_EXIT_MISSING_DEP` | `BRIK_EXIT_MISSING_DEP` |
| `clippy` | none (Rust defaults); `clippy.toml` optional for overrides | No skip | `BRIK_EXIT_MISSING_DEP` |
| `dotnet-format` | `.editorconfig` recommended for project rules | No skip; uses `dotnet-format` defaults | `BRIK_EXIT_MISSING_DEP` |

Universal rule: if `quality.lint.tool` is declared in `brik.yml`,
the expected config must exist. Otherwise Brik fails fast at the
lint stage instead of producing a cryptic tool error several lines
down. The permissive fallback (skip + warn) is reserved for Tier 3
auto-detect, where the user did not declare an explicit intent.

##### Lint stage status semantics

`aggregate-report.json` records `stages.lint.tech.status` with one
of five values:

| Status | Meaning | Stage exit code |
|--------|---------|-----------------|
| `disabled` | `quality.lint.enabled: false` (explicit user opt-out) | 0 |
| `not-applicable` | No lint/format/type_check tool configured | 0 |
| `skipped` | Tool configured but expected config file absent (Tier 3 only) | 0 |
| `passed` | The configured check ran and succeeded | 0 |
| `failed` | The configured check ran and reported violations | non-zero |

#### `quality.format`

| Key | Type | Required | Default | Description |
|-----|------|----------|---------|-------------|
| `quality.format.command` | string | no | -- | Format command override (Tier 1). |
| `quality.format.tool` | string | no | stack default | Formatter (e.g. `prettier`, `google-java-format`, `ruff format`, `rustfmt`). |
| `quality.format.check` | boolean | no | `false` | Check mode only (fail if files would be reformatted). Exported as `BRIK_QUALITY_FORMAT_CHECK` but not yet consumed -- formatters always run in check mode. |

#### `quality.type_check`

Type checking only runs when `type_check.tool` or `type_check.command` is explicitly
set in `brik.yml`. It is not auto-detected from project files.

| Key | Type | Required | Default | Description |
|-----|------|----------|---------|-------------|
| `quality.type_check.command` | string | no | -- | Type check command override (Tier 1). |
| `quality.type_check.tool` | string | no | -- | Type checker: `tsc`, `mypy`, `pyright`. Must be set explicitly to enable type checking. |

---

### `security`

All security scans are configured as structured objects under `security:`.

#### `security.sast`

| Key | Type | Required | Default | Description |
|-----|------|----------|---------|-------------|
| `security.sast.command` | string | no | -- | SAST command override (Tier 1). |
| `security.sast.tool` | string | no | `semgrep` | SAST tool. Only `semgrep` is currently implemented. |
| `security.sast.ruleset` | string | no | -- | Ruleset or profile (e.g. `auto`, `p/security-audit`). |

#### `security.deps`

| Key | Type | Required | Default | Description |
|-----|------|----------|---------|-------------|
| `security.deps.command` | string | no | -- | Dependency scan command override (Tier 1). |
| `security.deps.tool` | string | no | `osv-scanner` | Dependency scanning tool: `osv-scanner`, `grype`. |
| `security.deps.severity` | string | no | -- | Minimum severity that fails the scan: `critical`, `high`, `medium`, `low`. |

#### `security.secrets`

| Key | Type | Required | Default | Description |
|-----|------|----------|---------|-------------|
| `security.secrets.command` | string | no | -- | Secret scan command override (Tier 1). |
| `security.secrets.tool` | string | no | `gitleaks` | Secret scanning tool: `gitleaks`, `trufflehog`. |

##### Secret scan -- gitleaks platform

`gitleaks` needs the SCM platform name to render commit/file links in
findings. Brik derives it automatically from `BRIK_PLATFORM`:

| `BRIK_PLATFORM` | `gitleaks --platform` |
|-----------------|------------------------|
| `gitlab`        | `gitlab` |
| `jenkins`       | `gitea` (briklab default) |
| anything else   | `gitlab` |

Override via the `BRIK_GITLEAKS_PLATFORM` env var when Jenkins is wired
to a non-Gitea git host (GitHub, etc.).

#### Security scan actionability per scanner

| Scanner | Default severity threshold | Override (env) | Ignore file | What blocks the stage |
|---------|----------------------------|----------------|-------------|------------------------|
| `semgrep` (SAST) | `ERROR` | `BRIK_SECURITY_SAST_SEVERITY` | `.semgrepignore` | Findings >= severity threshold |
| `osv-scanner` (Deps) | `HIGH` | `BRIK_SECURITY_DEPS_SEVERITY` (also `security.deps.severity` in brik.yml) | `osv-scanner.toml` ignore section | Findings >= severity (Brik passes `--severity {threshold}` to the binary) |
| `gitleaks` (Secret) | -- | -- (gitleaks reports any leak) | `.gitleaksignore` | Any finding |
| `grype` (Container) | `HIGH` | `BRIK_SECURITY_CONTAINER_SCAN_SEVERITY` | `.grype.yaml` | Findings >= severity (`--fail-on $severity`) |

#### `security.license`

License compliance is checked using `license_finder` (primary), with `syft` and
`scancode` as fallbacks.

| Key | Type | Required | Default | Description |
|-----|------|----------|---------|-------------|
| `security.license.allowed` | string | no | -- | Comma-separated list of allowed licenses. |
| `security.license.denied` | string | no | -- | Comma-separated list of denied licenses. |

#### `security.container`

Scans container images using `grype` (primary) or `dockle` (fallback).

| Key | Type | Required | Default | Description |
|-----|------|----------|---------|-------------|
| `security.container.image` | string | no | -- | Container image to scan. |
| `security.container.severity` | string | no | -- | Minimum severity: `critical`, `high`, `medium`, `low`. |

#### `security.iac`

| Key | Type | Required | Default | Description |
|-----|------|----------|---------|-------------|
| `security.iac.command` | string | no | -- | IaC scan command override (Tier 1). |
| `security.iac.tool` | string | no | -- | IaC scanning tool (e.g. `checkov`, `tfsec`). |

#### `security.severity_threshold`

| Key | Type | Required | Default | Description |
|-----|------|----------|---------|-------------|
| `security.severity_threshold` | string | no | `high` | Global minimum severity that fails the stage: `critical`, `high`, `medium`, `low`. |

---

### `package`

#### `package.docker`

| Key | Type | Required | Default | Description |
|-----|------|----------|---------|-------------|
| `package.docker.image` | string | no | -- | Full image name including registry (e.g. `registry.example.com/my-app`). |
| `package.docker.dockerfile` | string | no | `Dockerfile` | Path to Dockerfile. |
| `package.docker.context` | string | no | `.` | Docker build context path. |
| `package.docker.platforms` | string[] | no | -- | Target platforms for multi-arch builds (e.g. `linux/amd64`). |
| `package.docker.build_args` | object | no | -- | Build arguments passed as `--build-arg KEY=VALUE`. |

---

### `publish`

Publish artifacts to package registries. Each subsection corresponds to a registry type.
Credential values are never stored in `brik.yml` -- only environment variable **names** are referenced.
For details on how credential indirection works and platform setup examples, see [credentials.md](credentials.md).

#### `publish.npm`

| Key | Type | Required | Default | Description |
|-----|------|----------|---------|-------------|
| `publish.npm.registry` | string (URI) | no | `https://registry.npmjs.org` | npm registry URL. |
| `publish.npm.tag` | string | no | `latest` | Distribution tag for the published package. |
| `publish.npm.access` | string | no | -- | Package access level for scoped packages: `public`, `restricted`. |
| `publish.npm.token_var` | string | no | -- | Environment variable name holding the npm auth token. |

#### `publish.docker`

| Key | Type | Required | Default | Description |
|-----|------|----------|---------|-------------|
| `publish.docker.image` | string | no | -- | Full image name including registry (e.g. `ghcr.io/org/app`). |
| `publish.docker.registry` | string | no | -- | Container registry URL for `docker login`. |
| `publish.docker.tags` | string[] | no | -- | Tags to push. If empty, uses `BRIK_VERSION`. |
| `publish.docker.username_var` | string | no | -- | Environment variable name holding the registry username. |
| `publish.docker.password_var` | string | no | -- | Environment variable name holding the registry password or token. |

#### `publish.maven`

| Key | Type | Required | Default | Description |
|-----|------|----------|---------|-------------|
| `publish.maven.repository` | string (URI) | no | -- | Maven repository URL. |
| `publish.maven.username_var` | string | no | -- | Environment variable name holding the repository username. |
| `publish.maven.password_var` | string | no | -- | Environment variable name holding the repository password. |

#### `publish.pypi`

| Key | Type | Required | Default | Description |
|-----|------|----------|---------|-------------|
| `publish.pypi.repository` | string (URI) | no | `https://upload.pypi.org/legacy/` | PyPI repository URL. |
| `publish.pypi.token_var` | string | no | -- | Environment variable name holding the PyPI API token. |

#### `publish.cargo`

| Key | Type | Required | Default | Description |
|-----|------|----------|---------|-------------|
| `publish.cargo.registry` | string | no | `crates-io` | Cargo registry name (e.g. `brik-cargo` for a private Nexus registry). |
| `publish.cargo.index` | string | no | -- | Sparse index URL for the registry (e.g. `sparse+http://nexus:8081/repository/brik-cargo/`). Required for private registries. |
| `publish.cargo.token_var` | string | no | -- | Environment variable name holding the registry API token. |

#### `publish.nuget`

| Key | Type | Required | Default | Description |
|-----|------|----------|---------|-------------|
| `publish.nuget.source` | string (URI) | no | `https://api.nuget.org/v3/index.json` | NuGet source URL. |
| `publish.nuget.token_var` | string | no | -- | Environment variable name holding the NuGet token or API key. |

---

### `deploy`

| Key | Type | Required | Default | Description |
|-----|------|----------|---------|-------------|
| `deploy.workflow` | string | no | -- | Git workflow convention: `trunk-based`, `git-flow`, `github-flow`. Pre-configures environments based on branch/tag patterns. User-defined environments override profile defaults. |

#### `deploy.environments.<name>`

Each key under `environments` is an environment name (e.g. `staging`, `production`).

| Key | Type | Required | Default | Description |
|-----|------|----------|---------|-------------|
| `when` | string | no | -- | Condition expression: `branch == 'main'`, `tag =~ 'v*'`, compound `AND`/`OR`. |
| `target` | string | no | -- | Deployment target: `ssh`, `compose`, `k8s`, `helm`, `gitops`. |
| `strategy` | string | no | -- | Deployment strategy: `rolling`, `blue-green`, `canary`. Defined in schema but not yet wired into the deploy stage. The `deploy.strategy` module exists but is not called automatically. |
| `namespace` | string | no | -- | Kubernetes namespace (for `k8s` and `helm` targets). |
| `manifest` | string | no | -- | Path to Kubernetes manifests (for `k8s` target). |
| `chart` | string | no | -- | Helm chart path or repository reference (for `helm` target). |
| `release_name` | string | no | environment name | Helm release name (for `helm` target). |
| `values` | string | no | -- | Path to Helm values file (for `helm` target). |
| `repo` | string | no | -- | GitOps infrastructure repository as a clonable git URL (for `gitops` target). Embed credentials in the URL via a CI variable (e.g. `https://oauth2:${GIT_TOKEN}@host/path.git`); there is no separate token field. |
| `path` | string | no | -- | Path within the GitOps repository for service manifests. |
| `controller` | string | no | -- | GitOps controller: `argocd` (for `gitops` target). |
| `app_name` | string | no | -- | Application name in the GitOps controller. |
| `host` | string | no | -- | Remote host address (for `ssh` target). |
| `remote_path` | string | no | -- | Absolute path on remote host (for `ssh` target). |
| `restart_cmd` | string | no | -- | Restart command on remote host (for `ssh` target). |
| `compose_file` | string | no | `docker-compose.yml` | Docker Compose file path (for `compose` target). |
| `source` | string | no | -- | Local source path to deploy (for `ssh` and `compose` targets). Implemented in the runtime but not yet in the JSON schema. |

---

### `notify`

#### `notify.slack`

Sends notifications via Slack Incoming Webhook. Requires a `SLACK_WEBHOOK_URL`
environment variable set on the runner. Silently skips if the variable is not set.

| Key | Type | Required | Default | Description |
|-----|------|----------|---------|-------------|
| `notify.slack.channel` | string | no | -- | Slack channel (e.g. `#deployments`). |
| `notify.slack.on` | string[] | no | `always` | Events: `failure`, `success`, `always`. |

#### `notify.email`

Sends email via system `sendmail` or `mail` command. Silently skips if neither
tool is available (common in containerized CI environments).

| Key | Type | Required | Default | Description |
|-----|------|----------|---------|-------------|
| `notify.email.to` | string | no | -- | Recipient address(es), comma-separated. |
| `notify.email.on` | string[] | no | `always` | Events: `failure`, `success`, `always`. |

#### `notify.webhook`

| Key | Type | Required | Default | Description |
|-----|------|----------|---------|-------------|
| `notify.webhook.url` | string (URI) | no | -- | Webhook endpoint URL. |
| `notify.webhook.on` | string[] | no | `always` | Events: `failure`, `success`, `always`. |

---

### `hooks`

Inline shell commands executed before or after each stage. Available hooks:

| Hook | When it runs |
|------|--------------|
| `pre_init` / `post_init` | Before/after init stage |
| `pre_release` / `post_release` | Before/after release stage |
| `pre_build` / `post_build` | Before/after build stage |
| `pre_lint` / `post_lint` | Before/after lint stage |
| `pre_sast` / `post_sast` | Before/after SAST scan |
| `pre_scan` / `post_scan` | Before/after security scan stage |
| `pre_test` / `post_test` | Before/after test stage |
| `pre_package` / `post_package` | Before/after package stage |
| `pre_container_scan` / `post_container_scan` | Before/after container scan |
| `pre_deploy` / `post_deploy` | Before/after deploy stage |
| `pre_notify` / `post_notify` | Before/after notify stage |

Each hook is an inline shell command. Chain multiple commands with `&&` or `;`:

```yaml
hooks:
  pre_build: echo "step 1" && ./scripts/prepare.sh
  post_deploy: ./scripts/smoke-test.sh
```

`pre_*` hooks can abort the stage (non-zero exit). `post_*` hooks are
best-effort and do not override the stage exit code.

File-based hooks (`.brik/hooks/pre-build.sh`) are also supported and handled by the
Bash Runtime (Layer 0) independently of the `hooks` section in `brik.yml`.

---

## Pipeline Report Fields

Every pipeline run produces `aggregate-report.json` (and a Markdown rendering)
under `${BRIK_LOG_DIR}` (local mode) or `${BRIK_WORKSPACE}/brik-artifacts/`
(CI mode). The fields below describe the v1.1 producer contract; producers
emit `schema_version: "1.1"` today. Consumers should match on `^1\.` to
accept future minor 1.x evolutions.

### Schema versions

Two schema versions coexist under [`schemas/report/`](../schemas/report/):

| Version | Status | When to use |
|---|---|---|
| [`v1.1`](../schemas/report/v1.1/) | **Active producer schema.** `business.status` is required and typed (`success / warning / error`); `pipeline.context`, `pipeline.business.status`, and `summary.business` are required on the aggregate; the legacy `tech.warning`, `tech.warning_reason`, and `summary.warnings` are explicitly rejected. `tech` and `business` keep `additionalProperties: true` so per-stage telemetry (build_duration_ms, framework, image_built, ...) and stage-specific business top-level scalars (release.{bump_type, new_version}, init.{platform, project_name}, ...) land without bumping the schema. | Today (all producers) |
| [`v1`](../schemas/report/v1/) | **Read-only legacy schema.** Kept so archived fragments and external producers that have not yet migrated keep aggregating cleanly. The aggregator accepts both 1.0 and 1.1 fragments on input and always emits 1.1 on output. | Reading historical artefacts only |

The v1.1 deltas in detail:

- **`business.status`** (enum `success | warning | error`) — outcome derived
  by the business filter from the technical exit code, the pipeline context
  (snapshot vs release), and stage-emitted side-band signals. Required on
  every fragment.
- **`business.reason`** (string) — human-readable explanation of why the
  business outcome is not `success` (e.g., `"14 findings ignored by policy:
  11 below severity, 3 no upstream fix"`). Optional but conventionally
  required when `status != success`.
- **`tech.kind`** (12-value enum: `ok`, `failure`, `invalid-input`,
  `missing-dependency`, `invalid-environment`, `external-service-unavailable`,
  `io-failure`, `configuration-error`, `timeout`, `interrupted`, `check-failed`,
  `not-applicable`) — readable label derived from the stage exit code, used
  in reports and recap output.
- **`pipeline.context`** (enum `snapshot | release`) — `release` when
  `pipeline.commit.tag` is non-null, `snapshot` otherwise. Drives the
  business filter (snapshot is lenient, release is strict) and the
  `continue_on_error` default.
- **`pipeline.business.status`** — pipeline-wide outcome aggregated from
  per-stage `business.status` values. `error` if any stage is `error`,
  `warning` if any stage is `warning` and none are `error`, `success`
  otherwise.
- **`summary.business`** — typed counts `{success_count, warning_count,
  error_count}` aggregated across the `stages` array.
- The legacy `tech.warning` boolean and `summary.warnings[]` array are
  rejected by v1.1; the same information lives in the per-stage
  `business.{status, reason}` block instead.

### Top-level `pipeline.commit`

Carries the commit identity for at-a-glance auditing. Mirrors the fields
recorded under `init.business.commit` so dashboards can lift them without
walking the stages array.

| Field | Source | Notes |
|---|---|---|
| `sha` | `BRIK_COMMIT_SHA` (from `CI_COMMIT_SHA` / `GIT_COMMIT`) | 40-char hex |
| `short_sha` | `BRIK_COMMIT_SHORT_SHA` | 7- or 8-char prefix |
| `ref` | `BRIK_COMMIT_REF` | branch or tag name (CI-platform native) |
| `branch` | `BRIK_COMMIT_BRANCH` | empty on tag-only builds |
| `tag` | `BRIK_COMMIT_TAG` | absent on branch builds |
| `author` | `CI_COMMIT_AUTHOR` parsed (`Name <email>`) or `git log -1 --format=%an` | author name only |
| `author_email` | parsed from `CI_COMMIT_AUTHOR` or `git log -1 --format=%ae` | -- |
| `timestamp` | `CI_COMMIT_TIMESTAMP` or `git log -1 --format=%aI` | ISO-8601 strict |
| `message_subject` | `CI_COMMIT_TITLE` or `git log -1 --format=%s` | first line only |

### Per-stage fields

Each entry in `stages[]` carries its own `tech` (machine-targeted) and
`business` (persona-targeted) sub-objects in addition to the runtime
fields (`stage`, `status`, `rc`, `runner`, `duration_ms`, `timestamp`).

#### `init`

| Field | Type | Source |
|---|---|---|
| `tech.stack` | string | `.project.stack` (resolved) |
| `tech.stack_version` | string | `.project.stack_version` |
| `tech.config_file` | string | path to active `brik.yml` |
| `tech.config_valid` | bool | JSON Schema validation result |
| `tech.prereqs_present` | object | `{yq, jq, jv}` booleans |
| `business.project_name` | string | `.project.name` |
| `business.platform` | string | `gitlab` / `jenkins` / `local` |
| `business.commit.*` | object | same shape as `pipeline.commit` |
| `business.pipeline.{id, url}` | object | CI native pipeline reference |
| `business.triggered_by` | string | user login or trigger source |

#### `release`

| Field | Type | Source |
|---|---|---|
| `tech.strategy` | string | `.release.strategy` (semver / calver) |
| `tech.tag_prefix` | string | `.release.tag_prefix` |
| `tech.dry_run` | bool | `BRIK_DRY_RUN` |
| `business.previous_version` | string | last tag matching `tag_prefix` |
| `business.new_version` | string | computed or `BRIK_TAG`-derived |
| `business.bump_type` | string | `none` / `explicit` |
| `business.tag.{name, sha, annotated, dry_run}` | object | created tag metadata |
| `business.changelog.{path, entries_count, generated_at}` | object | omitted on idempotent re-runs (tag already at HEAD) |

#### `build`

| Field | Type | Source |
|---|---|---|
| `tech.stack` | string | resolved stack |
| `tech.tool` | string | `.build.tool` or `auto` |
| `tech.command` | string | `.build.command` or `<stack-default>` |
| `tech.cache_hit` | bool | `BRIK_BUILD_CACHE_HIT` (when set by stack module / wrapper) |
| `business.artifact.{type, name, size_bytes, sha256, path}` | object | first existing of `dist/`, `target/release`, `target`, `build/libs`, `build`, `bin/Release`, `out` |

#### `test`

| Field | Type | Source |
|---|---|---|
| `tech.framework` | string | `.test.framework` |
| `tech.tool` | string | `BRIK_TEST_TOOL` or `BRIK_TEST_FRAMEWORK` fallback |
| `tech.coverage_tool` | string | `BRIK_TEST_COVERAGE_FORMAT` |
| `business.tests.{total, passed, failed, skipped, duration_ms}` | object | parsed from `BRIK_TEST_JUNIT_PATH` (JUnit XML) when present |
| `business.coverage.line_pct` | string | from Cobertura `coverage.xml` or Jacoco `jacoco.xml` |
| `business.coverage.branch_pct` | string | omitted when the report has no branch metric |

#### `lint`

| Field | Type | Source |
|---|---|---|
| `tech.checks` | array | configured checks (`lint`, `format`, `type_check`) |
| `tech.tools` | object | per-check tool name (`{lint: eslint, format: prettier, ...}`) |
| `tech.commands` | object | per-check command override when set |
| `business.violations.total` | int | `sarif.count_total` summed across present per-check SARIF files |
| `business.violations.by_severity` | object | `{critical, high, medium, low, info}` summed across files |
| `business.violations.by_check` | object | per-check totals, e.g. `{lint: 5, format: 6}` |
| `business.report` | object | `{format: "sarif", path: "brik-artifacts/lint/lint.sarif"}` rollup pointer |
| `business.fix_applied` | bool | `BRIK_QUALITY_LINT_FIX` (`true` only when `--fix` ran) |

The lint stage scans `${BRIK_WORKSPACE}/brik-artifacts/lint/<check>.sarif` for each
configured check. Tools without native SARIF support require a converter
from `lib/transverse/sarif.sh` (`sarif.from_prettier`, `sarif.from_tsc`,
`sarif.from_dotnet_format`). When no SARIF is produced, `business.*` is
omitted (backward compatible).

#### `sast`

| Field | Type | Source |
|---|---|---|
| `tech.tool` | string | `.security.sast.tool` (default `semgrep`) |
| `tech.ruleset` | string | `.security.sast.ruleset` |
| `business.findings.total` | int | `sarif.count_total brik-artifacts/sast/sast.sarif` |
| `business.findings.by_severity` | object | `{critical, high, medium, low, info}` |
| `business.findings.cwe` | array | sorted, deduped CWE identifiers extracted from rule tags |
| `business.report` | object | `{format: "sarif", path: <BRIK_SECURITY_SAST_OUTPUT_PATH or brik-artifacts/sast/sast.sarif>}` |

Configured via `security.sast.{output_format, output_path}`.

#### `scan`

| Field | Type | Source |
|---|---|---|
| `tech.deps.tool` | string | `.security.deps.tool` (default `osv-scanner`) |
| `tech.secret.tool` | string | `.security.secrets.tool` (default `gitleaks`) |
| `tech.severity_threshold` | string | `.security.deps.severity` or global default |
| `business.deps.vulnerabilities.{total, by_severity}` | object | parsed from `brik-artifacts/scan/deps.sarif` |
| `business.deps.affected_packages` | int | `sbom.vuln_count` (or `sbom.component_count` fallback) on `brik-artifacts/scan/sbom.cdx.json` |
| `business.deps.sbom_path` | string | path to the CycloneDX 1.5 file (when produced) |
| `business.secret.findings_count` | int | `sarif.count_total brik-artifacts/scan/secret.sarif` |
| `business.secret.report` | object | `{format: "sarif", path: ...}` |
| `business.report` | object | rollup pointer to the deps SARIF |

Configured via `security.deps.{output_path, sbom.{enabled, format,
output_path}}` and `security.secrets.output_path`. Each section is
independently no-op when its artifact is absent.

#### Severity normalization

The canonical Brik severity vocabulary used in every `by_severity` object
is `{critical, high, medium, low, info}`. SARIF producers express
severity in different places (`result.level`, `tool.driver.rules[].defaultConfiguration.level`,
or `properties.security-severity` numeric CVSS). `lib/transverse/sarif.sh`
resolves them in this order, then maps:

| Source | -> Canonical |
|---|---|
| `properties.security-severity` >= 9.0 (CVSS) | `critical` |
| `properties.security-severity` >= 7.0 | `high` |
| `properties.security-severity` >= 4.0 | `medium` |
| `properties.security-severity` > 0 | `low` |
| SARIF `level: error` | `high` |
| SARIF `level: warning` | `medium` |
| SARIF `level: note` | `low` |
| SARIF `level: none`, null, or unresolved | `info` |

#### `package`

| Field | Type | Source |
|---|---|---|
| `tech.packager` | string | `docker` |
| `tech.dockerfile` | string | `.package.docker.dockerfile` |
| `tech.image_built` | bool string | `true` once `stacks.docker.build` succeeded |
| `tech.image_ref` | string | `<image>:<tag>` |
| `tech.build_duration_ms` | int string | wraps `stacks.docker.build` |
| `business.image.{name, tag, full_name, digest}` | object | `digest` from `docker inspect --format='{{index .RepoDigests 0}}'` post-push |
| `business.registry.{host, namespace, repository}` | object | parsed from the configured image reference (preserves `:port` in host) |

#### `container-scan`

| Field | Type | Source |
|---|---|---|
| `tech.tool` | string | `BRIK_SECURITY_CONTAINER_TOOL` or `auto` |
| `tech.target_image` | string | mirror of `package.tech.image_ref` |
| `tech.target_digest` | string | mirror of `package.business.image.digest` (cross-stage consistency: the scanner sees what was packaged) |
| `tech.scan_duration_ms` | int string | wraps `verify.scan.run` |

#### `deploy`

| Field | Type | Source |
|---|---|---|
| `tech.environments` | array | env names (configured) |
| `business.environments[].name` | string | env name |
| `business.environments[].target` | string | k8s / helm / compose / ssh / gitops / argocd |
| `business.environments[].namespace` | string or null | configured namespace |
| `business.environments[].strategy` | string | rollout strategy (omitted when not configured) |

Skipped envs (failing `when` condition, missing target) are excluded from
`business.environments[]` so the array reflects only the work that
actually executed.

#### `notify`

`notify` is a meta-stage that produces the report itself; its content is
intentionally excluded from `aggregate-report.json` to avoid a double-pass
aggregation. The notify job's own job log (Slack / email / webhook
delivery confirmations) remains the source of truth for notification
outcomes.

---

## Business Filter

The runtime separates two orthogonal axes for every stage outcome:

- **Technical axis** -- what the stage logic returned. Captured in
  `tech.status` (success / failed / skipped) and `tech.kind` (a
  human-readable label derived from the exit code).
- **Business axis** -- what the technical outcome means for the user.
  Captured in `business.status` (success / warning / error) and
  `business.reason` (an explanation string).

The translation from technical to business is performed by
[`lib/pipeline/business.sh`](../lib/pipeline/business.sh). It is a pure
function: it reads its inputs from named flags, prints a JSON object on
stdout, and never touches the report backend or shell state.

### `business.evaluate`

```
business.evaluate \
  --tech-status   success|failed|skipped \
  --context       snapshot|release \
  [--findings-ignored <integer>=0] \
  [--tech-kind <string>=""]
```

Output on stdout:

```json
{"status":"success|warning|error","reason":"..."}
```

Exit code: `0` on success, `BRIK_EXIT_INVALID_INPUT` (`2`) on a
malformed flag (missing required argument, unknown enum value, negative
or non-integer `--findings-ignored`, unrecognised flag).

### Decision matrix

The mapping is fixed and centralised. Sub-chantiers that emit business
outcomes call `business.evaluate` instead of hardcoding their own
interpretation; consumers (notify, recap, harness) read the resulting
fields back from the fragment.

| `tech.status` | side-band               | context  | `business.status` | `business.reason`                           |
|---|---|---|---|---|
| `success`     | none                    | *        | `success`         | empty string                                |
| `success`     | `findings.ignored > 0`  | *        | `warning`         | `"<N> findings ignored by policy"`          |
| `failed`      | *                       | snapshot | `warning`         | `"failed in snapshot context (<kind>)"`     |
| `failed`      | *                       | release  | `error`           | `"failed in release context (<kind>)"`      |
| `skipped`     | *                       | *        | `success`         | `"not applicable"`                          |

`<kind>` defaults to `failure` when `--tech-kind` is omitted.

### Example call

```bash
result=$(business.evaluate \
  --tech-status success \
  --context snapshot \
  --findings-ignored 14 \
  --tech-kind ok)

status=$(jq -r .status <<<"$result")  # warning
reason=$(jq -r .reason <<<"$result")  # 14 findings ignored by policy
```

### Caller responsibilities

Callers must:

- Populate `--findings-ignored` from the stage's own side-band signal
  (e.g. `business.findings.ignored.total` after a security scanner has
  run).
- Resolve `--context` from `pipeline.commit.tag` (release if non-empty,
  snapshot otherwise).
- Persist the returned `status` and `reason` under the fragment's
  `business.{status, reason}` block.

The runtime calls `business.evaluate` from
`_stage._finalize_fragment` for every stage that runs through
`stage.run`. Inputs are sourced from the report backend
(`tech.status`, `tech.kind`, `business.findings.ignored.total`) and
from the resolved pipeline context (`BRIK_COMMIT_TAG` =>
snapshot|release). The result is persisted on the same backend under
`business.{status, reason}` and snapshotted into the per-stage
fragment by `report.write_fragment`. Stages running standalone (CI
single-job path) and stages running under `pipeline.run` share this
logic since both populate the backend before finalisation.

---

## Pipeline Context

Every pipeline run resolves to one of two execution contexts:

- `snapshot` -- short-lived run on a feature branch or unbound commit.
  Default policy: keep going past failures so the operator gets a full
  report.
- `release` -- promotion run tied to a versioned commit. Default policy:
  fail-fast so a broken stage cannot mask downstream issues.

The context is derived from `BRIK_COMMIT_TAG`:

| `BRIK_COMMIT_TAG`       | resolved context |
|---|---|
| unset or empty          | `snapshot`       |
| any non-empty string    | `release`        |

The resolved value is persisted under `pipeline.context` in
`aggregate-report.json` (both local mode and CI aggregate). The local
backend keeps its flat `pipeline_id` field for back-compat.

### `continue_on_error` precedence

Three layers, highest first:

1. `BRIK_CONTINUE_ON_ERROR=0|1` -- explicit operator override. Wins
   over everything else. Accepted truthy values: `1`, `true`, `yes`.
   Accepted falsy values: `0`, `false`, `no`. Other values fall
   through to the next layer.
2. `--continue-on-error` CLI flag -- legacy back-compat shortcut,
   equivalent to `BRIK_CONTINUE_ON_ERROR=1` when no env override is
   set.
3. Context default -- `snapshot` => `true`, `release` => `false`.

Examples:

```bash
# Snapshot, keep going past failures (default).
brik run pipeline

# Snapshot, force fail-fast for a CI lane that wants strict gating.
BRIK_CONTINUE_ON_ERROR=0 brik run pipeline

# Release, force continue to collect every stage report (e.g. for
# a post-mortem aggregator).
BRIK_COMMIT_TAG=v1.2.3 BRIK_CONTINUE_ON_ERROR=1 brik run pipeline
```

### Pre-release tags

Pre-release tags such as `v1.2.3-rc1` are treated as `release`. The
runtime does not parse the tag string; the presence of any non-empty
tag is enough. Refining this (e.g. only treating final tags as
release, or distinguishing rc from beta) is intentionally out of
scope -- callers that need a different policy override the context
indirectly via `BRIK_CONTINUE_ON_ERROR`.

---

## Pipeline Outcome

Every aggregate carries a `pipeline.business.status` and a
`summary.business` block derived from the per-stage `business.status`
written by [`_stage._finalize_fragment`](#business-filter):

```json
{
  "pipeline": { "business": { "status": "success|warning|error" } },
  "summary":  { "business": { "success_count": 3, "warning_count": 1, "error_count": 0 } }
}
```

The aggregation rules are fixed:

- `pipeline.business.status` is the worst stage status, with the order
  `error > warning > success`. Missing per-stage values default to
  `success` (legacy fragments stay neutral).
- `summary.business.<bucket>_count` counts stages whose
  `business.status` matches the bucket name. Stages without a
  `business.status` (legacy or pipeline-level skipped placeholders)
  contribute to `success_count`.

### Gatekeeper

Two callers gate the pipeline exit code off `pipeline.business.status`:

| Caller         | Behaviour                                                                |
|---|---|
| `pipeline.run` | Returns `BRIK_EXIT_FAILURE` when the worst status is `error`; `0` otherwise. The legacy `BRIK_EXIT_SKIP_WITH_WARNING` (99) is no longer produced. |
| `stages.notify`| Same contract: returns `BRIK_EXIT_FAILURE` when the worst status is `error`; `0` for `warning` or `success`. CI jobs that wire notify as the final stage inherit the pipeline exit code through it. |

The combination of context (snapshot vs release) and the matrix (see
[`business.evaluate`](#businessevaluate)) is what produces this signal:
a tech failure on snapshot maps to `business.status=warning` and lets
the run end clean (rc=0); the same failure on release maps to
`business.status=error` and surfaces as `rc=1`.

### Markdown render

`aggregate-report.md` (the canonical human-facing artefact) carries a
**Business outcome** block right after **Summary**:

```markdown
## Business outcome

- **Status:** [WARN] warning
- **Counts:** success=2, warning=1, error=0
```

---

## Configuration Resolution

When a value is not set in `brik.yml`, Brik resolves it through a three-tier hierarchy:

```
1. Command override (brik.yml *.command)     -- highest priority (Tier 1)
2. Tool selection (brik.yml *.tool)          -- auto-detected from markers (Tier 2)
3. Stack defaults (stack-specific modules)   -- applied when key is omitted (Tier 3)
```

Example for a Node.js project with no `build` section:

```
brik.yml: build.command not set, build.tool not set
  --> detect lock file: pnpm-lock.yaml -> tool = pnpm
  --> build.node.run executes: pnpm install && pnpm run build
```

Separately, **module loading** uses a three-level resolution for `.sh` files
(not configuration values):

```
1. Project extensions: ${BRIK_PROJECT_DIR}/.brik/lib/
2. BRIK_LIB            -- optional legacy override (skipped when unset)
3. BRIK_LIB_EXTENSIONS -- colon-separated notion paths (pipeline, transverse,
                          stages, stacks, rollout, deployments,
                          package-managers, cli)
```

## Findings Management

Brik unifies every static-analysis, scan, and test outcome behind a single
**SARIF 2.1.0** pipeline. The flow is identical for every stage:

```
tool output -> findings.from_sarif (validate)
            -> findings.apply_policy (preset + org allowlist + suppressions)
            -> findings.aggregate    (business.findings on the pipeline report)
            -> findings.merge_pipeline (notify stage -> aggregate.sarif)
```

Tools that already emit SARIF (semgrep, grype, gitleaks, eslint, osv-scanner,
checkov, ...) plug in directly. Tools without native SARIF (ruff, bandit,
clippy, dockle, trufflehog, scancode, junit-xml) go through a converter
under `lib/transverse/findings/converters/<tool>.sh`; see
[`docs/policy.md`](policy.md) for adding new converters.

### Built-in policy presets

`quality.findings.policy` selects how a finding is classified into
**failing** vs **ignored**. Default is `pragmatic`, which automatically
ignores findings below the severity floor and findings that have no
upstream fix.

| Preset      | Ignores below floor | Ignores `not-fixed` | Ignores `wont-fix` | Failing |
|-------------|---------------------|---------------------|--------------------|---------|
| `pragmatic` | yes                 | yes                 | yes                | rest    |
| `strict`    | yes                 | no                  | no                 | rest    |
| `permissive`| floor=critical      | yes                 | yes                | only critical with upstream fix |

A result that already carries a non-empty `suppressions[]` (tool-native
allowlist, inline annotation, ...) is never re-classified -- the SARIF
owner keeps full control.

### Severity resolution

For grype-style SARIF (sparse results, severity on the rule), Brik reads
CVSS at `runs[].tool.driver.rules[].properties["security-severity"]` and
falls back to `result.level` (`error|warning|note|none`). For ruff/bandit
and similar linters, the converter populates `result.properties` directly.

CVSS bands map to Brik buckets:

| CVSS    | Bucket   |
|---------|----------|
| >= 9.0  | critical |
| >= 7.0  | high     |
| >= 4.0  | medium   |
| > 0     | low      |
| 0 / N/A | info     |

#### Tool-native severity (`lib/transverse/severity.sh`)

`severity.normalize <tool> <tool_severity>` maps a tool-native severity to
the canonical 5-bucket Brik scale `{critical, high, medium, low, info}`.
`severity.is_tool_blocking <tool> <tool_severity>` returns `true` when
the tool itself treats the finding as blocking by default.

| Tool          | Severity (tool-native)     | Bucket   | Blocking |
|---------------|----------------------------|----------|----------|
| eslint        | `error` / `2`              | high     | yes      |
| eslint        | `warn` / `warning` / `1`   | low      | no       |
| eslint        | `off` / `0` / other        | info     | no       |
| ruff          | `error` / `E.*` / `F.*`    | high     | yes      |
| ruff          | `warning` / `W.*` / `I.*`  | low      | no       |
| ruff          | `info` / `note` / other    | info     | no       |
| checkstyle    | `error`                    | high     | yes      |
| checkstyle    | `warning`                  | low      | no       |
| checkstyle    | `info` / `ignore`          | info     | no       |
| dotnet-format | `error`                    | high     | yes      |
| dotnet-format | `warning`                  | low      | no       |
| dotnet-format | `info` / `silent` / `hidden` / `suggestion` | info | no |
| semgrep       | `ERROR`                    | high     | yes      |
| semgrep       | `WARNING`                  | medium   | no       |
| semgrep       | `INFO`                     | info     | no       |
| grype         | `Critical`                 | critical | yes      |
| grype         | `High`                     | high     | yes      |
| grype         | `Medium`                   | medium   | no       |
| grype         | `Low`                      | low      | no       |
| grype         | `Negligible` / `Unknown`   | info     | no       |
| osv-scanner   | `CRITICAL`                 | critical | yes      |
| osv-scanner   | `HIGH`                     | high     | yes      |
| osv-scanner   | `MODERATE`                 | medium   | no       |
| osv-scanner   | `LOW`                      | low      | no       |
| gitleaks      | any (no native scale)      | high     | yes      |

Unknown tools fall back to the SARIF level vocabulary
(`error|warning|note|none`) and the canonical bucket names. Empty inputs
collapse to `info` / non-blocking. The module is pure (no IO, no jq) so
it is safe to invoke from any pipeline hook.

#### Tool resolution (`lib/transverse/tool_resolver.sh`)

`tool_resolver.resolve <tool>` walks three layers in priority order and
emits a JSON descriptor `{path, version, provenance}`. Provenance is one
of `project`, `image`, `bundled`, `missing`.

| Priority | Source                                            | Provenance |
|----------|---------------------------------------------------|------------|
| 1        | `<BRIK_WORKSPACE>/node_modules/.bin/<tool>`       | `project`  |
| 2        | `command -v <tool>` (current `$PATH`)             | `image`    |
| 3        | `<BRIK_HOME>/tools/<tool>`                        | `bundled`  |
| 4        | not found anywhere                                | `missing`  |

Version detection is best-effort: the resolver invokes `<path> --version`
(then `-v` as a fallback), strips ANSI sequences, and keeps the first
dotted numeric token from the first line. Silent tools or missing
binaries report `version=unknown`.

`tool_resolver.is_available <tool>` returns `true` / `false` without
running `--version`, for hot paths where only existence matters.

### Per-stage artifacts layout

Each stage that emits findings writes two files side-by-side:

```
brik-artifacts/<stage>/
  <tool>.sarif      -- raw output from the tool (preserved for audit)
  findings.sarif    -- after apply_policy: same results, with
                       Brik-managed entries appended to result.suppressions[]
```

The notify stage produces three pipeline-level artifacts:

```
brik-artifacts/
  aggregate.sarif            -- multi-runs SARIF: one runs[] entry per stage source
  gl-sast-report.json        -- GitLab non-Ultimate report (vulnerabilities[])
  aggregate-report.{md,json} -- pipeline report with new sections:
                                Active policy / Failing / Ignored / Expiring soon
```

### Knobs

| Variable                              | Default      | Effect |
|---------------------------------------|--------------|--------|
| `quality.findings.policy`             | `pragmatic`  | Active built-in preset. |
| `BRIK_POLICY_URL`                     | unset        | Fetches the DSI policy at init; fail-closed when unreachable. |
| `BRIK_SECURITY_SEVERITY_THRESHOLD`    | `high`       | Severity floor used by `apply_policy`. |
| `BRIK_FINDINGS_EXPIRING_SOON_DAYS`    | `30`         | Window for `findings.expiring_soon` warnings at init. |
| `BRIK_POLICY_CACHE_PATH`              | `${BRIK_WORKSPACE}/brik-artifacts/.policy.cache.json` | Compiled-policy cache location. |

### Expiring-soon notice

When `BRIK_POLICY_URL` is set, the init stage automatically calls
`findings.expiring_soon` and surfaces every allowlist entry whose
`expires` falls within `BRIK_FINDINGS_EXPIRING_SOON_DAYS`. The notice is
visible (logged + recorded under `business.policy_expiring_soon`) but
non-blocking, so DSI sees the upcoming churn before it bites.

### Operational guide

For DSI-side documentation -- writing `brik-policy.yml`, deploying
`BRIK_POLICY_URL`, debugging the compiled cache -- see
[`docs/policy.md`](policy.md).
