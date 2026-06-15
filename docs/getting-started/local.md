# Getting Started: Local (CLI)

`brik` runs your CI pipeline, covering validation, build, lint, security scans,
and tests, on your own machine, in the **same containers CI uses**, with no CI
platform and no project toolchain to install. This page walks the real workflow end to end:
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
(`ghcr.io/getbrik/brik-runner-*`) container of its runner class, the same images
the GitLab and Jenkins adapters use. So the host needs only `bash 4+`, `git`,
[`yq`](https://github.com/mikefarah/yq), [`jq`](https://jqlang.github.io/jq/), and
a reachable container engine (`docker`). **The project toolchain lives in the
stack images, not on your machine.** You do not need node, java, the .NET SDK,
etc. installed to run a pipeline locally.

`brik doctor` verifies the core tools and the engine, then reports the detected
stack (its stack-tool checks are informational):

```text
brik doctor - checking prerequisites
======================================

  [OK]      bash 5.3.15(1)-release (>= 4 required)
  [OK]      yq (v4.53.3)
  [OK]      jq (jq-1.8.1)
  [OK]      docker (daemon reachable)
  [OK]      jv
  [OK]      shellcheck

  Detected stack: node (from .)

  [OK]      node (v22.22.3)
  [OK]      npm (10.9.8)

======================================
8 checks passed
```

> [!TIP]
> Every command is self-describing: `brik <command> --help` prints its options
> (this holds for subcommands too, such as `brik infra init --help` and
> `brik plan gate --help`), and `brik help` lists all commands.

## 2. Generate and configure `brik.yml`

Work from a **git project**, and commit your work, because brik runs your
*committed* state (untracked and uncommitted changes do not enter the run), so a
fresh repo needs at least one commit.

```bash
cd my-app
git init && git add -A && git commit -m "initial"   # if not already a repo

brik init --non-interactive
```

`brik init` **generates** a starting `brik.yml` plus a CI bootstrap file. It
auto-detects the stack from your project (`package.json` -> node,
`pom.xml`/`build.gradle` -> java, `pyproject.toml` -> python, `Cargo.toml` ->
rust, `*.csproj` -> dotnet) and writes a `.gitlab-ci.yml` by default (pass
`--platform jenkins` or `--platform github`):

```text
Detected stack: node
Created brik.yml and gitlab bootstrap in .
```

> [!NOTE]
> `brik init` only *generates* a `brik.yml`; it never overwrites one. Run it in a
> project that already has a `brik.yml` and it stops without touching your config:
>
> ```text
> error: brik.yml already exists in .
> ```
>
> So once your `brik.yml` is configured, you skip `init` and go straight to
> `validate`/`plan`/`integrate`. To regenerate from scratch, remove `brik.yml`
> first.

The generated `brik.yml` is intentionally **minimal**, just enough to run the
CI core (`build`, `lint`, `sast`, `scan`, `test`) as-is:

```yaml
# brik.yml that init wrote for a node project
version: 1

project:
  name: "my-app"
  stack: node

test:
  framework: npm
```

For node, when your `package.json` defines a `test` script, init pins
`test.framework: npm` so brik runs `npm test` (your script, such as
`node --test`, `vitest`, or `mocha`) instead of assuming the node default,
`jest`. That keeps
`brik init && brik integrate` green out of the box.

**Then configure it for your pipeline.** The scaffold is a starting point: you
grow `brik.yml` by adding the blocks your pipeline needs, such as `release` for
versioning, `package`/`publish` to build and push a container image, and
`deploy` for CD. For example, adding image packaging and a registry:

```yaml
package:
  docker:
    image: registry.example.com/my-app
    dockerfile: Dockerfile

publish:
  docker:
    registry: registry.example.com
    username_var: BRIK_PUBLISH_DOCKER_USER
    password_var: BRIK_PUBLISH_DOCKER_PASSWORD
```

See the [configuration overview](../reference/configuration/overview.md) for
every block, and [Going further](#going-further-deploy-and-signing-cd) below for
the CD (`deploy`) configuration.

Commit the scaffold (and your edits):

```bash
git add brik.yml .gitlab-ci.yml && git commit -m "add brik"
```

## 3. Validate the config

```bash
brik validate
```

This is the same JSON Schema check `stages.init` runs in CI, so a config that
passes here passes init in CI:

```text
brik.yml is valid
```

A bad value fails fast and points at the exact field (timestamps trimmed):

```text
ERROR  brik  brik.yml schema validation failed (rc=1)
ERROR  brik    schema .../schemas/config/v1/brik.schema.json: ok
ERROR  brik    instance -: failed
ERROR  brik    - at '/project/stack': value must be one of 'node', 'java', 'python', 'dotnet', 'rust'
ERROR  brik  brik.yml is invalid
```

## 4. Preview what will run

```bash
brik plan --explain
```

The planner reports, per stage, **run or skip and why**, the exact plan every
adapter executes. Nothing runs yet; this is a dry preview. The header shows the
pipeline context, mode, and a reproducible fingerprint:

```text
Brik plan (schema v1, brik 0.7.0)
  context      snapshot
  mode         safe
  workspace    /path/to/my-app
  changes      source=none
  fingerprint  53a1915419a2d8095cc6056203c2c81c66783c1e...

─ Stages (abridged)
┌─────────┬──────────┬──────────┬─────────────────────┬──────────────────────────────────────────────────┐
│ ID      │ DECISION │ GATE     │ CODE                │ REASON                                           │
├─────────┼──────────┼──────────┼─────────────────────┼──────────────────────────────────────────────────┤
│ init    │ RUN      │ blocking │ context-match       │ applicable to context [snapshot]                 │
│ build   │ RUN      │ blocking │ context-match       │ applicable to context [snapshot]                 │
│ lint    │ RUN      │ blocking │ context-match       │ applicable to context [snapshot]                 │
│ test    │ RUN      │ blocking │ context-match       │ applicable to context [snapshot]                 │
│ package │ SKIP     │ opt_in   │ opt-in-flag-missing │ the --with-package flag was not passed (opt-in)  │
│ deploy  │ SKIP     │ opt_in   │ opt-in-flag-missing │ the --with-deploy flag was not passed (opt-in)   │
│ notify  │ RUN      │ blocking │ context-match       │ applicable to context [snapshot]                 │
└─────────┴──────────┴──────────┴─────────────────────┴──────────────────────────────────────────────────┘
```

`release` and `promote` skip outside a tagged commit (they require the `release`
context); `package`/`deploy` are opt-in (see `--with-package` / `--with-deploy`).

## 5. Run the pipeline

```bash
brik integrate
```

Each stage runs in its runner-class container, one per stage, in order. **No
infrastructure to configure**: on a bare host with no referential set, brik falls
back to a built-in `p-local` default, so `build`/`lint`/`sast`/`scan`/`test` just
work. That zero-config fallback is the local-host convenience; an orchestrated CI
run and any `deploy` use a configured referential (see below).

```text
─ Pipeline Report
  Pipeline ID   1781516511-1
  Project       my-app
  Platform      local
  Status        SUCCESS
  Duration      1m02s

─ Stages
┌────────────────┬─────────┬──────────┬──────────┐
│ Stage          │ Status  │ Business │ Duration │
├────────────────┼─────────┼──────────┼──────────┤
│ init           │ SUCCESS │ SUCCESS  │ 12s      │
│ release        │ SKIPPED │ N/A      │ -        │
│ build          │ SUCCESS │ SUCCESS  │ 3s       │
│ lint           │ SUCCESS │ SUCCESS  │ 3s       │
│ sast           │ SUCCESS │ SUCCESS  │ 3s       │
│ scan           │ SUCCESS │ SUCCESS  │ 1s       │
│ test           │ SUCCESS │ SUCCESS  │ 2s       │
│ package        │ SKIPPED │ N/A      │ -        │
│ container-scan │ SKIPPED │ N/A      │ -        │
│ promote        │ SKIPPED │ N/A      │ -        │
│ deploy         │ SKIPPED │ N/A      │ -        │
│ notify         │ SUCCESS │ SUCCESS  │ -        │
└────────────────┴─────────┴──────────┴──────────┘

─ Business outcome
  Status        SUCCESS
  Counts        success=12, warning=0, error=0
```

The HTML report lands in `brik-artifacts/aggregate-report.html`. A `WARNING` or
`FAILED` status is a real signal from your project (a failing lint, a missing
test, a vulnerable dependency), not a brik error. Read the per-stage log, fix,
and re-run. The four checks `lint`, `sast`, `scan`, `test` run independently (as
they do in parallel in CI), so one failing does not hide the others' results.

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
  live instead of copying the committed state into a volume. This is fast for
  iterating on edits, but it **waives** the committed-state isolation
  (untracked/dirty files become visible and outputs land in your project dir).
- **`--platform <p>`** (or `BRIK_LOCAL_PLATFORM`) pins the container architecture;
  the default is your host's. A mismatch (for example a cached `amd64` image on an
  `arm64` host) runs under emulation and is slower; docker prints a platform
  warning when that happens.
- **`--dry-run`** (or `BRIK_DRY_RUN=true`) makes deploy targets, registry pushes,
  and release tagging print what they would do without performing it.

See [concepts/local-execution.md](../concepts/local-execution.md) for the full
execution model (volumes, governed mounts, declared divergences from CI).

## Going further: deploy and signing (CD)

The **infrastructure referential** is the adapter-agnostic config tree (endpoints,
credentials, policies, trust material) Brik resolves on every run, locally and in
CI alike; the bare-host `p-local` default above is just its empty form. To
`deploy`, publish to a registry, or sign evidence you configure a real one.
Scaffold it (it lands in `.brik/infra/` by default) and point `BRIK_INFRA_DIR` at
it:

```bash
brik infra init --profile p-open      # or p-entreprise / p-lab / p-local
brik infra validate --dir .brik/infra
export BRIK_INFRA_DIR=.brik/infra
brik deploy --version v1.2.3 --environment staging
```

`brik infra init` reports where the instance landed:

```text
Created a p-open referential instance in .brik/infra
Review the endpoints, then point BRIK_INFRA_DIR (or BRIK_INFRA_REPO) at it
```

The `--profile` flag picks the starting posture: `p-open` (public registry,
keyless signing), `p-entreprise` (self-hosted, OpenBAO-backed), `p-lab` (test
only), or `p-local` (empty). See
[Choose an infrastructure profile](../how-to/choose-infra-profile.md) for what
each wires and how to configure it.

The CD verbs (`deploy`/`authorize`/`status`) **always** require an explicit
referential; they never use the bare-host default. See the
[infrastructure referential reference](../reference/infrastructure-referential.md)
for the document kinds and [credentials](../how-to/manage-credentials.md) for how
credentials resolve.

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

> [!IMPORTANT]
> The two `--platform` flags are unrelated: on `brik init` it selects the CI
> orchestrator (`gitlab`/`jenkins`/`github`); on `brik integrate`/`brik stage` it
> selects the container architecture (`linux/amd64`, ...).

## Next steps

- [Configuration overview](../reference/configuration/overview.md): what you can put in `brik.yml`
- [Local execution model](../concepts/local-execution.md): volumes, mounts, divergences from CI
- [Fixed flow](../concepts/fixed-flows.md): the 12 stages a pipeline runs
- [Development](../contributing/development.md): working on Brik itself
