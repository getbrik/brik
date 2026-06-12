# Schemas: every contract is declared, versioned and enforced

Everything brik exchanges with the outside world -- project config, the
infrastructure referential, plans, reports, journal events, policies --
is governed by a JSON Schema (draft 2020-12) under `schemas/`. The schema
is not documentation of the contract; it **is** the contract.

## Philosophy

**The schema is the single source of truth.** Human-facing reference docs
are generated from it, never written by hand: the configuration reference
under [docs/configuration/](../configuration/overview.md) is produced from
`schemas/config/v1/brik.schema.json` by `scripts/gen-config-reference.sh`,
and a drift check fails the build when the committed docs no longer match
the schema. To change a contract, you change the schema; everything else
follows.

**Validation is fail-closed, at runtime, on every boundary.** brik
validates the documents it consumes before acting on them: `brik.yml` at
validate/init, every referential document at init and deploy, the plan on
write, promotion-journal events on write AND on read (an invalid event
poisons the whole read, it is never skipped). The validator chain prefers
`jv` (Go) and falls back to `check-jsonschema` (Python); when neither is
available the operation fails as a missing dependency rather than running
unvalidated.

**Unknown fields are errors.** The schemas declare
`additionalProperties: false`: a typo or an unsupported key refuses the
document instead of being silently ignored. A security posture you believe
you declared but misspelled must fail loudly, not degrade.

**Every field justifies itself.** A field that can be derived from other
fields is not added. This keeps the contracts small enough to audit and
prevents two declarations of the same fact from drifting apart.

**References, never values.** Credential documents in the referential carry
`env://`, `file://` or `bao://` references. A schema pattern enforces it:
a literal secret does not validate, so it cannot be committed.

**Versioned evolution.** Each family lives in a versioned directory
(`config/v1/`, `report/v1.1/`, ...). A breaking change is a new version
directory consumed explicitly, never a silent mutation of the existing
contract.

**External formats are pinned.** Third-party schemas (SARIF 2.1.0,
CycloneDX 1.5) are vendored under `schemas/external/` and guarded by a
checksum file, so the contracts brik validates findings and SBOMs against
cannot drift with a network fetch.

**Contracts are regression-tested.** Spec campaigns validate real produced
artifacts (reports, fragments, plans, SARIF, journal events) against the
schemas, so a code change that breaks a contract fails the suite before it
ships.

## The families

| Family | Schema(s) | Governs |
|--------|-----------|---------|
| `config/v1` | `brik.schema.json` | the project's `brik.yml`; the generated configuration reference derives from it |
| `referential/v1` | one schema **per kind** (Registry, GitHost, Signing, SecretManager, ArgoCD, K8sTarget, SshTarget, PackageRegistry, Notification, Credential, Binding, Policy, Referential) | the infrastructure referential documents; TLS posture, credential references and cross-references (bindings, endpoint credentials) validate fail-closed |
| `plan/v1` | `plan.schema.json` | the byte-reproducible per-commit plan, including the mandatory `infra.fingerprint` audit block |
| `state/v1` | `promotion-event.schema.json` | PromotionJournal events (artifact_promoted, validated_for, authorized_for); the digest is required, which is what makes grants replay-proof |
| `policy/v1` | `brik-policy.schema.json` | the org-wide policy document (findings posture, `state_repo_protection`) |
| `findings/v1` | `brik-extensions.schema.json` | brik's extensions to SARIF findings |
| `report/v1`, `report/v1.1` | `aggregate`, `fragment` | the pipeline report backbone and its per-stage fragments |
| `stages/v1` | `stage-summary.schema.json` | per-stage summary artifacts |
| `execution/v1`, `execution-environment/v1` | `pipeline-env`, `wrapper-context` | the dotenv contract between stages and the wrapper context |
| `registry/v1` | `stage`, `stack`, `provider` | the registry manifests stages, stacks and capability providers are compiled from |
| `rollout/v1` | `deploy-profile.schema.json` | built-in deployment workflow profiles |
| `external/` | SARIF 2.1.0, CycloneDX 1.5 (+ `SCHEMAS.sha256`) | pinned third-party formats |

## Why this matters for security and compliance

The schemas are the conformance surface. What an auditor needs to know --
which TLS postures are legal, what a signing declaration can contain, what
a promotion grant must carry to be accepted, which gates an environment can
declare -- is answered by reading a schema, not by reading code. And
because the same schema is enforced fail-closed at runtime, the document
the auditor read is the document the pipeline obeyed.
