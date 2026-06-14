# Getting Started: Local (CLI)

The `brik` CLI lets you validate `brik.yml`, scaffold a project, and run
pipelines (or single stages) on your own machine, with no CI platform required.

## Install

```bash
# One-liner
curl -fsSL https://raw.githubusercontent.com/getbrik/brik/main/scripts/install.sh | bash

# or Homebrew (macOS / Linux)
brew install getbrik/tap/brik
```

Then check your environment:

```bash
brik doctor
```

Local execution is **containerized**: `brik integrate` and `brik stage` run each
stage in a [brik-images](https://github.com/getbrik/brik-images)
(`ghcr.io/getbrik/brik-runner-*`) container of its runner class -- the same images
the GitLab and Jenkins adapters use. So the host needs only `bash 4+`, `git`,
[`yq`](https://github.com/mikefarah/yq), [`jq`](https://jqlang.github.io/jq/), and
a reachable container engine (`docker`). **The project toolchain lives in the
stack images, not on your machine** -- you do not need node, java, the .NET SDK,
etc. installed to run a pipeline locally.

`brik doctor` checks the core tools and the engine. Its stack-tool report is
informational (handy when you work outside containers); a containerized run does
not depend on it. See [concepts/local-execution.md](../concepts/local-execution.md)
for the full execution model.

## Scaffold a project

```bash
brik init --stack node --platform gitlab --dir ./my-project
```

`brik init` writes a `brik.yml` plus a platform bootstrap file. `--platform`
accepts `gitlab`, `jenkins`, and `github` (the GitHub bootstrap is generated
today even though the reusable GitHub Actions workflows are still in progress).
Add `--non-interactive` to skip the prompts.

## Validate

```bash
brik validate --config brik.yml
```

Validation runs the same JSON Schema check that `stages.init` runs in CI, so a
config that passes locally passes init in CI. See
[configuration/overview.md](../reference/configuration/overview.md#validation).

## Run a pipeline locally

From any committed git project with a `brik.yml`, a bare `brik integrate` runs
the full CI flow -- **no setup**:

```bash
# The full CI pipeline, one container per stage
brik integrate

# A single stage
brik stage build
```

Each stage runs in its runner-class container; `build`/`lint`/`test` need nothing
configured. When no infrastructure referential is set, Brik falls back to a
built-in default (profile `p-local`) so a plain CI run works out of the box -- see
[the referential section](#infrastructure-referential-for-cd-and-signing) for when
you need a real one.

Valid stages for `brik stage`: `init`, `release`, `build`, `lint`, `sast`,
`scan`, `test`, `package`, `container-scan`, `promote`, `deploy`, `notify`.

The opt-in flags (`--with-release`, `--with-package`, `--with-deploy`) enable
the trigger-gated stages; see [fixed flow](../concepts/fixed-flows.md#opt-in-stages-and-triggers).
`--continue-on-error` forces the pipeline to keep going past a failed stage; see
[pipeline context](../concepts/pipeline-context.md#continue_on_error-precedence).
`--dry-run` exports `BRIK_DRY_RUN=true` so that deploy targets, registry pushes,
and release tag creation print what they would do without performing the
destructive action:

```bash
brik stage deploy --dry-run
brik integrate --with-deploy --dry-run
```

The same behaviour can be triggered by exporting `BRIK_DRY_RUN=true` in the
caller shell; the CLI flag is the supported way to surface it.

Two more opt-in flags tune the containerized run (`brik integrate`/`brik stage`):

```bash
brik integrate --platform linux/amd64   # run amd64 images for exact CI arch parity
brik integrate --bind-mount             # mount the project dir live (fast edit/inspect)
```

`--platform` (or `BRIK_LOCAL_PLATFORM`) pins the container architecture; the
default is your host's. `--bind-mount` (or `BRIK_LOCAL_BIND_MOUNT=1`) mounts the
project directory instead of copying the committed state into a volume -- it
**waives** the committed-state isolation (untracked and dirty files become
visible, and outputs land in your project dir). See
[concepts/local-execution.md](../concepts/local-execution.md) for both.

## Infrastructure referential (for CD and signing)

A plain CI run needs **no** referential: Brik falls back to a built-in default
(profile `p-local`). You only need to configure one to `brik deploy`, to publish,
or to sign evidence -- a directory of endpoints, credentials, policies, and trust
material. Scaffold one (it lands in `.brik/infra/` by default) and point
`BRIK_INFRA_DIR` at it:

```bash
brik infra init --profile p-open        # or p-entreprise / p-lab / p-local
export BRIK_INFRA_DIR=.brik/infra
brik deploy --version v1.2.3 --environment staging
```

The CD verbs (`deploy`/`authorize`/`status`) always require an explicit
referential -- they never use the local default. See
[artifact attestation](../concepts/supply-chain.md) for the referential structure
and [credentials](../how-to/manage-credentials.md) for how credentials are resolved.

## CLI reference

| Command | Description |
|---------|-------------|
| `brik validate` | Validate `brik.yml` against the JSON Schema |
| `brik doctor` | Check prerequisites (tools, stack detection) |
| `brik init` | Scaffold `brik.yml` and a platform bootstrap file |
| `brik stage <name>` | Execute a single pipeline stage locally |
| `brik integrate` | Execute the full pipeline locally |
| `brik plan` | Compute the per-stage selection plan (`--explain`, `--mode <safe\|balanced>`, `--validate-only`, `--out`) |
| `brik plan gate <stage>` | Decide run/skip for a stage against the active plan |
| `brik infra` | Infrastructure referential commands (`init` scaffolds an instance, `validate` checks one) |
| `brik authorize` | Grant an artifact version to an environment (promotion journal entry) |
| `brik deploy` | Deploy a version to an environment with attestation verification |
| `brik status` | Report an environment as three layers (journal, desired, live) with drift verdicts |
| `brik extension test <dir>` | Run the contract harness against a Brik extension directory |
| `brik self-update` | Update brik to the latest version |
| `brik self-uninstall` | Remove brik from your system |
| `brik version` | Print version, schema, and runtime info |
| `brik help` | Print usage information |

```bash
brik validate --config path/to/brik.yml --schema path/to/schema.json
brik doctor --workspace ./my-project
brik init --stack node --platform gitlab --dir ./my-project --non-interactive
brik stage build --config brik.yml --workspace .
brik stage deploy --dry-run
brik integrate
brik integrate --continue-on-error --with-release --with-package --with-deploy
brik integrate --with-deploy --dry-run
brik integrate --platform linux/amd64
brik integrate --bind-mount
brik self-update --channel edge --version v0.7.0
brik self-uninstall --force
brik version --verbose
```

## Next steps

- [Configuration overview](../reference/configuration/overview.md): what you can put in `brik.yml`
- [Fixed flow](../concepts/fixed-flows.md): the 12 stages a pipeline runs
- [Development](../contributing/development.md): working on Brik itself
