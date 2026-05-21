# Brik Configuration Overview

## Declare what, not how

`brik.yml` describes **what** the pipeline should produce, scan, and
deploy. It does not describe **how** the pipeline runs. The fixed flow
(`Init -> Release -> Build -> Lint || SAST || Scan || Test -> Package
-> Container Scan -> Deploy -> Notify`, with the four middle stages
running in parallel after Build) is implemented by the platform-specific
shared libraries; users configure the inputs to that flow, not the flow
itself.

Two consequences:

- A `brik.yml` that runs on GitLab runs identically on Jenkins and
  locally. The shared library handles platform mapping; the user does
  not.
- Removing or reordering pipeline stages is not configurable on
  purpose. Brik's value is the convention, not flexibility.

## Three-tier resolution

Most `brik.yml` knobs follow the same precedence rule when several
sources can provide a value:

| Tier | Source | Example |
|---|---|---|
| 1 | Explicit command in `brik.yml` | `quality.lint.command: "npx eslint --fix ."` |
| 2 | Explicit tool in `brik.yml` | `quality.lint.tool: eslint` |
| 3 | Stack default (auto, from `project.stack`) | `eslint` for `node`, `ruff` for `python` |

Tier 1 always wins. Tier 2 is consulted when Tier 1 is unset. Tier 3 is
the silent fallback when neither is set, derived from the config modules
`lib/transverse/config/<stack>.sh` (`config.<stack>.default`).

The same pattern applies to `build.{command,tool}`, `test.{command,framework}`,
`quality.{format,type_check}.{command,tool}`, and most `security.*.{command,tool}`
fields. When a reference page documents a field, the page calls out the
tier explicitly.

## What is required

Only two fields are required:

```yaml
version: 1
project:
  name: my-app
```

Everything else has a sensible default. `project.stack` is recommended
but optional: when omitted, `stages.init` auto-detects from the workspace
(`package.json` -> node, `pom.xml` -> java, `pyproject.toml` -> python,
`Cargo.toml` -> rust, `*.csproj` -> dotnet).

## Validation

`brik.yml` is validated against
[`schemas/config/v1/brik.schema.json`](../../schemas/config/v1/brik.schema.json)
at two points:

- **Locally** by `brik validate` before you commit.
- **In CI** by `stages.init` at the very start of every pipeline run.

Both call the same primitive (`config.validate_schema` in
`lib/transverse/config.sh`), so a config that passes locally is
guaranteed to pass init in CI.

The validator is `jv` (Go static binary, shipped in `brik-runner-base`).
On dev hosts without `jv`, `check-jsonschema` (Python) is used as a
silent fallback.

## See also

- [Documentation portal](../README.md) - top-level navigation
- [`reference/`](reference/) - one page per `brik.yml` top-level section
- [`stacks/`](stacks/) - editorial guides per stack
- [`schemas/config/v1/brik.schema.json`](../../schemas/config/v1/brik.schema.json) - source of truth
