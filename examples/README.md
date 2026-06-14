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
