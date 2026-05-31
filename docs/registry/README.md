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
| [`runner-classes.md`](runner-classes.md) | Platform / extension author | The runner-class -> image registry (`runner_classes.yml`), the dotenv contract, and the `BRIK_RUNNER_CLASSES_FILE` override. |

## At a glance

```text
lib/registry/manifests/        <- YAML manifests (author edits these)
  stacks/<id>.yml
  stages/<id>.yml
schemas/registry/v1/           <- JSON Schema 2020-12 (do not edit)
  stack.schema.json
  stage.schema.json
scripts/compile-registry.sh    <- yq + jq + sha256 reproducibility
lib/registry/cache/            <- generated cache (gitignored, not committed)
  registry.json
lib/registry/registry.sh       <- public API (registry.stack.*, registry.stage.*)
lib/registry/_loader.sh        <- eval-cache loader, single jq pass
lib/registry/_validator.sh     <- per-manifest validation via jv
```

You edit YAML; the runtime reads only the compiled JSON cache. The
cache (`cache/registry.json`) is a build artifact: it is gitignored
and `_loader.sh` auto-compiles it on a cache miss, so there is nothing
to commit. End users never run `yq`.

## Versioning

The manifest format is frozen at `apiVersion: brik.dev/v1`: a stable
field contract lets extension authors write manifests once and rely on
them. Breaking changes ship under a parallel `v2` schema kept alongside
`v1` for at least 12 months. The runtime accepts both during the
deprecation window; the cache stores the source `apiVersion` so
consumers can branch when needed.

## Related material

- **Why YAML at author time, JSON at runtime.** YAML is what humans
  edit (comments, multi-line strings, natural nesting); JSON is what
  the runtime parses with `jq`. There are no `kustomize`-style
  overlays -- the compiler merges manifests into one flat cache.
- **Contract testing.** `spec/registry/contract/` enforces the public
  API contract for every registry implementation (builtin +
  extensions), so a function signature cannot change silently.
- [`docs/concepts/architecture.md`](../concepts/architecture.md)
  section "Registry" -- where the registry sits in the broader runtime.
