# Getting Started: Local (CLI)

`brik` runs your CI pipeline -- validation, build, lint, security scans, tests --
on your own machine, in the **same containers CI uses**, with no CI platform and
no project toolchain to install. This page walks the real workflow end to end:
from an unconfigured project to a green local pipeline, then day-to-day use.

## 1. Install and check your machine

```bash
# One-liner
curl -fsSL https://raw.githubusercontent.com/getbrik/brik/main/scripts/install.sh | bash

# or Homebrew (macOS / Linux)
brew install getbrik/tap/brik

brik doctor
```

Local execution is **containerized**: `brik integrate` and `brik stage` run each
stage in a [brik-images](https://github.com/getbrik/brik-images)
(`ghcr.io/getbrik/brik-runner-*`) container of its runner class -- the same images
the GitLab and Jenkins adapters use. So the host needs only `bash 4+`, `git`,
[`yq`](https://github.com/mikefarah/yq), [`jq`](https://jqlang.github.io/jq/), and
a reachable container engine (`docker`). **The project toolchain lives in the
stack images, not on your machine** -- you do not need node, java, the .NET SDK,
etc. installed to run a pipeline locally. `brik doctor` verifies the core tools
and the engine (its stack-tool report is informational).

> Every command is self-describing: `brik <command> --help` prints its options,
> and `brik help` lists all commands.

## 2. Add brik to a project

Work from a **git project**, and commit your work -- brik runs your *committed*
state (untracked and uncommitted changes do not enter the run), so a fresh repo
needs at least one commit.

```bash
cd my-app
git init && git add -A && git commit -m "initial"   # if not already a repo

brik init --non-interactive
```

`brik init` auto-detects the stack from your project (`package.json` -> node,
`pom.xml`/`build.gradle` -> java, `pyproject.toml` -> python, `Cargo.toml` ->
rust, `*.csproj` -> dotnet) and writes a `brik.yml` plus a CI bootstrap file
(`.gitlab-ci.yml` by default; pass `--platform jenkins` or `--platform github`).
For node it also pins `test.framework` to match your `package.json` test script,
so the scaffold runs as-is.

```yaml
# brik.yml that init wrote for a node project using `node --test`
version: 1

project:
  name: "my-app"
  stack: node

test:
  framework: npm
```

Commit the scaffold:

```bash
git add brik.yml .gitlab-ci.yml && git commit -m "add brik"
```

## 3. Validate the config

```bash
brik validate
```

This is the same JSON Schema check `stages.init` runs in CI, so a config that
passes here passes init in CI. A bad value points at the exact field:

```text
- at '/project/stack': value must be one of 'node', 'java', 'python', 'dotnet', 'rust'
```

## 4. Preview what will run

```bash
brik plan --explain
```

The planner reports, per stage, **run or skip and why** (pipeline context,
opt-in flags, changed-file impact) -- the exact plan every adapter executes.
Nothing runs yet; this is a dry preview.

```text
─ Stages
│ ID      │ DECISION │ ... │ REASON                                        │
│ build   │ RUN      │     │ applicable to context [snapshot]              │
│ test    │ RUN      │     │ applicable to context [snapshot]              │
│ package │ SKIP     │     │ the --with-package flag was not passed ...    │
│ deploy  │ SKIP     │     │ the --with-deploy flag was not passed ...     │
```

## 5. Run the pipeline

```bash
brik integrate
```

Each stage runs in its runner-class container, one per stage, in order. **No
infrastructure to configure**: with no referential set, brik falls back to a
built-in `p-local` default, so `build`/`lint`/`sast`/`scan`/`test` just work.

```text
─ Pipeline Report
  Status        SUCCESS
│ Stage  │ Status  │ Business │
│ init   │ SUCCESS │ SUCCESS  │
│ build  │ SUCCESS │ SUCCESS  │
│ lint   │ SUCCESS │ SUCCESS  │
│ test   │ SUCCESS │ SUCCESS  │
│ notify │ SUCCESS │ SUCCESS  │
```

A `WARNING` or `FAILED` status is a real signal from your project (a failing
lint, a missing test, a vulnerable dependency), not a brik error -- read the
per-stage log, fix, and re-run. The four checks `lint`, `sast`, `scan`, `test`
run independently (as they do in parallel in CI), so one failing does not hide
the others' results.

## Day-to-day

```bash
brik stage test                       # run a single stage in its container
brik plan --explain                   # preview run/skip without running
brik integrate --bind-mount           # use live files, skip commit+copy (see caveat)
brik stage deploy --dry-run           # print destructive actions instead of doing them
brik integrate --with-package         # add an opt-in stage (also --with-deploy/--with-release)
brik integrate --continue-on-error    # keep going past a failed stage
brik integrate --platform linux/amd64 # run amd64 images for exact CI arch parity
```

- **`--bind-mount`** (or `BRIK_LOCAL_BIND_MOUNT=1`) mounts your project directory
  live instead of copying the committed state into a volume -- fast for iterating
  on edits, but it **waives** the committed-state isolation (untracked/dirty files
  become visible and outputs land in your project dir).
- **`--platform <p>`** (or `BRIK_LOCAL_PLATFORM`) pins the container architecture;
  the default is your host's (a mismatch runs under emulation and is slower).
- **`--dry-run`** (or `BRIK_DRY_RUN=true`) makes deploy targets, registry pushes,
  and release tagging print what they would do without performing it.

See [concepts/local-execution.md](../concepts/local-execution.md) for the full
execution model (volumes, governed mounts, declared divergences from CI).

## Going further: deploy and signing (CD)

CI needs no referential. To `deploy`, publish to a registry, or sign evidence you
configure an **infrastructure referential** -- a directory of endpoints,
credentials, policies, and trust material. Scaffold one (it lands in `.brik/infra/`
by default) and point `BRIK_INFRA_DIR` at it:

```bash
brik infra init --profile p-open      # or p-entreprise / p-lab / p-local
brik infra validate --dir .brik/infra
export BRIK_INFRA_DIR=.brik/infra
brik deploy --version v1.2.3 --environment staging
```

The CD verbs (`deploy`/`authorize`/`status`) **always** require an explicit
referential -- they never use the local default. See
[artifact attestation](../concepts/supply-chain.md) for the referential structure
and [credentials](../how-to/manage-credentials.md) for how credentials resolve.

## CLI reference

Every command accepts `--help`.

| Command | Description |
|---------|-------------|
| `brik validate` | Validate `brik.yml` against the JSON Schema |
| `brik doctor` | Check prerequisites (tools, stack detection) |
| `brik init` | Scaffold `brik.yml` and a platform bootstrap file |
| `brik plan` | Compute the per-stage selection plan (`--explain`, `--mode <safe\|balanced>`, `--validate-only`, `--out`) |
| `brik plan gate <stage>` | Decide run/skip for a stage against the active plan |
| `brik integrate` | Execute the full pipeline locally |
| `brik stage <name>` | Execute a single pipeline stage locally |
| `brik infra` | Infrastructure referential commands (`init` scaffolds an instance, `validate` checks one) |
| `brik authorize` | Grant an artifact version to an environment (promotion journal entry) |
| `brik deploy` | Deploy a version to an environment with attestation verification |
| `brik status` | Report an environment as three layers (journal, desired, live) with drift verdicts |
| `brik promote` | Promote a version between artifact channels (evidence carried) |
| `brik extension test <dir>` | Run the contract harness against a Brik extension directory |
| `brik self-update` | Update brik to the latest version |
| `brik self-uninstall` | Remove brik from your system |
| `brik version` | Print version, schema, and runtime info |
| `brik help` | Print usage information |

```bash
brik init --stack node --platform gitlab --non-interactive   # --platform = orchestrator
brik integrate --platform linux/amd64                        # --platform = container arch
brik integrate --with-deploy --dry-run
brik version --verbose
```

> Note the two unrelated `--platform` flags: on `brik init` it selects the CI
> orchestrator (`gitlab`/`jenkins`/`github`); on `brik integrate`/`brik stage` it
> selects the container architecture (`linux/amd64`, ...).

## Next steps

- [Configuration overview](../reference/configuration/overview.md): what you can put in `brik.yml`
- [Local execution model](../concepts/local-execution.md): volumes, mounts, divergences from CI
- [Fixed flow](../concepts/fixed-flows.md): the 12 stages a pipeline runs
- [Development](../contributing/development.md): working on Brik itself
