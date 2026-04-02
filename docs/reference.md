# Brik Reference

Complete reference for CI platforms, supported stacks, and `brik.yml` configuration.

For architecture and design principles, see [architecture.md](architecture.md).
For a quick overview, see the [README](../README.md).

---

## CI Platforms

| Platform | Status | Integration mechanism | Bootstrap file |
|----------|--------|-----------------------|----------------|
| **GitLab CI** | Functional | Shared library (pipeline template) | `.gitlab-ci.yml` |
| **Jenkins** | PoC | Jenkins Shared Library | `Jenkinsfile` |
| **GitHub Actions** | Planned | Reusable workflows | `.github/workflows/*.yml` |

### GitLab CI

The GitLab shared library is the primary platform adapter. It implements the fixed
flow as native GitLab CI stages and jobs.

**Bootstrap file** (`.gitlab-ci.yml`):

```yaml
include:
  - project: 'brik/gitlab-templates'
    ref: v1
    file: '/templates/pipeline.yml'
```

**Pipeline variables** set by the template:

| Variable | Default | Description |
|----------|---------|-------------|
| `BRIK_VERSION` | `v0.1.0` | Brik version |
| `BRIK_HOME` | `/opt/brik` | Installation directory on runners |
| `BRIK_LOG_DIR` | `/tmp/brik/logs` | Log output directory |
| `BRIK_LOG_LEVEL` | `info` | Log verbosity (debug, info, warn, error) |
| `BRIK_PLATFORM` | `gitlab` | Platform identifier |

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
| `setup.py`, `pyproject.toml` | python |
| `Cargo.toml` | rust |
| `*.csproj`, `*.sln` | dotnet |

### Stack defaults

Each stack comes with sensible defaults for build, test, lint, and format tools.
These apply when the corresponding `brik.yml` key is omitted.

| | **node** | **java** | **python** | **rust** | **dotnet** |
|---|---|---|---|---|---|
| **Build** | `npm run build` | `mvn package -DskipTests` | `pip install .` | `cargo build` | `dotnet build` |
| **Test framework** | jest | junit | pytest | cargo test | xunit |
| **Lint tool** | eslint | checkstyle | ruff | clippy | dotnet-format |
| **Format tool** | prettier | google-java-format | ruff format | rustfmt | dotnet-format |

### Package manager detection

**Node** -- detected from lock files:

| Lock file | Package manager | Install command |
|-----------|-----------------|-----------------|
| `pnpm-lock.yaml` | pnpm | `pnpm install --frozen-lockfile` |
| `yarn.lock` | yarn | `yarn install --frozen-lockfile` |
| `package-lock.json` (or none) | npm | `npm ci` |

**Java** -- detected from build files:

| Build file | Build tool | Default goal |
|------------|------------|--------------|
| `pom.xml` | Maven | `package -DskipTests` |
| `build.gradle` / `build.gradle.kts` | Gradle | `build -x test` |

**Python** -- detected from project files:

| Marker | Package manager | Install command |
|--------|-----------------|-----------------|
| `poetry.lock` or `[tool.poetry]` in `pyproject.toml` | poetry | `poetry install` |
| `Pipfile` | pipenv | `pipenv install` |
| `pyproject.toml` | pip | `pip install -e .` |
| `setup.py` | pip | `pip install .` |

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

quality:
  enabled: true
  lint:
    tool: checkstyle
    config: checkstyle.xml
    fix: false
  format:
    tool: google-java-format
    check: true
  sast:
    tool: semgrep
    ruleset: auto
  deps:
    tool: trivy
    severity: high
  coverage:
    threshold: 80
    report: target/site/cobertura/coverage.xml
  license:
    allowed: MIT,Apache-2.0,BSD-3-Clause
    denied: GPL-3.0
  container:
    image: registry.example.com/my-app:latest
    severity: high

security:
  enabled: true
  dependency_scan: true
  secret_scan: true
  container_scan: false
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

deploy:
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
| `project.root` | string | no | `.` | Relative path to service root (for monorepos). |

---

### `release`

| Key | Type | Required | Default | Description |
|-----|------|----------|---------|-------------|
| `release.strategy` | string | no | `semver` | Release strategy: `semver`, `calver`, `custom`. |
| `release.tag_prefix` | string | no | `v` | Prefix for release tags (e.g. `v1.2.3`). |

---

### `build`

| Key | Type | Required | Default | Description |
|-----|------|----------|---------|-------------|
| `build.command` | string | no | stack default | Build command. Overrides the stack default. |
| `build.node_version` | string | no | -- | Node.js version (e.g. `"20"`). Only for `stack: node`. |
| `build.java_version` | string | no | -- | Java version (e.g. `"21"`). Only for `stack: java`. |
| `build.python_version` | string | no | -- | Python version (e.g. `"3.12"`). Only for `stack: python`. |
| `build.dotnet_version` | string | no | -- | .NET version (e.g. `"8.0"`). Only for `stack: dotnet`. |
| `build.rust_version` | string | no | -- | Rust version (e.g. `"stable"`). Only for `stack: rust`. |

---

### `test`

| Key | Type | Required | Default | Description |
|-----|------|----------|---------|-------------|
| `test.framework` | string | no | stack default | Test framework (e.g. `jest`, `junit`, `pytest`). |
| `test.commands.unit` | string | no | derived from framework | Command to run unit tests. |
| `test.commands.integration` | string | no | -- | Command to run integration tests. |
| `test.commands.e2e` | string | no | -- | Command to run end-to-end tests. |

---

### `quality`

| Key | Type | Required | Default | Description |
|-----|------|----------|---------|-------------|
| `quality.enabled` | boolean | no | `true` | Set to `false` to skip the entire quality stage. |

#### `quality.lint`

| Key | Type | Required | Default | Description |
|-----|------|----------|---------|-------------|
| `quality.lint.tool` | string | no | stack default | Lint tool (e.g. `eslint`, `checkstyle`, `ruff`, `clippy`). |
| `quality.lint.config` | string | no | -- | Path to lint configuration file. |
| `quality.lint.fix` | boolean | no | `false` | Run the linter in auto-fix mode. |

#### `quality.format`

| Key | Type | Required | Default | Description |
|-----|------|----------|---------|-------------|
| `quality.format.tool` | string | no | stack default | Formatter (e.g. `prettier`, `google-java-format`, `ruff format`, `rustfmt`). |
| `quality.format.check` | boolean | no | `false` | Check mode only (fail if files would be reformatted). |

#### `quality.sast`

| Key | Type | Required | Default | Description |
|-----|------|----------|---------|-------------|
| `quality.sast.tool` | string | no | auto-detected | SAST tool: `semgrep`, `sonarqube`, `codeql`. Auto-detects from available tools. |
| `quality.sast.ruleset` | string | no | -- | Ruleset or profile (e.g. `auto`, `p/security-audit`). |

SAST tool auto-detection order: semgrep, trivy, skip.

#### `quality.deps`

| Key | Type | Required | Default | Description |
|-----|------|----------|---------|-------------|
| `quality.deps.tool` | string | no | auto-detected | Dependency scanning tool (e.g. `npm-audit`, `pip-audit`, `trivy`). |
| `quality.deps.severity` | string | no | `high` | Minimum severity that fails the scan: `critical`, `high`, `medium`, `low`. |

Dependency tool auto-detection: npm audit (node), pip-audit/safety (python), trivy (fallback).

#### `quality.coverage`

| Key | Type | Required | Default | Description |
|-----|------|----------|---------|-------------|
| `quality.coverage.threshold` | integer | no | `80` | Minimum coverage percentage required (0-100). |
| `quality.coverage.report` | string | no | auto-detected | Path to Cobertura XML coverage report. |

Report auto-detection paths: `coverage/cobertura-coverage.xml`, `coverage.xml`,
`target/site/cobertura/coverage.xml`, `build/reports/cobertura/coverage.xml`.

#### `quality.license`

| Key | Type | Required | Default | Description |
|-----|------|----------|---------|-------------|
| `quality.license.allowed` | string | no | -- | Comma-separated list of allowed licenses. |
| `quality.license.denied` | string | no | -- | Comma-separated list of denied licenses. |

License tool auto-detection: license_finder, trivy (fallback).

#### `quality.container`

| Key | Type | Required | Default | Description |
|-----|------|----------|---------|-------------|
| `quality.container.image` | string | no | `<project>:<version>` | Container image to scan. |
| `quality.container.severity` | string | no | `HIGH` | Minimum severity: `critical`, `high`, `medium`, `low`. |

Container scan tool detection: trivy, grype, skip.

---

### `security`

| Key | Type | Required | Default | Description |
|-----|------|----------|---------|-------------|
| `security.enabled` | boolean | no | `true` | Set to `false` to skip all security scans. |
| `security.dependency_scan` | boolean | no | `true` | Scan dependencies for known vulnerabilities. |
| `security.secret_scan` | boolean | no | `true` | Scan codebase for committed secrets/tokens. |
| `security.container_scan` | boolean | no | `false` | Scan Docker image for vulnerabilities. |
| `security.severity_threshold` | string | no | `high` | Minimum severity that fails the stage: `critical`, `high`, `medium`, `low`. |

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

### `deploy`

#### `deploy.environments.<name>`

Each key under `environments` is an environment name (e.g. `staging`, `production`).

| Key | Type | Required | Default | Description |
|-----|------|----------|---------|-------------|
| `when` | string | no | -- | Condition expression: `branch == 'main'`, `tag =~ 'v*'`, CI variables. |
| `target` | string | no | -- | Deployment target: `ssh`, `compose`, `k8s`, `helm`, `gitops`. |
| `namespace` | string | no | -- | Kubernetes namespace (for `k8s` and `helm` targets). |
| `manifest` | string | no | -- | Path to Kubernetes manifests (for `k8s` target). |
| `repo` | string | no | -- | GitOps infrastructure repository (for `gitops` target). |
| `path` | string | no | -- | Path within the GitOps repository for service manifests. |
| `controller` | string | no | -- | GitOps controller: `argocd`, `fluxcd`. |
| `app_name` | string | no | -- | Application name in the GitOps controller. |

---

### `notify`

#### `notify.slack`

| Key | Type | Required | Default | Description |
|-----|------|----------|---------|-------------|
| `notify.slack.channel` | string | no | -- | Slack channel (e.g. `#deployments`). |
| `notify.slack.on` | string[] | no | -- | Events: `failure`, `success`, `always`. |

#### `notify.email`

| Key | Type | Required | Default | Description |
|-----|------|----------|---------|-------------|
| `notify.email.to` | string | no | -- | Recipient address(es), comma-separated. |
| `notify.email.on` | string[] | no | -- | Events: `failure`, `success`, `always`. |

#### `notify.webhook`

| Key | Type | Required | Default | Description |
|-----|------|----------|---------|-------------|
| `notify.webhook.url` | string (URI) | no | -- | Webhook endpoint URL. |
| `notify.webhook.on` | string[] | no | -- | Events: `failure`, `success`, `always`. |

---

### `hooks`

Inline shell commands executed before or after each stage. Available hooks:

| Hook | When it runs |
|------|--------------|
| `pre_init` / `post_init` | Before/after init stage |
| `pre_release` / `post_release` | Before/after release stage |
| `pre_build` / `post_build` | Before/after build stage |
| `pre_quality` / `post_quality` | Before/after quality stage |
| `pre_security` / `post_security` | Before/after security stage |
| `pre_test` / `post_test` | Before/after test stage |
| `pre_package` / `post_package` | Before/after package stage |
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

When a value is not set in `brik.yml`, Brik resolves it through a three-level hierarchy:

```
1. Explicit configuration (brik.yml)        -- highest priority
2. Stack defaults (config/<stack>.sh)        -- applied when key is omitted
3. Global defaults (hardcoded in modules)    -- lowest priority
```

Example for a Node.js project with no `build` section:

```
brik.yml: build.command not set
  --> config.node defaults: "npm run build"
```
