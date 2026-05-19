# Registry reference

Technical reference for the Brik **registry**: the single source of
truth that lists the stacks and stages the runtime supports.

This directory is the **deep reference** for extension authors and
runtime contributors. If you only want a walkthrough of "add a custom
stack in 4 steps", read [`docs/operations/extensions.md`](../operations/extensions.md)
first and come back here when you need the field-by-field details.

## Reading order

| Page | Audience | What it covers |
|---|---|---|
| [`architecture.md`](architecture.md) | Anyone touching `lib/registry/` | How manifests, schemas, compiler, loader, and the public API fit together. |
| [`manifest-stack.md`](manifest-stack.md) | Stack author | Field reference for `lib/registry/manifests/stacks/<id>.yml`. |
| [`manifest-stage.md`](manifest-stage.md) | Stage author | Field reference for `lib/registry/manifests/stages/<id>.yml`. |
| [`api.md`](api.md) | Runtime contributor | The `registry.stack.*` / `registry.stage.*` Bash API consumers call. |

## At a glance

```text
lib/registry/manifests/        <- YAML manifests (author edits these)
  stacks/<id>.yml
  stages/<id>.yml
schemas/registry/v1/           <- JSON Schema 2020-12 (do not edit)
  stack.schema.json
  stage.schema.json
scripts/compile-registry.sh    <- yq + jq + sha256 reproducibility
lib/registry/cache/            <- generated cache (checked in)
  registry.json
lib/registry/registry.sh       <- public API (registry.stack.*, registry.stage.*)
lib/registry/_loader.sh        <- eval-cache loader, single jq pass
lib/registry/_validator.sh     <- per-manifest validation via jv
```

You edit YAML, run `scripts/compile-registry.sh`, commit the refreshed
`cache/registry.json`. The runtime reads only the cache; end users
never run `yq`.

## Versioning

The manifest format is frozen at `apiVersion: brik.dev/v1` per
[ADR-003](../../docs/adr/ADR-003-manifest-versioning.md). Breaking
changes ship under a parallel `v2` schema kept alongside `v1` for at
least 12 months. The runtime accepts both during the deprecation
window; the cache stores the source `apiVersion` so consumers can
branch when needed.

## Related material

- [ADR-001 -- manifest format](../../docs/adr/ADR-001-manifest-format.md)
  -- why YAML at author time, JSON at runtime, no `kustomize`-style
  overlays.
- [ADR-002 -- contract testing](../../docs/adr/ADR-002-contract-testing.md)
  -- how `spec/registry/contract/` enforces the public API contract
  for every registry implementation (builtin + extensions).
- [`docs/concepts/architecture.md`](../concepts/architecture.md)
  section "Registry" -- where the registry sits in the broader runtime.
