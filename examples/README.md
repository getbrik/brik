# Brik examples

Each directory is a self-contained `brik.yml` (plus this kind of README). They
are both **user-facing references** and the **schema-validation fixtures** the
test suite runs against (`make validate` + `spec/unit/cli/validate_spec.sh`),
so every file here is guaranteed to validate against
`schemas/config/v1/brik.schema.json`.

## Starters (one stack each)

| Example | Stack | Highlights |
|---|---|---|
| [`minimal-node`](minimal-node/) | node | smallest valid config (auto-detection) |
| [`java-maven`](java-maven/) | java | explicit build command + quality stage |
| [`python-pytest`](python-pytest/) | python | Ruff lint + format |
| [`mono-dotnet`](mono-dotnet/) | dotnet | Release build + dotnet-format |
| [`rust-cargo`](rust-cargo/) | rust | minimal Cargo project |

## Complete configurations (named by what they exercise)

| Example | Demonstrates |
|---|---|
| [`full-ci-pipeline`](full-ci-pipeline/) | every quality + security control, reports, multi-arch package, notify, hooks, planner selection |
| [`publish-registries`](publish-registries/) | every `publish` target (npm/docker/maven/pypi/cargo/nuget) |
| [`cd-channels-promote`](cd-channels-promote/) | candidate -> release channel promotion |
| [`cd-signed-supply-chain`](cd-signed-supply-chain/) | signed evidence + fail-closed deploy gates (digest/attestation/eligibility) |
| [`cd-multi-target`](cd-multi-target/) | every deploy target (ssh/compose/k8s/helm/gitops) + a promotion chain |

## Validate them

```bash
make validate                                  # all examples
bin/brik validate --config examples/<name>/brik.yml   # one
```

## Run a pipeline locally

These directories are **config references** (each is a `brik.yml`, not a runnable
app), so copy the relevant `brik.yml` into a real project of that stack and run
it there. With a container engine (`docker`) available, a bare `brik integrate`
runs the full CI flow on your machine, one container per stage -- no
infrastructure to configure (Brik falls back to a built-in `p-local` referential):

```bash
cd path/to/your-node-project
cp /path/to/brik/examples/minimal-node/brik.yml .
git add -A && git commit -qm "add brik.yml"   # only committed state is run
brik integrate
```

The CD examples (`cd-*`, `publish-registries`) additionally need a real
referential and reachable endpoints. See
[getting-started/local.md](../docs/getting-started/local.md) for the full local
workflow and [concepts/local-execution.md](../docs/concepts/local-execution.md)
for the execution model.
