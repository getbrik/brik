<p align="center">
  <img src="docs/brik.jpg" alt="Brik">
</p>

<p align="center">
  <b>Portable CI/CD pipelines - configure what, not how. One brik.yml, any platform.</b>
</p>

<p align="center">
  <a href="https://github.com/getbrik/brik/actions/workflows/ci.yml"><img src="https://img.shields.io/github/actions/workflow/status/getbrik/brik/ci.yml?label=CI" alt="CI"></a>
  <a href="https://codecov.io/gh/getbrik/brik"><img src="https://codecov.io/gh/getbrik/brik/graph/badge.svg?token=QMN3W4XI8Y" alt="codecov"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MPL--2.0-blue" alt="License"></a>
</p>

<p align="center">
  <a href="https://github.com/getbrik/brik/issues">Issues</a> -
  <a href="https://github.com/getbrik/briklab">Briklab</a>
</p>

## What is Brik

CI/CD pipelines share the same logic across projects, yet every team rewrites it per
platform. Brik fixes this: write one `brik.yml`, get a production-grade pipeline on
any CI platform.

- **One config, any platform** -- same `brik.yml` works on GitLab CI, Jenkins, GitHub Actions
- **Sensible defaults** -- a 4-line config gets you build, test, lint, and security scanning
- **Hundreds of tests** -- ShellSpec unit tests, ShellCheck linting, kcov coverage

## Quick Start

### Prerequisites

```bash
brew install bash yq jq check-jsonschema
```

### Scaffold a project

```bash
brik init --stack node --platform gitlab
```

This creates a `brik.yml` and a GitLab CI bootstrap file in your project.

### Minimal configuration

```yaml
version: 1
project:
  name: my-app
  stack: node
```

That's it. Push to GitLab and the shared library runs the full pipeline with
stack-appropriate defaults for build, test, lint, and security.

## Pipeline Flow

Every Brik pipeline follows a fixed stage sequence:

```
                                     ┌───────────┐
                                     │  Quality  │
Init ─> Release ─> Build ─> ─────────┤           ├────────> Test ─> Package ─> Deploy ─> Notify
                                     │ Security  │
                                     └───────────┘
                                      (parallel)
```

| Stage | Purpose | Default behavior |
|-------|---------|------------------|
| Init | Setup | Validate config, detect stack, export variables |
| Release | Versioning | Determine version from git tags/commits |
| Build | Compile | Stack-specific build (npm, mvn, pip, dotnet, cargo) |
| Quality | Code quality | Lint, format check, dependency audit, coverage |
| Security | Security scans | Dependency scan, secret scan, container scan |
| Test | Test suite | Stack-specific test runner (jest, junit, pytest, etc.) |
| Package | Artifacts | Docker image build, archives |
| Deploy | Deployment | Kubernetes, cloud, custom targets |
| Notify | Notifications | Slack, email, webhooks |

Users do not define pipeline structure. They configure behavior within each stage
via `brik.yml`.

## Supported Stacks

| Stack | Detection | Build | Test | Lint |
|-------|-----------|-------|------|------|
| **node** | `package.json` | npm/yarn/pnpm | jest/mocha/vitest | eslint |
| **java** | `pom.xml` / `build.gradle` | mvn/gradle | junit | checkstyle |
| **python** | `pyproject.toml` / `setup.py` | pip/poetry/uv/pipenv | pytest | ruff/flake8 |
| **dotnet** | `*.csproj` / `*.sln` | dotnet build | xunit/nunit | dotnet format |
| **rust** | `Cargo.toml` | cargo build | cargo test | clippy |

Stack is auto-detected from project files when not specified in `brik.yml`.

## Configuration (`brik.yml`)

Brik follows a "declare what, not how" philosophy. Only `version` and `project.name`
are required -- everything else has sensible defaults per stack.

Full example (Java/Maven):

```yaml
version: 1

project:
  name: my-java-app
  stack: java

build:
  java_version: "21"
  command: mvn package -DskipTests

test:
  framework: junit

quality:
  enabled: true
  lint:
    tool: checkstyle
    config: checkstyle.xml
    fix: false
  format:
    tool: google-java-format
    check: true
  deps:
    severity: high

security:
  dependency_scan: true
  secret_scan: true
  container_scan: false
```

- JSON Schema: [`schemas/config/v1/brik.schema.json`](schemas/config/v1/brik.schema.json)
- Examples: [`examples/`](examples/) (minimal-node, java-maven, python-pytest, mono-dotnet)
- Full parameter reference: [`docs/reference.md`](docs/reference.md)

## CLI Reference

| Command | Description |
|---------|-------------|
| `brik validate` | Validate `brik.yml` against the JSON Schema |
| `brik doctor` | Check prerequisites (tools, stack detection) |
| `brik init` | Scaffold `brik.yml` and platform bootstrap file |
| `brik run stage <name>` | Execute a pipeline stage locally |
| `brik version` | Print version, schema, and runtime info |
| `brik help` | Print usage information |

Key options:

```bash
brik validate --config path/to/brik.yml
brik doctor --workspace ./my-project
brik init --stack node --platform gitlab
brik init --non-interactive
brik run stage build --config brik.yml --workspace .
```

## Platform Support

| Platform | Status | Integration |
|----------|--------|-------------|
| **GitLab CI** | Functional | Shared library with pipeline template |
| **Jenkins** | PoC | Jenkins Shared Library |
| **GitHub Actions** | Planned | Reusable workflows |

## Architecture

| Layer | Role |
|-------|------|
| **brik.yml** | Project configuration |
| **Shared Library** | Per platform (GitLab, Jenkins, GitHub Actions) |
| **brik-lib** | Reusable CI/CD functions (Bash) |
| **Bash Runtime** | Stage lifecycle, logging, hooks |

For a detailed explanation of the architecture, design principles, stage lifecycle,
and how to extend Brik, see [docs/architecture.md](docs/architecture.md).

## Development

### Prerequisites

```bash
brew install bash yq jq check-jsonschema shellspec shellcheck kcov
```

### Run tests

```bash
# All tests
shellspec

# A specific spec file
shellspec runtime/bash/spec/cli/validate_spec.sh

# With verbose output
shellspec --format documentation

# With coverage (requires kcov)
ulimit -n 1024 && shellspec --kcov
# Report in coverage/index.html
```

Tests are in `runtime/bash/spec/` using [ShellSpec](https://shellspec.info). The `.shellspec` config at the project root sets the shell, spec path, and helper.

> **Note:** `ulimit -n 1024` is required on macOS where the default file descriptor limit is too high for kcov's `dup2()` call. See [kcov#293](https://github.com/SimonKagstrom/kcov/issues/293).

### Validate examples

```bash
# Single file
bin/brik validate --config examples/minimal-node/brik.yml

# All examples
for f in examples/*/brik.yml; do bin/brik validate --config "$f"; done
```

### Lint

```bash
shellcheck bin/brik
```

## Status

- [x] `brik.yml` JSON Schema v1
- [x] Bash Runtime (`stage.run` lifecycle)
- [x] 9 pipeline stages (init, release, build, quality, security, test, package, deploy, notify)
- [x] 5 stacks (node, java, python, dotnet, rust)
- [x] GitLab CI shared library
- [x] CLI (validate, doctor, init, run, version)
- [x] Hundreds of tests (ShellSpec + ShellCheck + kcov)
- [ ] Jenkins shared library
- [ ] GitHub Actions reusable workflows

## Related

- [briklab](https://github.com/getbrik/briklab) - local Docker infrastructure for testing Brik pipelines

## License

[MPL-2.0](LICENSE)
