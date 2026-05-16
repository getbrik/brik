# Brik Documentation

Brik is a portable CI/CD pipeline. You describe your project in a `brik.yml`
file; Brik runs a fixed pipeline -- build, test, lint, security scans, package,
deploy, notify -- the same way on GitLab CI, Jenkins, and locally. You configure
*what* happens at each stage; you never write pipeline logic.

This is the documentation portal. Pick the section that matches what you need.

```mermaid
flowchart TD
    A["README.md<br/>project showcase"] --> B["docs/README.md<br/>this portal"]
    B --> C["Getting started<br/>install + first pipeline"]
    B --> D["Concepts<br/>how Brik thinks"]
    B --> E["Configuration<br/>brik.yml reference"]
    B --> F["Platforms<br/>GitLab + Jenkins"]
    B --> G["Operations<br/>secrets, policy, reports"]
    B --> H["Internals<br/>extend + contribute"]
```

## Getting started

Install Brik and run your first pipeline.

- [GitLab CI](getting-started/gitlab.md) -- add the pipeline template to a GitLab project
- [Jenkins](getting-started/jenkins.md) -- add the shared library to a Jenkins job
- [Local](getting-started/local.md) -- install the CLI, validate and run pipelines on your machine

## Concepts

How Brik works, and why it is shaped this way.

- [Fixed flow](concepts/fixed-flow.md) -- the 11 stages, their order, the parallel verify group, the quality gate
- [Pipeline context](concepts/pipeline-context.md) -- snapshot vs release, and how that decides fail-fast behavior
- [Business outcome](concepts/business-outcome.md) -- the tech/business two-axis model and the decision matrix
- [Architecture](concepts/architecture.md) -- the 4-layer model and the design principles behind it

## Configuration

The `brik.yml` reference. The JSON Schema is the source of truth; the reference
pages are generated from it.

- [Overview](configuration/overview.md) -- "declare what, not how", three-tier resolution, what is required
- [Reference](configuration/reference/) -- one page per top-level `brik.yml` section
- [Stacks](configuration/stacks/) -- minimum viable `brik.yml` and gotchas per stack

## Platforms

Integrating Brik with a CI platform.

- [GitLab CI](platforms/gitlab.md) -- runner images, pipeline variables, cache relocation, coverage reports
- [Jenkins](platforms/jenkins.md) -- shared library, parameters, Docker agents, variable mapping

## Operations

Running Brik in production: secrets, policy, and the pipeline report.

- [Credentials](operations/credentials.md) -- credential indirection, per-platform secret setup
- [Policy](operations/policy.md) -- the org-wide `brik-policy.yml` (DSI / security teams)
- [Risk management](operations/risk-management.md) -- when and how to accept a finding with traceability
- [Findings](operations/findings.md) -- the SARIF pipeline, presets, severity resolution
- [Pipeline report](operations/pipeline-report.md) -- the `aggregate-report.{json,md,html}` field contract
- [Troubleshooting](operations/troubleshooting.md) -- common failures and their fixes

## Internals

For contributors and advanced integrators.

- [Layout](internals/layout.md) -- the nine domain notions and the `lib/` tree
- [Stage lifecycle](internals/stage-lifecycle.md) -- what `stage.run` does around every stage
- [Extending a stack](internals/extending-stack.md) -- add support for a new language
- [Extending a stage](internals/extending-stage.md) -- add a stage to the fixed flow
- [Development](internals/development.md) -- prerequisites, Makefile targets, running tests
- [Briklab](internals/briklab.md) -- the local end-to-end test infrastructure
