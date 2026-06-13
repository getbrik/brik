# Declarations

> Your project, the pipeline, the operator knobs, and your infrastructure are
> all schema-validated declarations -- not code you maintain.

**Audience:** users, operators &nbsp;·&nbsp; **Type:** Explanation

## What it is (functionally)

Brik hides none of its behaviour in code you have to read. Everything that
shapes a pipeline is a **declaration you can read, validate, and audit**, and
each is governed by a JSON Schema (draft 2020-12) under `schemas/`:

- **Your project** -- `brik.yml`. The only file you normally write.
- **The pipeline itself** -- YAML manifests in the registry describe the stages,
  the stacks, and the capability providers. You do not script the flow; you
  read how it is assembled.
- **The operator surface** -- one manifest declares every user-facing pipeline
  parameter (its type, default, and which flow it drives), so every platform
  exposes the same knobs.
- **Your infrastructure** -- a referential of declared endpoints, credential
  references, trust material, and policy.

In each case the schema is not documentation *of* the contract; it **is** the
contract.

## Why it matters

- **The document an auditor reads is the document the pipeline obeys.** What is
  a legal TLS posture, what a signing declaration may contain, what a promotion
  grant must carry, which gates an environment can set -- all answered by
  reading a schema, because the same schema is enforced fail-closed at runtime.
- **It cannot drift.** The configuration reference is *generated* from
  `brik.schema.json`; a CI drift check fails the build when the committed docs
  no longer match the schema. To change a contract you change the schema, and
  everything else follows.
- **Unknown fields are errors.** Schemas declare `additionalProperties: false`:
  a misspelled key refuses the document instead of being silently ignored. A
  posture you believe you declared but mistyped fails loudly.
- **References, never values.** Credential documents carry `env://`, `file://`,
  or `bao://` references; a schema pattern rejects a literal secret, so it
  cannot be committed.

## How it works

**Validation is fail-closed, at runtime, on every boundary.** Brik validates
the documents it consumes before acting: `brik.yml` at validate/init, every
referential document at init and deploy, the plan on write, promotion-journal
events on write *and* on read (an invalid event poisons the whole read, never
skipped). The validator chain prefers `jv` (Go) and falls back to
`check-jsonschema` (Python); with neither available the operation fails as a
missing dependency rather than running unvalidated.

**Versioned evolution.** Each family lives in a versioned directory
(`config/v1/`, `report/v1.1/`, ...). A breaking change is a new version
directory consumed explicitly, never a silent mutation. Third-party formats
(SARIF 2.1.0, CycloneDX 1.5) are vendored under `schemas/external/` behind a
checksum, so they cannot drift with a network fetch. Spec campaigns validate
real produced artifacts against the schemas, so a contract break fails the
suite before it ships.

The schema families:

| Family | Governs |
|--------|---------|
| `config/v1` | the project's `brik.yml`; the generated configuration reference derives from it |
| `referential/v1` | the infrastructure referential (one schema per kind: Registry, Signing, Credential, Binding, Policy, ...); TLS posture and credential references validate fail-closed |
| `registry/v1` | the stage, stack, and capability-provider manifests the pipeline is compiled from |
| `plan/v1` | the byte-reproducible per-commit plan, including the mandatory `infra.fingerprint` audit block |
| `state/v1` | PromotionJournal events (the digest is required, which makes grants replay-proof) |
| `policy/v1` | the org-wide policy document (findings posture, `state_repo_protection`) |
| `report/v1`, `report/v1.1`, `stages/v1` | the pipeline report backbone, its per-stage fragments, and stage summaries |
| `execution/v1` | the dotenv contract between stages |
| `findings/v1` | Brik's extensions to SARIF findings |
| `rollout/v1` | the built-in deployment workflow profiles |
| `external/` | pinned third-party formats (SARIF, CycloneDX) |

## Configuration & reference

- The schemas, the source of truth: [`schemas/`](../../schemas/)
- The generated `brik.yml` reference: [reference/configuration](../reference/configuration/README.md)
- The pipeline manifests: [`lib/registry/manifests/`](../../lib/registry/manifests/)
- The operator parameter manifest: [`lib/registry/pipeline-params.yml`](../../lib/registry/pipeline-params.yml)
- The infrastructure referential: [manage credentials](../how-to/manage-credentials.md)

## Related

- [The plan](plan.md) -- the per-commit declaration of what runs
- [Supply-chain gates](supply-chain.md) -- the gates an environment declares
- [Runner classes](runner-classes.md) -- the declared image per stage
- [Configuration overview](../reference/configuration/overview.md) -- "declare what, not how"
