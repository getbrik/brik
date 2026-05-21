# Extensions: adding a custom stack or stage

Brik's registry was built from the start to be extended. This page
covers the **minimal extension surface** that ships today:

- declare a new stack or stage by dropping a manifest into a directory
  you control,
- point `compile-registry.sh` at that directory via
  `BRIK_REGISTRY_EXTENSIONS_DIRS`,
- ship the matching Bash module alongside the manifest.

What Brik does **not** provide yet:

- a marketplace / discovery mechanism,
- signed manifests or lockfiles (no `brik.lock` enforcement),
- CI allowlists,
- runtime hot-reload.

The decision rationale: until at least one external consumer documents
a real use case, adding distribution machinery would be premature
complexity.

## Anatomy of an extension

An extension is a directory with this layout:

```text
my-extensions/
  stacks/
    <stack-id>.yml          # Stack manifest, valid against
                            # schemas/registry/v1/stack.schema.json
  stages/
    <stage-id>.yml          # Stage manifest, valid against
                            # schemas/registry/v1/stage.schema.json
  lib/                      # Optional: matching Bash modules
    stacks/
      <stack-id>.sh         # Implements stacks.<id>.{build, test, ...}
    stages/
      <stage-id>.sh         # Implements stages.<snake_id>
```

The directory name is yours; only `stacks/` and `stages/` subdirectory
names matter to `compile-registry.sh`.

## Step 1: write the manifest

Stacks and stages use the same JSON Schemas as the builtin manifests
under `lib/registry/manifests/`. Copy a builtin you want to clone, edit
the `metadata.id`, and adjust the spec.

Minimal stack example:

```yaml
# my-extensions/stacks/myteam.yml
apiVersion: brik.dev/v1
kind: Stack
metadata:
  id: myteam                       # ^[a-z][a-z0-9-]*$
  displayName: MyTeam Stack
spec:
  detect:
    markers:
      any: [myteam.toml]           # any one of these files in $workspace
  cache:
    paths: [.myteam-cache]
  runner:
    image: ghcr.io/myteam/brik-runner-myteam
    defaultVersion: "1.0"
    versions: ["1.0", "1.1"]
  api:
    module: stacks.myteam          # path the loader resolves
    required: [stacks.myteam.build]
```

Minimal stage example:

```yaml
# my-extensions/stages/security-audit.yml
apiVersion: brik.dev/v1
kind: Stage
metadata:
  id: security-audit
  displayName: Security Audit
spec:
  module: stages.security_audit
  function: stages.security_audit
  placement:
    slot: verify
    group: verify
    after: [build]
    before: [package]
  runner:
    class: scanner
  gate:
    mode: blocking
    contexts: [snapshot, release]
  api:
    required: [stages.security_audit]
```

Validate manifests before compiling:

```bash
jv brik/schemas/registry/v1/stack.schema.json my-extensions/stacks/myteam.yml
jv brik/schemas/registry/v1/stage.schema.json my-extensions/stages/security-audit.yml
```

## Step 2: compile the registry with the overlay

`BRIK_REGISTRY_EXTENSIONS_DIRS` is a colon-separated list of extension
directories. Builtins come first, then each extension dir in the order
listed.

```bash
BRIK_REGISTRY_EXTENSIONS_DIRS="/path/to/my-extensions" \
  brik/scripts/compile-registry.sh --output brik/lib/registry/cache/registry.json
```

The script:

- merges builtins + extensions into one canonical `registry.json`,
- refuses any `metadata.id` collision with a hard error (a future
  release will introduce `spec.replaces` for explicit overrides),
- emits the sha256 of the cache so CI can detect drift.

## Step 3: ship the Bash module

The manifest's `spec.api.required` list points the loader at the Bash
functions you must provide. For the `myteam` stack:

```bash
# my-extensions/lib/stacks/myteam.sh
stacks.myteam.build() {
    # workspace = $1
    cd "$1"
    myteam build --release
}
```

Make the module discoverable by adding its parent dir to
`BRIK_LIB_EXTENSIONS` (colon-separated, prepended to the search path):

```bash
export BRIK_LIB_EXTENSIONS="/path/to/my-extensions/lib:${BRIK_LIB_EXTENSIONS}"
brik run stage build
```

The loader iterates `BRIK_LIB_EXTENSIONS` in order; the first directory
holding a matching `<notion>/<id>.sh` wins.

## Step 4: detect the extension at runtime

Once both manifest and module are in place, the existing CLI commands
discover them automatically:

```bash
brik doctor                        # reports the runner image of myteam
brik plan --explain                # lists security-audit alongside builtins
brik run stage security-audit      # dispatches to stages.security_audit
```

No code change in `brik/` is required.

## Smoke test (proof of OCP)

The repo ships
[`spec/registry/extensions_spec.sh`](../../spec/registry/extensions_spec.sh)
which writes a temporary extension directory, compiles, and asserts the
custom stack and stage land in the cache. Run it against your local
checkout when iterating:

```bash
shellspec spec/registry/extensions_spec.sh
```

For author-side validation of your own extension (schema, api symbols,
no-exit, compile, dry-call), use `brik extension test` -- see
[extension-authoring.md](extension-authoring.md) for the walkthrough
and the five contract checks it performs.

## Constraints and gotchas

- **No `replaces` yet.** A custom manifest with the same `id` as a
  builtin is refused. Once `brik.lock` lands, explicit replace
  semantics will be reintroduced; for now, fork the builtin.
- **No cycle detection across extensions.** A stage that declares
  `placement.after: [my-other-stage]` works only if `my-other-stage` is
  also resolvable. Builtin cycles are caught by the topological sort in
  `_loader.sh`; extensions inherit the same check.
- **Cache must be re-compiled.** The runtime reads
  `lib/registry/cache/registry.json`. Forgetting to re-run
  `compile-registry.sh` after editing a manifest is the most common
  mistake; the schema-drift CI job catches it before merge.
- **Schema versioning is fixed for 12 months** per ADR-003. Manifests
  written against `apiVersion: brik.dev/v1` keep working for the full
  12-month window.

## Reopening full extension support

Revisit extension distribution when:

- at least one external consumer documents a real use case, AND
- ADR-003 has been in application for 3+ months without re-revision.

The deferred scope covers `brik.lock`, signing, allowlists, and a
discovery mechanism. Until then, the in-repo overlay above is the
contract.
