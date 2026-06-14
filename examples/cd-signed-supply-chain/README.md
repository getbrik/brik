# cd-signed-supply-chain

`node 22` · **CD** · complete reference

> [!NOTE]
> Fail-closed, signed continuous delivery.

## When to use this
You ship to production behind a signed supply chain and want every deploy
proven -- digest-pinned, attested, and explicitly authorized -- before it runs.

## What it configures
- **artifacts** `channels.release` and a signed evidence state-repo
  (`evidence.sign: true`).
- **deploy** a production gitops environment whose gates require the full
  chain: `require_digest`, `require_attestation` with
  `expected_builder` / `expected_source`, keyless `verify_identity` /
  `verify_issuer`, and `requires_eligibility: [artifact_authorized_for]`.

## Try it
```bash
brik validate --config examples/cd-signed-supply-chain/brik.yml
```

## Reference
- [`artifacts`](../../docs/reference/configuration/artifacts.md) - channels and evidence store
- [`deploy`](../../docs/reference/configuration/deploy.md) - environments, gates, eligibility

> [!IMPORTANT]
> Attestation says where the artifact comes from; eligibility says where it may
> go. This example requires both.
