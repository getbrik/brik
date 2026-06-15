# Choose an infrastructure profile

`brik infra init --profile <name>` scaffolds an **infrastructure referential**:
the tree of endpoints, credentials, trust material, and bindings that Brik
resolves at runtime. Every pipeline reads it (the `init` stage validates it and
records its fingerprint in the plan), on every adapter, local, GitLab, and
Jenkins alike. A profile is the *starting point* for that tree, a reference
instance pre-wired for one **infrastructure posture** that you then edit to match
your real infrastructure. For the central role it plays and the consumers that
read it, see the
[infrastructure referential reference](../reference/infrastructure-referential.md).

> [!NOTE]
> A profile is an **infrastructure posture, not an execution location**. The same
> referential mechanism applies whether Brik runs locally or on GitLab/Jenkins.
> Only the *bare local host* gets a zero-config default (the bundled `p-local`);
> an orchestrated CI run always has a referential mounted, and `deploy`,
> publishing, and signing always need a real one. See the
> [infrastructure referential reference](../reference/infrastructure-referential.md)
> for the document kinds and [Supply-chain gates](../concepts/supply-chain.md)
> for how trust material is verified.

Every scaffold is a valid reference instance: it passes `brik infra validate`
unchanged, with placeholder hosts (`*.example`, `*.lab`) and credential
*references* (`env://`, `bao://`, `file://`) that you replace, never inline
secrets.

## The four profiles at a glance

| Dimension | `p-local` | `p-open` | `p-entreprise` | `p-lab` |
|-----------|-----------|----------|----------------|---------|
| Purpose | empty default, CI core only | public open source | self-hosted enterprise | disposable test lab |
| Registry | none | `ghcr.io` (public) | internal Harbor | `nexus.lab` over HTTP |
| TLS posture | n/a | system CA | corporate CA | insecure |
| Git host | none | GitHub | internal GitLab | Gitea over HTTP |
| Secret manager | none | none | OpenBAO | none |
| Signing backend | none | keyless | KMS (OpenBAO) | local file key |
| Transparency log | none | Rekor public | none | none |
| Credential refs | none | `env://` | `bao://` | `env://` + `file://` |
| Attestation | none | `cosign-keyless` | `cosign-kms` | `cosign-key` |
| SLSA Build L2 | n/a | claimable | claimable | not claimable |

In all profiles except `p-local`, evidence commits are signed with SSH
(`evidence-commit-signing: ssh-signing`).

## The profiles in detail

### `p-local`: empty posture, zero setup

The empty posture: no endpoints, no credentials, no signing, so the CI core
(`build`, `lint`, `sast`, `scan`, `test`) needs nothing configured. It is the
materializable twin of the bundled referential Brik falls back to **on a bare
local host** when neither `BRIK_INFRA_DIR` nor `BRIK_INFRA_REPO` is set. An
orchestrated CI run never auto-falls-back: it always has a referential mounted
(see [How each adapter delivers the referential](#how-each-adapter-delivers-the-referential)).

Scaffold it (then extend it) when you want to opt into `package`, `promote`,
`deploy`, or signing: add a `Registry` endpoint, a `Signing` backend, and the
matching credentials. See [Local execution](../concepts/local-execution.md).

### `p-open`: public open-source posture

For projects that publish in the open: a public registry (`ghcr.io`), GitHub as
the git host, **keyless** signing, and a **public** Rekor transparency log.
Credentials are read from environment variables (`env://BRIK_REGISTRY_TOKEN`,
`env://BRIK_GIT_TOKEN`, `env://BRIK_EVIDENCE_SIGNING_KEY`), which your CI platform
provides. Keyless signing makes SLSA Build L2 claimable when the signing
credential is scoped to the signing stage.

### `p-entreprise`: self-hosted enterprise posture

For internal infrastructure behind a corporate CA: an internal registry (Harbor)
and git host (GitLab) with `trust: custom-ca`, an **OpenBAO** secret manager, and
**KMS** signing backed by OpenBAO (`openbao://brik-signing`) with **no** public
transparency log. Credentials are pulled from the secret manager
(`bao://secret/ci/...`). This is the recommended posture for organisations that
keep key material and traffic inside their own network.

### `p-lab`: disposable test lab

For end-to-end test infrastructure only: plain-HTTP services (`trust: insecure`)
and a passphrase-less **file** signing key (`file://trust/cosign.key`) with an
exported `verification_key`. It is legal and runnable but deliberately noisy.

> [!WARNING]
> `p-lab` is never a production reference. The `insecure` TLS posture and the
> on-disk private key exist to make ephemeral test stacks (such as briklab) easy
> to stand up. A `file://` private key cannot claim SLSA Build L2.

## What gets scaffolded

`brik infra init` writes the instance to `.brik/infra/` by default (override with
`--dir`):

```text
.brik/infra/
  referential.yml        # profile id + description
  endpoints/             # Registry, GitHost, Signing, SecretManager, ...
  credentials/           # Credential references (env://, bao://, file://)
  bindings/              # which credential serves which endpoint + capabilities
  trust/                 # signing keys, verification keys, allowed signers
  schemas/               # the v1 referential schemas (for validation)
```

`p-local` is intentionally a single `referential.yml`. The other profiles
pre-populate `endpoints/`, `credentials/`, and one `bindings/` document.

## How to configure a profile

```bash
# 1. Scaffold the posture closest to your target
brik infra init --profile p-entreprise        # writes .brik/infra/

# 2. Edit the endpoints: replace placeholder hosts with real ones
#    (endpoints/registry-*.yml, endpoints/git-host.yml, endpoints/signing.yml)

# 3. Point credential references at the secrets your platform provides
#    (credentials/*.yml: env://NAME, bao://path#field, or file://trust/<file>)

# 4. Drop trust material into trust/ for a file-backed posture
#    (cosign.key / cosign.pub, the evidence signing key, allowed_signers)

# 5. Validate the instance (fail-closed; run it before every commit)
brik infra validate --dir .brik/infra

# 6. Point Brik at it
export BRIK_INFRA_DIR=.brik/infra
brik deploy --version v1.2.3 --environment staging
```

Use `BRIK_INFRA_REPO` instead of `BRIK_INFRA_DIR` to track the referential in its
own git repository (resolved at runtime).

## How each adapter delivers the referential

Whichever orchestrator runs Brik, the referential is mounted into every stage
container at the same path, `/etc/brik/infra` (read-only), so stages behave
identically:

| Adapter | Delivery |
|---------|----------|
| Local | the container runner bind-mounts `BRIK_INFRA_DIR` at `/etc/brik/infra`; on a bare host with nothing set, it falls back to the bundled `p-local` |
| GitLab | the runner is registered with a `/etc/brik/infra` volume (a project-level `BRIK_INFRA_DIR` can select a variant) |
| Jenkins | the shared library discovers the host referential and adds the `/etc/brik/infra` mount to every stage container |

Because the `init` stage validates the referential on every run, a missing or
invalid one fails the pipeline the same way on all three.

This is what makes the referential the **one place a team declares its
infrastructure**: a single posture, authored once, that the orchestrator carries
unchanged into every stage. The same pipeline then behaves identically on a
laptop, on GitLab, and on Jenkins; there is no per-platform infrastructure config
to keep in sync.

**Worked example: briklab.** Brik's own end-to-end lab runs the `p-lab` posture,
and it is the same instance on both orchestrators, not one referential per
platform. The lab does not commit its referential: it is **generated at setup**
by `scripts/lib/setup/infra-referential.sh` (with a KMS-signing variant) into the
lab's runtime `data/` directory, which is git-ignored. The same generated
instance is then handed to both orchestrators at the same path, `/etc/brik/infra`:
the GitLab runner mounts it through its `config.toml` (`scripts/lib/setup/runner.sh`)
and the Jenkins service through `docker-compose.yml`. A scenario opts into the
KMS-signing variant per run with `BRIK_INFRA_DIR=/etc/brik/infra-kms`, on either
platform. To see the shape of a real instance, read those generator scripts (the
`data/` tree itself is not in the repository).

## Field reference

The credential reference schemes (`env://`, `bao://`, `file://`), the signing
backends (`keyless`, `kms`, `key`), and the fields of every endpoint and binding
are documented in the
[infrastructure referential reference](../reference/infrastructure-referential.md).

## Choosing a profile

- Running pipelines locally with no deploy or signing? Stay on the built-in
  default, or scaffold `p-local` and extend it.
- Public project on GitHub plus GHCR? Start from `p-open`.
- Self-hosted registry and git behind a corporate CA, key material in a vault?
  Start from `p-entreprise`.
- Standing up a throwaway end-to-end stack? Start from `p-lab`, and never promote
  its posture to production.

When no profile is an exact fit, pick the closest one and edit it: the profiles
differ only in their endpoint hosts, TLS posture, credential schemes, and signing
backend, all of which you are expected to change.

## Related

- [Credentials](manage-credentials.md): the referential structure and credential indirection
- [Supply-chain gates](../concepts/supply-chain.md): how trust material and attestation are verified
- [Local execution](../concepts/local-execution.md): the built-in default and containerized local mode
- [Configure org policy](configure-org-policy.md): the org-wide policy document in the referential
