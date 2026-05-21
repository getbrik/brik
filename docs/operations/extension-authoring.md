# Authoring and validating an extension

This page walks through writing a Brik extension and validating it with
the contract harness exposed by `brik extension test`. If you only want
to *consume* an existing extension, read
[`extensions.md`](extensions.md) instead.

The contract harness is how Brik keeps the registry public API stable:
it asserts that an extension honors the same function-and-reporting
contract every builtin does. Authors run it locally before publishing;
CI runs it as a gate against the merged extension set.

## What `brik extension test` checks

Five checks, all of which must pass for the command to exit 0:

| # | Check | What it verifies |
|---|---|---|
| 1 | Schema | Every `<ext>/stacks/*.yml` validates against `schemas/registry/v1/stack.schema.json`; same for `stages/*.yml`. |
| 2 | API symbols | Every function listed in a manifest's `spec.api.required` is defined somewhere under `<ext>/lib/` or the brik builtin `lib/`. |
| 3 | No-exit | Stage modules under `<ext>/lib/stages/*.sh` contain no top-level `exit ` calls. Stages run inside `stage.run`, which traps non-zero `return` values; an `exit` would skip the orchestrator's finally block. |
| 4 | Compile | `BRIK_REGISTRY_EXTENSIONS_DIRS=<ext> compile-registry.sh` produces a merged cache with no id collision against builtins. |
| 5 | Dry-call | For every function in `spec.api.required`, source `<ext>/lib/`, invoke the function against a minimal workspace fixture, and assert `rc=0` plus at least one `report.record` entry. |

Exit codes:

| rc | Meaning |
|---|---|
| 0 | every check passed |
| 2 | one or more checks failed (`BRIK_EXIT_INVALID_INPUT`) |
| 69 | dependency missing (`jv` / `check-jsonschema` / `yq` / `jq` not on PATH) |

## Extension directory layout

```text
my-extension/
  stacks/
    myteam.yml                <- stack manifest (apiVersion: brik.dev/v1, kind: Stack)
  stages/
    audit.yml                 <- stage manifest (apiVersion: brik.dev/v1, kind: Stage)
  lib/
    stacks/myteam.sh          <- module backing stacks/myteam.yml
    stages/audit.sh           <- module backing stages/audit.yml
```

`stacks/` and `stages/` are independent: an extension can ship one,
the other, or both. `lib/` mirrors the layout for clarity but the
harness sources every `**/*.sh` recursively, so any flat structure works.

## Walkthrough: a custom stack in four steps

### 1. Write the manifest

`my-extension/stacks/myteam.yml`:

```yaml
apiVersion: brik.dev/v1
kind: Stack
metadata:
  id: myteam
  displayName: MyTeam
spec:
  detect:
    markers:
      any: [myteam.toml]
  cache:
    paths: [.myteam-cache]
  runner:
    image: ghcr.io/myorg/brik-runner-myteam
    defaultVersion: "1"
    versions: ["1"]
  api:
    module: stacks.myteam
    required:
      - stacks.myteam.build
      - stacks.myteam.test
```

### 2. Write the module

`my-extension/lib/stacks/myteam.sh`:

```bash
#!/usr/bin/env bash

stacks.myteam.build() {
    # Contract: return 0 on success and record at least one tech.* key.
    # The dry-call harness masks PATH so external tools are not invoked;
    # production code lives behind a `[[ -n "$BRIK_WORKSPACE" ]]` guard
    # or a feature flag if needed for the harness path.
    if ! command -v myteam-build >/dev/null 2>&1; then
        report.record "build" "tech" "status" "skipped"
        report.record "build" "tech" "kind"   "not-applicable"
        return 0
    fi
    myteam-build --workspace "$BRIK_WORKSPACE"
    local rc=$?
    if [[ $rc -eq 0 ]]; then
        report.record "build" "tech" "status" "success"
    else
        report.record "build" "tech" "status" "failure"
        report.record "build" "tech" "exit_code" "$rc"
    fi
    return "$rc"
}

stacks.myteam.test() {
    report.record "test" "tech" "status" "success"
    return 0
}
```

### 3. Run the contract harness

```bash
brik extension test ./my-extension
```

Sample output for a healthy extension:

```text
[brik extension] testing ./my-extension
  [OK]   schema   stacks/myteam.yml
  [OK]   api      stacks/myteam.yml -> stacks.myteam.build
  [OK]   api      stacks/myteam.yml -> stacks.myteam.test
  [OK]   no-exit  stacks/myteam.sh
  [OK]   compile registry merges cleanly
  [OK]   dry-call stacks/myteam.yml -> stacks.myteam.build (rc=0, 1 record entries)
  [OK]   dry-call stacks/myteam.yml -> stacks.myteam.test  (rc=0, 1 record entries)

[brik extension] 7 passed, 0 failed
```

### 4. Wire the extension at runtime

```bash
BRIK_REGISTRY_EXTENSIONS_DIRS=./my-extension scripts/compile-registry.sh
BRIK_LIB_EXTENSIONS=./my-extension/lib brik run pipeline
```

The first call merges the manifest into a fresh registry cache. The
second tells the runtime to source the matching modules at `brik.use`
time.

## Common failure modes

### Function returns non-zero on the happy-path fixture

```text
  [FAIL] dry-call stages/audit.yml -> stages.audit: rc=7 on happy-path fixture
```

The dry-call harness invokes the function against a minimal workspace
(an empty tempdir with a synthetic `brik.yml`). It expects `rc=0`. A
non-zero return on this fixture means the function does not handle the
"no real workspace state" case -- usually a missing input file or a
hard-coded path. Add a guard:

```bash
stages.audit() {
    if [[ ! -d "${BRIK_WORKSPACE}/src" ]]; then
        report.record "audit" "tech" "status" "skipped"
        report.record "audit" "tech" "kind"   "not-applicable"
        return 0
    fi
    # real implementation
}
```

### Function does not record an outcome

```text
  [FAIL] dry-call stages/audit.yml -> stages.audit: no report.record entry on happy-path
```

The contract requires every conformant function to record at least
one `tech.*` key. Without it, the aggregate report has no signal for
the stage and the planner cannot reason about its outcome. Call
`report.record` even on the skip path -- it is what makes a stage
"observable".

### Stage module calls `exit`

```text
  [FAIL] no-exit lib/stages/audit.sh: 12:    exit 1
```

`stage.run` traps `return` codes and runs cleanup hooks (artifact
collection, fragment write). A top-level `exit` short-circuits the
orchestrator: the fragment is lost, the next stage does not see the
error, and the aggregate report misses the record. Replace `exit` with
`return` everywhere in stage modules.

### Manifest id collides with a builtin

```text
  [FAIL] compile registry: collision: stacks id=node in ./my-extension/stacks/node.yml
```

A manifest's `metadata.id` must be unique across the merged registry.
`compile-registry.sh` aborts unconditionally on any id collision --
there is no `metadata.replaces` override and no `brik.lock` escape
hatch. Pick a namespaced id (e.g. `myteam-node`) instead.

## See also

- [extensions.md](extensions.md) -- consuming extensions in a project.
- [`docs/registry/`](../registry/) -- registry author reference.
- [`docs/planning/`](../planning/) -- planner reference (how the
  registry feeds `plan.json`).
