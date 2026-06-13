# `artifacts`

> [!NOTE]
> Named registry channels for the CD flow, and the append-only evidence journal.

**Section:** `artifacts` (optional) &nbsp;·&nbsp; **Schema:** [`brik.schema.json` (properties.artifacts)](../../../schemas/config/v1/brik.schema.json)

## What it is for

`artifacts` connects the two flows. A **channel** is a named registry endpoint an
artifact lives in (for example `release`). CI publishes the image to a channel;
CD resolves a version to a digest in the channel an environment accepts
(`deploy.environments.<env>.accepts_channel`).

The **evidence** sub-section names the state-repo where Brik records the signed
build evidence and the promotion and deployment journals.

## What it does

- **`channels`**: each entry maps a channel name to the registry repository it
  resolves against. A version is resolved as `<registry>:<version>` to
  `<registry>@sha256:<hex>`, so a deploy always pins a digest.
- **`evidence`**: when set, Container Scan commits a BuildEvidence record per
  digest to this repo, and the CD verbs append their promotion and deployment
  journal events here. Credentials are references (`token_var`), never values.

## When it runs

This section is not a stage. It is consumed by the CD flow (resolve, promote,
deploy) and by Container Scan (which writes evidence). See
[supply-chain gates](../../concepts/supply-chain.md).

## How to configure

`artifacts` is optional. With no channels declared the CD flow has nothing to
resolve against; with no evidence repo, attestations are still attached to the
image but no evidence file is committed.

<!-- BEGIN AUTO-GENERATED: quick-reference -->
| Field | Type | Default |
|-------|------|---------|
| `artifacts.channels` | `object` | -- |

- **`artifacts.channels`**

  Named artifact channels. Each key is a channel name; the value declares the registry endpoint that channel resolves against.


### `artifacts.evidence`

State-repo where CI records BuildEvidence for each published digest (evidence/<version>/sha256-<digest>.json). When unset, evidence signing still attaches attestations to the image but no evidence file is committed.

| Field | Type | Default |
|-------|------|---------|
| `artifacts.evidence.repo` | `string` | -- |
| `artifacts.evidence.branch` | `string` | -- |
| `artifacts.evidence.token_var` | `string` | -- |
| `artifacts.evidence.sign` | `boolean` | `false` |

- **`artifacts.evidence.repo`**

  Git URL of the evidence state-repo (append-only, file-per-digest).

- **`artifacts.evidence.branch`**

  Branch to commit evidence on (default: the repo default branch).

- **`artifacts.evidence.token_var`**

  Name of the environment variable holding the write token for the evidence repo (resolved indirectly, never inlined).

- **`artifacts.evidence.sign`**

  When true, sign the evidence commit (git commit -S) in addition to the attestations on the digest.


*Example*

```yaml
artifacts:
  evidence:
    repo: https://git.example.com/orders/evidence.git
    token_var: BRIK_GIT_TOKEN
```

<!-- END AUTO-GENERATED -->

### Examples

A release channel plus a signed evidence journal (the shape the README uses):

```yaml
artifacts:
  channels:
    release:
      registry: registry.example.com/orders/orders-api
  evidence:
    repo: https://git.example.com/orders/evidence.git
    token_var: BRIK_GIT_TOKEN
    sign: true
```

Separate candidate and release channels (build once, promote between them):

```yaml
artifacts:
  channels:
    candidate:
      registry: registry.example.com/orders/orders-api-candidate
    release:
      registry: registry.example.com/orders/orders-api
```

## See also

- [Supply-chain gates](../../concepts/supply-chain.md): how channels and evidence feed the CD gates
- [Data layout](../../concepts/data-layout.md): what the evidence state-repo holds
- [`deploy`](deploy.md): where an environment names the channel it accepts
- [`brik.yml` reference](README.md): all top-level sections
