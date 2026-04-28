# Brik Configuration Reference

`brik.yml` is the single declarative source of truth for a Brik project.
It tells the platform-specific shared libraries **what** to do at each
stage; the fixed pipeline flow itself is not configurable.

This directory documents `brik.yml` along three orthogonal axes.

## By audience

| You are... | Start here |
|-----|-----|
| Evaluating Brik | The 5-line example in [`brik/README.md`](../../README.md#configuration-brikyml) |
| A user on a specific stack | Your stack page under [`stacks/`](#by-stack) |
| Auditing fields, types, defaults | The reference page for the section you care about under [`reference/`](#by-section) |
| Curious about precedence and conventions | [`overview.md`](overview.md) |

## By section

One page per top-level `brik.yml` section. Authoritative for field names,
types, defaults, enums.

- [`project`](reference/project.md) - identity, stack
- [`version`](reference/project.md#version) - schema version (singleton)
- [`release`](reference/release.md) - versioning strategy, changelog, tags
- [`build`](reference/build.md) - build command and tool
- [`test`](reference/test.md) - framework, coverage, reports
- [`quality`](reference/quality.md) - lint, format, type check
- [`security`](reference/security.md) - sast, deps, secrets, license, container, iac
- [`package`](reference/package.md) - docker packaging
- [`publish`](reference/publish.md) - npm, docker, maven, pypi, cargo, nuget
- [`deploy`](reference/deploy.md) - environments, targets, rollout
- [`notify`](reference/notify.md) - slack, email, webhook
- [`hooks`](reference/hooks.md) - inline pre/post stage commands
- [`git`](reference/git.md) - identity used by release and gitops deploy

## By stack

Editorial pages with the minimum viable `brik.yml` per stack and
stack-specific gotchas.

- [`node`](stacks/node.md)
- [`python`](stacks/python.md)
- [`java`](stacks/java.md)
- [`rust`](stacks/rust.md)
- [`dotnet`](stacks/dotnet.md)

## Source of truth

The JSON Schema lives at
[`schemas/config/v1/brik.schema.json`](../../schemas/config/v1/brik.schema.json).
Every reference page is derived from it; the schema is what `jv` (and
`brik validate`, and `stages.init`) check against. If a page disagrees
with the schema, the schema wins and the page is wrong.
