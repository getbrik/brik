# Registry architecture

```text
                  +-------------------------+
   author edits   |   manifests/*.yml       |
   YAML --------> |   (stacks + stages)     |
                  +-----------+-------------+
                              |
                              | scripts/compile-registry.sh
                              | (yq build -> jq -S -> sha256)
                              v
                  +-------------------------+
                  |   cache/registry.json   |   <- deterministic, checked in
                  +-----------+-------------+
                              |
                              | lib/registry/_loader.sh
                              | (single jq pass at first call)
                              v
                  +-------------------------+
                  |   in-memory associative |
                  |   arrays per stack/stage|
                  +-----------+-------------+
                              |
                              | lib/registry/registry.sh
                              v
                  +-------------------------+
   consumers ---> |   registry.stack.*      |
                  |   registry.stage.*      |
                  +-------------------------+
```

Four layers, decoupled by file formats and one function boundary:

| Layer | Format | Owned by |
|---|---|---|
| Source | YAML | extension author |
| Cache | JSON | compiler |
| Loader | bash assoc. arrays | runtime |
| API | `registry.stack.*` / `registry.stage.*` | consumers |

## Why YAML at author time and JSON at runtime

[ADR-001](../../docs/adr/ADR-001-manifest-format.md) records the
decision. The short version:

- YAML is what humans edit. It supports comments, multi-line strings,
  and reads naturally for the shape of a manifest (nested
  `spec.detect.markers.any`).
- JSON is what the runtime parses. `jq` is in every brik-runner image,
  `yq` is not. End users running `brik run` never have to install `yq`.
- The compiler runs `yq -o=json` then pipes through `jq -S` to get a
  deterministic byte stream. The sha256 of the cache is stable across
  OSes; CI verifies this via `scripts/compile-registry.sh --check`.

## Cache reproducibility contract

`scripts/compile-registry.sh` guarantees that two runs over the same
manifest tree produce byte-identical output:

- key ordering: `jq -S` sorts top-level keys recursively.
- array stability: arrays from `yq` keep author order; `jq -S` does
  not touch them. Manifest fields that need ordering (e.g. stage
  placement) preserve it.
- no timestamps, no working directory paths, no machine-specific data
  baked into the cache.

CI runs `scripts/compile-registry.sh --check`. The job fails if the
committed cache does not match a fresh compile, which prevents drift
between manifests and cache.

## Loader lifecycle

`lib/registry/_loader.sh` reads the cache once per shell, into bash
associative arrays keyed by `<id>`. The loader is invoked lazily by
`registry.use` (the public idempotent entry point) so consumers can
source `registry.sh` cheaply.

Refresh paths:

- `registry.use` -- idempotent; subsequent calls are no-ops.
- `_registry._reset` -- internal, drops the in-memory state. Used in
  ShellSpec to test scenarios where extensions are added.
- `_registry._reload` -- internal, equivalent to `_reset` + `_load`.

The loader is **never** called from production code outside
`registry.*`. Consumers depend on the API, not the cache shape.

## Validator

`lib/registry/_validator.sh` validates each manifest individually
against the JSON schema (`schemas/registry/v1/{stack,stage}.schema.json`)
using `jv`. The validator runs:

- at compile time (`scripts/compile-registry.sh` aborts on invalid
  manifest with the failing path),
- in CI (`shellspec spec/registry/validator_spec.sh`),
- on-demand for extension authors who source the validator directly.

Validation is per-manifest, not per-cache: errors point at the
offending file, which is what the author needs.

## Extension overlay

The compiler supports `BRIK_REGISTRY_EXTENSIONS_DIRS` (colon-separated)
to overlay user-supplied manifests on top of the builtins. See
[`extensions.md`](../operations/extensions.md) for the walkthrough.

Conflict policy: if the same `metadata.id` appears in both a
builtin and an extension, the compile aborts. A future release
introduces explicit overrides; until then, name your stack
unambiguously (`acme-java`, not `java`).

## Stage placement and topological order

Stage manifests declare `spec.placement.{slot, after, before}`. The
compiler resolves these into a total order written into the cache as
`stages.<id>.placement.rank`. `registry.stage.list` returns ids in
ascending rank.

If two stages have conflicting `after`/`before` constraints, the
compiler aborts with the cycle path. This is checked at compile time
once, never at runtime.

## What lives outside the registry

The registry deliberately does **not** carry:

- Stage runtime logic (`lib/stages/*.sh`) -- only references to it
  via `spec.module` / `spec.function`.
- Stack-specific tooling (`lib/stacks/*.sh`) -- only references via
  `spec.module`.
- Site-specific configuration (registry URLs, auth) -- lives in
  `brik.yml` (per project) or platform secrets.

Keeping behavior out of the registry is what lets the same cache feed
GitLab, Jenkins, and local execution without modification.
