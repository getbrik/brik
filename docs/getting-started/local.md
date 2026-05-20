# Getting Started: Local (CLI)

The `brik` CLI lets you validate `brik.yml`, scaffold a project, and run
pipelines (or single stages) on your own machine -- no CI platform required.

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

`brik doctor` reports whether the Brik core tools and your stack tools are
present. The Brik core tools are `bash 4+`,
[`yq`](https://github.com/mikefarah/yq), [`jq`](https://jqlang.github.io/jq/),
and [`jv`](https://github.com/santhosh-tekuri/jsonschema). Stack tools depend on
`project.stack`: `node` needs node + a package manager, `java` needs java +
mvn/gradle, `python` needs python3 + pip/poetry/uv, `rust` needs rustc + cargo,
`dotnet` needs the .NET SDK.

For CI, [brik-images](https://github.com/getbrik/brik-images)
(`ghcr.io/getbrik/brik-runner-*`) ship every prerequisite preinstalled and the
shared library selects the right image automatically.

## Scaffold a project

```bash
brik init --stack node --platform gitlab --dir ./my-project
```

`brik init` writes a `brik.yml` plus a platform bootstrap file. `--platform`
accepts `gitlab`, `jenkins`, and `github` -- the GitHub bootstrap is generated
today even though the reusable GitHub Actions workflows are still in progress.
Add `--non-interactive` to skip the prompts.

## Validate

```bash
brik validate --config brik.yml
```

Validation runs the same JSON Schema check that `stages.init` runs in CI, so a
config that passes locally passes init in CI. See
[configuration/overview.md](../configuration/overview.md#validation).

## Run a pipeline locally

```bash
# A single stage
brik run stage build --config brik.yml --workspace .

# The full pipeline
brik run pipeline --with-release --with-package --with-deploy
```

Valid stages for `brik run stage`: `init`, `release`, `build`, `lint`, `sast`,
`scan`, `test`, `package`, `container-scan`, `deploy`, `notify`.

The opt-in flags (`--with-release`, `--with-package`, `--with-deploy`) enable
the trigger-gated stages; see [fixed flow](../concepts/fixed-flow.md#opt-in-stages-and-triggers).
`--continue-on-error` forces the pipeline to keep going past a failed stage; see
[pipeline context](../concepts/pipeline-context.md#continue_on_error-precedence).
`--dry-run` exports `BRIK_DRY_RUN=true` so that deploy targets, registry pushes,
and release tag creation print what they would do without performing the
destructive action:

```bash
brik run stage deploy --dry-run
brik run pipeline --with-deploy --dry-run
```

The same behaviour can be triggered by exporting `BRIK_DRY_RUN=true` in the
caller shell; the CLI flag is the supported way to surface it.

## CLI reference

| Command | Description |
|---------|-------------|
| `brik validate` | Validate `brik.yml` against the JSON Schema |
| `brik doctor` | Check prerequisites (tools, stack detection) |
| `brik init` | Scaffold `brik.yml` and a platform bootstrap file |
| `brik run stage <name>` | Execute a single pipeline stage locally |
| `brik run pipeline` | Execute the full pipeline locally |
| `brik self-update` | Update brik to the latest version |
| `brik self-uninstall` | Remove brik from your system |
| `brik version` | Print version, schema, and runtime info |
| `brik help` | Print usage information |

```bash
brik validate --config path/to/brik.yml --schema path/to/schema.json
brik doctor --workspace ./my-project
brik init --stack node --platform gitlab --dir ./my-project --non-interactive
brik run stage build --config brik.yml --workspace .
brik run stage deploy --dry-run
brik run pipeline --continue-on-error --with-release --with-package --with-deploy
brik run pipeline --with-deploy --dry-run
brik self-update --channel edge --version v0.6.0
brik self-uninstall --force
brik version --verbose
```

## Next steps

- [Configuration overview](../configuration/overview.md) -- what you can put in `brik.yml`
- [Fixed flow](../concepts/fixed-flow.md) -- the 11 stages a pipeline runs
- [Development](../internals/development.md) -- working on Brik itself
