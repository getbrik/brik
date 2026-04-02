# Brik Architecture

This document explains how Brik works internally. It is intended for contributors,
integrators, and anyone curious about the design decisions behind the project.

For user-facing documentation, see the [README](../README.md).

---

## Why Brik

CI/CD pipelines share the same logic across projects -- build, test, lint, deploy --
yet every team rewrites that logic per platform. Switch from GitLab to GitHub Actions?
Rewrite everything. Add Jenkins? Rewrite again. The business logic is the same; only
the orchestration differs.

Brik solves this by separating concerns:

- **Business logic** lives in portable Bash scripts (build, test, quality, deploy).
- **Orchestration** is handled by thin platform adapters (GitLab templates, Jenkins
  shared library, GitHub Actions workflows).
- **Configuration** is declarative: users write `brik.yml` to say *what* they need,
  not *how* to run it.

One set of CI/CD functions. Any platform. No duplication.

---

## Design Principles

These principles guide every implementation decision in Brik.

### 1. Fixed flow, not custom pipelines

Every Brik pipeline follows the same stage sequence:

```
Init -> Release -> Build -> Quality || Security -> Test -> Package -> Deploy -> Notify
```

Users do not define pipeline structure. They configure behavior within stages.
This ensures consistency, auditability, and predictability across all projects.

### 2. Declarative configuration

`brik.yml` is the only user interface. Users declare their stack, tools, thresholds,
and environments. They never write pipeline logic. Sensible defaults per stack mean
a valid config can be as short as:

```yaml
version: 1
project:
  name: my-app
  stack: node
```

### 3. Bash portability

All CI/CD business logic is implemented in portable Bash scripts. Bash is available
on every CI runner, container, and VM. No compilation step, no runtime dependency
beyond standard Unix tools.

### 4. Thin platform adapters

Shared libraries for each CI platform (GitLab, Jenkins, GitHub Actions) are thin
adapters. Their only job: read `brik.yml`, map the fixed flow to native constructs,
and invoke `stage.run`. No business logic is allowed in shared libraries.

### 5. module.function naming

Public functions use a dotted namespace mirroring the module hierarchy:
`build.node`, `test.run`, `quality.lint`, `deploy.k8s`, `config.get`. This makes
functions self-documenting and avoids name collisions.

### 6. Test everything

Every Bash function has a corresponding ShellSpec test. All source files pass
ShellCheck. Coverage is measured by kcov and must stay at or above 80%. End-to-end
validation runs on briklab (a real GitLab instance).

---

## Architecture: 4 Layers

```
┌─────────────────────────────────────────────────────────┐
│  Layer 3 - brik.yml (project configuration)             │
│  Declares stack, tools, thresholds, environments        │
├─────────────────────────────────────────────────────────┤
│  Layer 2 - Shared Library (per platform)                │
│  Implements the fixed flow, reads brik.yml,             │
│  orchestrates stages via native platform mechanisms     │
├─────────────────────────────────────────────────────────┤
│  Layer 1 - brik-lib (Bash library)                      │
│  Reusable CI/CD business functions                      │
│  build.*, test.*, quality.*, security.*, deploy.*       │
├─────────────────────────────────────────────────────────┤
│  Layer 0 - Bash Runtime (stage.run)                     │
│  Lifecycle, logging, context, hooks, summary            │
└─────────────────────────────────────────────────────────┘
```

**Layer 0 -- Bash Runtime** (`runtime/bash/lib/runtime/`).
The execution framework that wraps every stage. Provides `stage.run` (lifecycle
engine), structured logging, execution context, pre/post hooks, error handling,
and step summary generation. Knows nothing about CI/CD -- it only runs functions
with observability.

**Layer 1 -- brik-lib** (`runtime/bash/lib/core/`).
Reusable CI/CD business functions organized by domain: `build.node`, `build.java`,
`test.run`, `quality.lint`, `quality.coverage`, `security.dependency_scan`, etc.
Each function knows how to perform one CI/CD action for one stack or tool. Layer 1
depends on Layer 0 for logging and context but has no knowledge of any CI platform.

**Layer 2 -- Shared Library** (`shared-libs/<platform>/`).
Thin adapters that bridge CI platforms to the Bash layers. The GitLab shared library
(`shared-libs/gitlab/`) maps the fixed flow to GitLab CI stages and jobs. Jenkins
and GitHub Actions adapters follow the same pattern. Shared libraries read `brik.yml`,
extract configuration, and call `stage.run` for each stage.

**Layer 3 -- brik.yml** (`schemas/config/v1/brik.schema.json`).
The user-facing configuration file. Validated against a JSON Schema. Defines project
name, stack, build/test/quality/security/deploy settings, and environment-specific
overrides. Only `version` and `project.name` are required.

---

## Stage Flow

The pipeline executes 9 stages in a fixed order:

```
                                     ┌───────────┐
                                     │  Quality  │
Init ─> Release ─> Build ─> ─────────┤           ├────────> Test ─> Package ─> Deploy ─> Notify
                                     │ Security  │
                                     └───────────┘
                                      (parallel)
```

| Stage | File | What happens |
|-------|------|--------------|
| Init | `stages/init.sh` | Validate config, detect stack, export variables, check prerequisites |
| Release | `stages/release.sh` | Determine version (semver from tags/commits), set release variables |
| Build | `stages/build.sh` | Compile/build per stack (npm, mvn, pip, dotnet, cargo) |
| Quality | `stages/quality.sh` | Lint, format check, dependency audit, coverage thresholds |
| Security | `stages/security.sh` | Dependency scan, secret scan, container scan (SAST) |
| Test | `stages/test.sh` | Run test suite per stack (jest, junit, pytest, xunit, cargo test) |
| Package | `stages/package.sh` | Build Docker image, create archives, prepare artifacts |
| Deploy | `stages/deploy.sh` | Deploy to target environment (k8s, cloud, custom) |
| Notify | `stages/notify.sh` | Send pipeline results (Slack, email, webhooks) |

Quality and Security run in parallel on GitLab CI (same stage). On other platforms
that support parallelism, the same pattern applies.

---

## Stage Lifecycle (`stage.run`)

Every stage is executed through `stage.run`, which provides a consistent lifecycle.
Source: `runtime/bash/lib/runtime/stage.sh`.

```
stage.run("build", stages.build)
  │
  ├─ context.create            # Create execution context (temp file)
  ├─ stage.create_log_file     # Create dedicated log file
  │
  ├─ hook.pre_stage            # Pre-stage hook (CAN ABORT the stage)
  │    └─ [abort?] --> summary.build --> stage.cleanup --> return
  │
  ├─ stage.with_logging        # Redirect output to log file
  │    └─ stage.execute        # Call the logic function (e.g. stages.build)
  │
  ├─ context.set BRIK_FINISHED_AT
  │
  ├─ hook.on_success           # (best effort, does not override exit code)
  │   OR hook.on_failure
  │
  ├─ hook.post_stage           # Post-stage hook (best effort)
  │
  ├─ summary.build             # Generate stage summary
  ├─ stage.cleanup             # Remove temp files
  │
  └─ return exit_code
```

Key decisions:
- **Never `exit`**: stages return exit codes, they never call `exit` directly.
  This allows the runtime to always run cleanup and summary.
- **Hooks are best-effort**: `on_success`, `on_failure`, and `post_stage` hooks
  use `|| true` -- they cannot override the stage's real exit code.
- **Pre-stage can abort**: `hook.pre_stage` is the only hook that can prevent
  stage execution (e.g., skip conditions, environment gates).
- **Each stage has its own context**: an isolated context file holds stage-specific
  variables (timestamps, config values, results).

---

## Directory Structure

```
brik/
├─ bin/brik                      # CLI (validate, doctor, init, run, version)
├─ runtime/bash/
│  ├─ lib/
│  │  ├─ runtime/                # Layer 0 -- stage.run, logging, hooks, context, errors
│  │  ├─ core/                   # Layer 1 -- brik-lib business functions
│  │  │  ├─ build.sh + build/    #   Dispatchers + stack-specific (node, java, python, docker)
│  │  │  ├─ test.sh  + test/     #   Test runners per stack (node, java, python, rust, dotnet)
│  │  │  ├─ quality.sh + quality/#   Lint, coverage, sast, deps, license, container
│  │  │  ├─ config.sh + config/  #   Config reader + stack defaults
│  │  │  ├─ deploy.sh + deploy/  #   Deploy strategies (k8s)
│  │  │  ├─ security.sh          #   Dependency scan, secret scan
│  │  │  └─ env.sh  git.sh  version.sh  condition.sh
│  │  └─ stages/                 # 9 entry points (init, release, build, quality, ...)
│  └─ spec/                      # ShellSpec tests (mirrors lib/ structure)
├─ shared-libs/                  # Layer 2 -- platform adapters
│  ├─ gitlab/                    #   GitLab CI pipeline template
│  ├─ jenkins/                   #   Jenkins Shared Library (PoC)
│  └─ github/                    #   GitHub Actions (planned)
├─ schemas/config/v1/            # JSON Schema for brik.yml
└─ examples/                     # minimal-node, java-maven, python-pytest, mono-dotnet
```

---

## Adding a Stack

To add support for a new stack (e.g., `go`):

1. **JSON Schema** -- add `go` to the `stack` enum in `schemas/config/v1/brik.schema.json`
   and define any stack-specific properties (e.g., `go_version`).

2. **Build module** -- create `runtime/bash/lib/core/build/go.sh` implementing
   `build.go()` with the standard build logic for the stack.

3. **Test module** -- create `runtime/bash/lib/core/test/go.sh` implementing
   `test.go()` with the stack's test runner.

4. **Config module** -- create `runtime/bash/lib/core/config/go.sh` implementing
   `config.go.defaults()` with sensible defaults for the stack.

5. **Dispatchers** -- add the `go)` case to the dispatchers in `stages/build.sh`,
   `stages/test.sh`, and any other stage that routes by stack.

6. **CLI doctor** -- add Go-specific prerequisite checks to `bin/brik` (doctor command).

7. **Example** -- create `examples/minimal-go/brik.yml` with a minimal config.

8. **Tests** -- add ShellSpec tests for each new module under `spec/core/build/`,
   `spec/core/test/`, and `spec/core/config/`.

9. **Validate on briklab** -- push a Go test project to the briklab GitLab instance
   and verify the full pipeline executes correctly.

---

## Adding a Stage

To add a new stage to the fixed flow (rare -- the flow is intentionally fixed):

1. **Stage entry point** -- create `runtime/bash/lib/stages/<stage>.sh` implementing
   `stages.<stage>()` following the pattern of existing stages.

2. **Shared library template** -- add the stage to `shared-libs/gitlab/templates/pipeline.yml`
   (and other platform adapters).

3. **Pipeline flow** -- add the stage name to the `stages:` list in the GitLab template.

4. **Schema** -- add any stage-specific configuration properties to the JSON Schema.

5. **Tests** -- add ShellSpec tests under `spec/stages/<stage>_spec.sh`.

---

## Test Strategy

Brik uses three levels of testing:

### Unit tests (ShellSpec)

Hundreds of examples covering runtime modules, core library functions, and stage entry points.
Each source file in `lib/` has a corresponding `_spec.sh` file in `spec/`. Tests use
ShellSpec's mocking and assertion framework to test functions in isolation.

### Shared library tests (ShellSpec)

Tests covering the GitLab CI shared library integration. These verify that
the templates correctly read configuration and invoke stage.run.

### End-to-end tests (briklab)

Full pipeline validation on a real GitLab CE instance with a runner and container
registry. E2E tests verify that stages execute in order with real tools and produce
expected artifacts. [Briklab](https://github.com/getbrik/briklab) provides a
production-like environment for validation.

### Tools

| Tool | Purpose |
|------|---------|
| [ShellSpec](https://shellspec.info) | BDD testing framework for Bash |
| [kcov](https://github.com/SimonKagstrom/kcov) | Code coverage measurement |
| [ShellCheck](https://www.shellcheck.net) | Static analysis for Bash scripts |

### CI

GitHub Actions runs two jobs on every push and pull request:
- **lint** -- ShellCheck on all Bash source files
- **test** -- ShellSpec full suite + kcov coverage uploaded to Codecov

---

## Key Architectural Decisions

**Why Bash?** Bash is the only language guaranteed to be available on every CI runner,
container, and VM. No compilation, no runtime installation, no dependency management.
The trade-off is reduced expressiveness -- but CI/CD logic is mostly glue code and
command invocation, which Bash handles well.

**Why a fixed flow?** Custom pipelines create inconsistency across teams and projects.
A fixed flow ensures every project follows the same quality gates, security scans,
and deployment process. Configuration within stages provides the flexibility users need.

**Why thin adapters?** Business logic in platform-specific files means maintaining N
copies of the same logic. Thin adapters push all logic into the portable Bash layer,
so a bug fix or feature addition benefits every platform at once.

**Why JSON Schema?** `brik.yml` validation must be fast, offline, and tool-agnostic.
JSON Schema provides all three. Tools like `check-jsonschema` and `yq` make validation
a single command with clear error messages.
