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
    ref: v0.1.0
    file: '/templates/pipeline.yml'
```

**Pipeline variables** set by the template:

| Variable | Default | Description |
|----------|---------|-------------|
| `BRIK_LIB_REF` | `v0.1.0` | Git ref of the Brik runtime to clone |
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
  java_version: "21"

test:
  framework: junit
  commands:
    unit: mvn test
    integration: mvn verify -Pintegration
    e2e: mvn verify -Pe2e
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
      repo: org/infra
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
  pre_build:
    - echo "preparing build environment"
  post_deploy:
    - ./scripts/smoke-test.sh
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
| `test.command` | string | no | stack default | Test command override (Tier 1). For per-suite override, use `commands.*` instead. |
| `test.framework` | string | no | stack default | Test framework (e.g. `jest`, `junit`, `pytest`). |
| `test.commands.unit` | string | no | derived from framework | Command to run unit tests. |
| `test.commands.integration` | string | no | -- | Command to run integration tests. |
| `test.commands.e2e` | string | no | -- | Command to run end-to-end tests. |

#### `test.coverage`

| Key | Type | Required | Default | Description |
|-----|------|----------|---------|-------------|
| `test.coverage.threshold` | integer | no | `80` | Minimum coverage percentage required (0-100). |
| `test.coverage.report` | string | no | -- | Path to Cobertura XML coverage report. |

---

### `quality`

#### `quality.lint`

| Key | Type | Required | Default | Description |
|-----|------|----------|---------|-------------|
| `quality.lint.enabled` | boolean | no | `true` | Set to `false` to skip lint checks entirely. |
| `quality.lint.command` | string | no | -- | Lint command override (Tier 1). |
| `quality.lint.tool` | string | no | stack default | Lint tool (e.g. `eslint`, `checkstyle`, `ruff`, `clippy`). |
| `quality.lint.config` | string | no | -- | Path to lint configuration file. Exported as `BRIK_QUALITY_LINT_CONFIG` but not yet consumed by the linter. |
| `quality.lint.fix` | boolean | no | `false` | Run the linter in auto-fix mode. |

#### `quality.format`

| Key | Type | Required | Default | Description |
|-----|------|----------|---------|-------------|
| `quality.format.command` | string | no | -- | Format command override (Tier 1). |
| `quality.format.tool` | string | no | stack default | Formatter (e.g. `prettier`, `google-java-format`, `ruff format`, `rustfmt`). |
| `quality.format.check` | boolean | no | `false` | Check mode only (fail if files would be reformatted). |

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
| `publish.cargo.registry` | string | no | `crates-io` | Cargo registry name. |
| `publish.cargo.token_var` | string | no | -- | Environment variable name holding the crates.io API token. |

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
| `repo` | string | no | -- | GitOps infrastructure repository (for `gitops` target). |
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

Each hook is an array of shell commands:

```yaml
hooks:
  pre_build:
    - echo "step 1"
    - ./scripts/prepare.sh
  post_deploy:
    - ./scripts/smoke-test.sh
```

`pre_*` hooks can abort the stage. `post_*` hooks are best-effort and do not
override the stage exit code.

File-based hooks (`.brik/hooks/pre-build.sh`) are also supported and handled by the
Bash Runtime (Layer 0) independently of the `hooks` section in `brik.yml`.

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
1. Project extensions: ${BRIK_PROJECT_DIR}/.brik/lib/core/
2. Organization extensions: BRIK_LIB_EXTENSIONS (colon-separated paths)
3. Standard library: ${BRIK_HOME}/runtime/bash/lib/core/
```
