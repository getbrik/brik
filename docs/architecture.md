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
Init -> Release -> Build -> Lint || SAST || Scan || Test -> Package -> Container Scan -> Deploy -> Notify
```

Lint, SAST, Scan, and Test all run **in parallel** after Build (same `verify` stage).
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
`stacks.node.build`, `stacks.node.test`, `verify.lint.run`, `deploy.k8s.run`, `config.get`.
This makes functions self-documenting and avoids name collisions.

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
│  stacks.*, verify.*, deploy.*, pkg.*, rollout.*, transverse.*       │
├─────────────────────────────────────────────────────────┤
│  Layer 0 - Bash Runtime (stage.run)                     │
│  Lifecycle, logging, context, hooks, summary            │
└─────────────────────────────────────────────────────────┘
```

**Layer 0 -- Bash Runtime** (`lib/pipeline/`).
The execution framework that wraps every stage. Provides `stage.run` (lifecycle
engine), structured logging, execution context, pre/post hooks, error handling,
and step summary generation. Knows nothing about CI/CD -- it only runs functions
with observability.

**Layer 1 -- brik-lib** (`lib/{stages,stacks,deployments,rollout,package-managers,transverse,cli}/`).
Reusable CI/CD business functions organized by domain: `stacks.node.build`, `stacks.java.build`,
`verify.lint.run`, `verify.scan.run`, `pkg.npm.publish`, `transverse.wait.until`, `cli.validate.run`, etc.
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

The pipeline executes 11 stages in a fixed order.

```
init ─> release
         └─> build ─┬─> lint ──────────┐
                     ├─> sast ──────────┤ (optional for package/deploy)
                     ├─> scan ──────────┤
                     └─> test ──────────┼─> package ─> container_scan
                                        │                    │ (optional)
                                        └────────────────────┴─> deploy ─> notify
```

Deploy has a **mandatory** dependency on Test and **optional** dependencies on
Package, Container Scan, Lint, SAST, and Scan. Package waits for Test to pass
and for Lint/SAST/Scan to succeed (quality gate).

| Stage | File | What happens |
|-------|------|--------------|
| Init | `stages/init.sh` | Validate config, detect stack, export variables, check prerequisites |
| Release | `stages/release.sh` | Determine version (semver from tags/commits), set release variables |
| Build | `stages/build.sh` | Compile/build per stack (npm, mvn, pip, dotnet, cargo) |
| Lint | `stages/lint.sh` | Lint, format check, type checking |
| SAST | `stages/sast.sh` | Static application security testing, license and IaC scans |
| Scan | `stages/scan.sh` | Dependency audit and secret scan |
| Test | `stages/test.sh` | Run test suite per stack (jest, junit, pytest, xunit, cargo test) |
| Package | `stages/package.sh` | Build Docker image, create archives, publish artifacts |
| Container Scan | `stages/container_scan.sh` | Scan built container images for vulnerabilities |
| Deploy | `stages/deploy.sh` | Deploy to target environment (k8s, helm, gitops, compose, ssh) |
| Notify | `stages/notify.sh` | Send pipeline results (Slack, email, webhooks) |

Lint, SAST, Scan, and Test run in parallel on GitLab CI (same `verify` stage).
On other platforms that support parallelism, the same pattern applies.

---

## Stage Lifecycle (`stage.run`)

Every stage is executed through `stage.run`, which provides a consistent lifecycle.
Source: `lib/pipeline/stage.sh`.

```
stage.run("build", stages.build)
  │
  ├─ banner.stage              # Display stage banner (name + ASCII logo)
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

> For a higher-level view mapping the `lib/` tree to the 8 domain notions, see
> [layout.md](layout.md).

```
brik/
├─ bin/brik                        # Thin CLI dispatcher (~190 lines, delegates to lib/cli/)
├─ lib/                            # Domain-driven layout (Phases 3-5)
│  ├─ pipeline/                    # Notion #6 -- execution engine (stage.run, loader, logging)
│  │  ├─ stage.sh                  #   Lifecycle engine (stage.run)
│  │  ├─ pipeline.sh               #   Full-pipeline orchestrator (pipeline.run)
│  │  ├─ loader.sh                 #   Module loader (brik.use, 3-level resolution)
│  │  ├─ logging.sh                #   Structured logging (log.info, log.error, etc.)
│  │  ├─ context.sh                #   Lifecycle-only context (create, _context._* privates)
│  │  ├─ report.sh                 #   Pipeline report (report.record / render)
│  │  ├─ hooks.sh                  #   Pre/post stage hooks
│  │  ├─ error.sh                  #   Exit codes and error handling
│  │  ├─ summary.sh                #   Stage summary generation
│  │  ├─ banner.sh                 #   Stage banner display
│  │  ├─ tools.sh                  #   Tool requirement checks (pipeline.require_tool)
│  │  ├─ bootstrap.sh              #   Prerequisite installation (yq, jq, stack tools)
│  │  ├─ pipeline-env.sh           #   Pipeline environment propagation
│  │  ├─ runner-images.sh          #   Runner image resolution
│  │  └─ version-info.sh           #   Version and schema exports
│  ├─ cli/                         # CLI command modules (Phase 4.5 Lot 6)
│  │  ├─ helpers.sh                #   brik_print/error/usage_error + _brik_detect_install_method
│  │  ├─ validate.sh               #   cli.validate.run
│  │  ├─ doctor.sh                 #   cli.doctor.run
│  │  ├─ version.sh                #   cli.version.run
│  │  ├─ help.sh                   #   cli.help.run
│  │  ├─ init.sh                   #   cli.init.run (+ scaffold private helpers)
│  │  ├─ run.sh                    #   cli.run.{run,stage,pipeline}
│  │  ├─ self_update.sh            #   cli.self_update.run
│  │  └─ self_uninstall.sh         #   cli.self_uninstall.run
│  ├─ stages/                      # Notion #3 -- pipeline stages
│  │  ├─ init.sh, release.sh, build.sh, test.sh, package.sh
│  │  ├─ lint.sh, scan.sh, sast.sh, container_scan.sh
│  │  ├─ deploy.sh, notify.sh
│  │  └─ verify/                   # Quality + scan umbrella (N7)
│  │     ├─ verify.sh              #   verify.run dispatcher
│  │     ├─ format.sh, lint.sh, type_check.sh
│  │     └─ scan/                  #   Security scans
│  │        ├─ scan.sh             #     verify.scan.run dispatcher
│  │        ├─ container.sh, deps.sh, iac.sh, license.sh, sast.sh, secret.sh
│  │        └─ _scan.sh
│  ├─ stacks/                      # Notion #2 -- per-stack build+test+install_deps
│  │  ├─ node.sh, python.sh, java.sh, rust.sh, dotnet.sh
│  │  ├─ docker.sh                 #   stacks.docker.build (image build)
│  │  └─ _deps.sh                  #   stacks.install_deps dispatcher
│  ├─ transverse/                  # Notion #5 -- cross-cutting helpers
│  │  ├─ git.sh, version.sh, changelog.sh, conditions.sh
│  │  ├─ env.sh                    #   transverse.env.{resolve_indirect,...}
│  │  ├─ secrets.sh                #   transverse.secrets.require_var
│  │  ├─ ssh.sh                    #   transverse.ssh.setup_agent
│  │  ├─ csv.sh                    #   transverse.csv.foreach
│  │  ├─ wait.sh                   #   transverse.wait.until (poll-until-timeout)
│  │  ├─ yaml.sh                   #   transverse.yaml.{merge,patch,set_image_tag}
│  │  ├─ tools.sh                  #   transverse.tools.{register,resolve,exec} (3-tier registry)
│  │  ├─ config.sh
│  │  └─ config/                   #   Per-stack config (node, python, java, rust, dotnet)
│  ├─ deployments/                 # Notion #4 -- deploy targets
│  │  ├─ k8s.sh, helm.sh, compose.sh, ssh.sh
│  │  └─ gitops.sh, argocd.sh
│  ├─ rollout/                     # Notion #8 -- rollout (health, strategy, profile)
│  │  ├─ health.sh, strategy.sh, profile.sh
│  │  └─ data/deploy-profiles/     #   trunk-based.yml, git-flow.yml, github-flow.yml
│  └─ package-managers/            # Notion #7 -- registry publishing
│     └─ npm.sh, pypi.sh, maven.sh, cargo.sh, nuget.sh, docker.sh
├─ spec/                           # ShellSpec tests (mirrors lib/ structure)
├─ shared-libs/                    # Layer 2 -- platform adapters
│  ├─ common/scripts/              #   Shared logic (base-wrapper.sh)
│  ├─ gitlab/                      #   GitLab CI pipeline template
│  ├─ jenkins/                     #   Jenkins Shared Library
│  ├─ local/                       #   Local execution wrapper
│  └─ github/                      #   GitHub Actions (planned)
├─ schemas/config/v1/              # JSON Schema for brik.yml
└─ examples/                       # minimal-node, java-maven, python-pytest, mono-dotnet
```

---

## Adding a Stack

To add support for a new stack (e.g., `go`):

1. **JSON Schema** -- add `go` to the `stack` enum in `schemas/config/v1/brik.schema.json`
   and define any stack-specific properties (e.g., `go_version`).

2. **Build module** -- create `lib/stacks/go.sh` implementing
   `stacks.go.build()` with the standard build logic for the stack.

3. **Test module** -- create `lib/stacks/go.sh` (same file, fused per stack) implementing
   `stacks.go.test_cmd()` (returns the test command) and `stacks.go.test()` (executes it).

4. **Config module** -- create `lib/transverse/config/go.sh` implementing
   `config.go.default()` (sensible defaults), `config.go.export_build_vars()` (export
   stack-specific build variables), and `config.go.validate_coherence()` (cross-field
   validation).

5. **Dynamic dispatch** -- no manual wiring needed. The build and test stages
   (`lib/stages/build.sh`, `lib/stages/test.sh`) use `brik.use "stacks.${stack}"`
   to dynamically load the correct module at runtime. The new `lib/stacks/go.sh`
   is picked up automatically.

6. **Doctor** -- add Go-specific prerequisite checks to `lib/cli/doctor.sh`.

7. **Example** -- create `examples/minimal-go/brik.yml` with a minimal config.

8. **Tests** -- add ShellSpec tests under `spec/stacks/go_spec.sh` and
   `spec/transverse/config/go_spec.sh`.

9. **Validate on briklab** -- push a Go test project to the briklab GitLab instance
   and verify the full pipeline executes correctly.

---

## Adding a Stage

To add a new stage to the fixed flow (rare -- the flow is intentionally fixed):

1. **Stage entry point** -- create `lib/stages/<stage>.sh` implementing
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

Nearly 2000 examples covering runtime modules, core library functions, and stage entry points.
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

GitHub Actions runs three jobs on every push and pull request:
- **lint** -- ShellCheck on all Bash source files
- **test** -- ShellSpec full suite + kcov coverage uploaded to Codecov
- **metrics** -- shellmetrics badge generation (push to main only)

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
JSON Schema provides all three. Tools like `jv` and `yq` make validation
a single command with clear error messages.
