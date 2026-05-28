# Transverse Contracts (v1)

Unlike the other domain notions, the transverse notion has **no I/O
artifact** to schematise. Its public functions (`lib/transverse/*.sh` +
sub-directories) are pure helpers consumed by every other notion. The L0
contract here is a set of **static code invariants** declared in
[`docs/internals/layout.md`](../internals/layout.md#invariants) and
verified by `brik/spec/contracts/transverse_contract_spec.sh` via grep /
file checks.

## The 7 layout.md invariants

| # | Invariant | Owner | Status |
|---|---|---|---|
| 1 | No indirect expansion `${!var}` outside `lib/transverse/env.sh`. All indirect reads go through `transverse.env.resolve_indirect`. | `transverse.env` | **15 violations** in 10 files (cf. follow-up below) |
| 2 | No manual poll loops. The only `while elapsed < timeout; check; sleep` pattern lives in `transverse.wait.until`. Tool-native waits (`argocd app wait --health`, `kubectl rollout status --timeout`) stay as-is. | `transverse.wait` | 0 violations |
| 3 | No duplicated `yq -i` setters. `transverse.yaml.{merge,patch,set_image_tag}` centralizes YAML mutation. | `transverse.yaml` | 0 violations |
| 4 | No duplicated tool registry. `transverse.tools.{register,resolve,exec}` is the single 3-tier registry for all scan modules. | `transverse.tools` | 0 redefinitions |
| 5 | Tool registry vs. binary-path resolution are distinct concerns. `transverse.binary_path` (`binary_path.resolve`, `binary_path.is_available`) is the only binary locator. | `transverse.binary_path` | 0 redefinitions |
| 6 | No `lib/core/` directory. The old dispatcher layer was inlined into the stages and CLI it fed. | architectural | OK (directory absent) |
| 7 | `bin/brik` is a thin bootstrap + dispatcher; `lib/cli/` carries the command logic. | architectural | OK (under the 300-line target) |

## Follow-up: invariant 1 violations

15 `${!var}` violations are distributed across 10 files:

```
lib/pipeline/bootstrap.sh
lib/pipeline/hooks.sh
lib/pipeline/loader.sh
lib/pipeline/pipeline.sh
lib/pipeline/runner-images.sh
lib/pipeline/stage.sh
lib/registry/registry.sh
lib/transverse/conditions.sh
lib/transverse/gating.sh
lib/transverse/secrets.sh
```

Three of the 10 violators are themselves under `lib/transverse/` (conditions, gating, secrets). Each occurrence needs a triage:

- **Refactor**: route through `transverse.env.resolve_indirect` if the
  semantics match (single indirect lookup with `:-default` fallback).
- **Document exception**: amend `layout.md` invariant 1 to whitelist the
  pipeline-internal use cases (hooks, loader guards) when they pre-date
  the env.sh module or have specific semantics (e.g. checking if a flag
  variable is set without reading it).

## How to validate

```bash
# Run the full L0 contract spec (10 schema-based notions + transverse invariants)
cd brik && shellspec spec/contracts/

# Only the transverse invariants
shellspec spec/contracts/transverse_contract_spec.sh
```

When a new invariant is added to `layout.md`, add a matching test in
`transverse_contract_spec.sh` and update the table above.
