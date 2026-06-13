# Local execution

Local execution is containerized: on a bare host, `brik integrate`,
`brik stage <name>` and `brik deploy` never run a stage in the host shell.
Each stage executes in a container of its runner class, with the same images,
the same plan gate, and the same gates as the GitLab and Jenkins adapters. The
host needs `bash`, `git`, `jq`, `yq` and a reachable container engine
(`docker`; `brik doctor` checks them), nothing else: the project toolchain
lives in the stack images.

## Execution model

One run = one named workspace volume (`brik-run-<id>`):

1. **Seed**: `.git` is copied into the volume, the volume root is aligned
   on the host uid:gid, and the tracked files are materialized with
   `git checkout -f HEAD`. Only the committed state enters the run:
   untracked files and uncommitted edits never leak in.
2. **Plan**: `brik plan` runs in a base-class container and writes
   `plan.json` onto the volume (`brik integrate --plan <file>` seeds a
   caller-provided plan instead). `--auto-select` is implicit.
3. **Stages**: one container per registry stage, in registry order. The
   plan gate and the stage execute INSIDE the container (the CI job
   contract, replayed). The stack image comes from `BRIK_CI_IMAGE`, posted
   by init into the volume's `pipeline.env`.
4. **Extract**: `.brik-logs/` and `brik-artifacts/` are copied back to
   the host in every outcome.
5. The volume is destroyed on success and kept for inspection on failure.

`brik stage <name>` follows the same lifecycle for a single stage; the
stage's own opt-in flag is fed to the planner, so explicitly asking for an
opt-in stage (package, deploy) does not plan it away; every other gate
applies unchanged. `brik deploy` and `brik status` re-exec the verb inside
a deploy-class container: definition-ref resolution, the deploy gates, the
target actions and the live read-back all run in-container, exactly as in
a CI CD job.

Inside a CI job or a brik-spawned container (`BRIK_LOCAL_CONTAINER=1`),
the verbs execute in-process: the caller is already the execution
environment.

## Governed mounts

Containers run under the host uid:gid with `HOME` redirected to a writable
directory on the volume, a clean environment, and exactly these mounts:

| Mount | Mode | Scope |
|-------|------|-------|
| run volume at `/work` | rw | every container of the run |
| brik runtime at `/opt/brik` | ro | every container |
| referential at `/etc/brik/infra` | ro | when `BRIK_INFRA_DIR` is set |
| docker socket | rw | ONLY stages whose manifest declares `runner.docker` |

Secrets are forwarded by name only (`-e VAR`) for the `env://` references
declared by the referential's credentials; values never appear in the
engine argv. On a Linux host the socket mount adds the socket's gid as a
supplementary group (`root:docker 0660`); Docker Desktop needs nothing.

## Declared divergences from CI

Local execution is the same flow, not the same machine. The known,
accepted differences:

- **Architecture**: images run for the host architecture (arm64 on Apple
  Silicon); CI runners may build amd64. Digests pin content per platform.
- **Network**: stage containers sit on the default bridge. The
  referential's endpoint URLs must be reachable from a container; endpoint
  hosts the HOST resolves through a loopback `/etc/hosts` entry (a
  host-published lab service) are automatically aliased to the host
  gateway with `--add-host`. `localhost` itself is never remapped.
- **Shared engine, no DinD**: the socket talks to the HOST daemon.
  Images built by a stage land in the host image store (tags and build
  cache are shared between runs); a `docker run -v <path>` issued by stage
  code resolves the path on the host, not in the stage container
  (`--volumes-from` is the supported pattern).
- **No OIDC issuer**: keyless signing is unavailable locally. A
  referential that binds a keyless Signing endpoint fails the CI flow at
  entry with a cross-validation error: bind a key or kms backend, or
  declare no Signing endpoint. Verification (the CD verb) is OIDC-free and
  is not gated.
- **Cluster credentials**: the deploy container does not inherit host
  kubeconfigs; targets must be reachable through the referential's
  endpoints and credentials.
