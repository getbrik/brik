# cd-multi-target

`node 22` · **CD** · complete reference

> [!NOTE]
> One project deploying to every supported target type, with a staging ->
> production promotion chain.

## When to use this
As a reference for the fields each deploy target needs, and for how a promotion
chain is wired across environments.

## What it configures
- **deploy.environments** one per target: `ssh` (review), `compose` (dev),
  `k8s` (staging), `helm` (production), and `gitops` (canary), each with its
  target-specific fields and a deploy `strategy`.
- **promotion chain** staging `validates_for: production`; production's
  `requires_eligibility: [artifact_validated_for]` gate consumes it.
- **artifacts** a shared `release` channel and an evidence state-repo carrying
  the PromotionJournal.

## Try it
```bash
brik validate --config examples/cd-multi-target/brik.yml
```

## Reference
- [`deploy`](../../docs/reference/configuration/deploy.md) - targets, strategies, gates
- [`artifacts`](../../docs/reference/configuration/artifacts.md) - channels and evidence

> [!TIP]
> `config_ref` lets staging follow its own branch, so an environment-config
> change can redeploy the same digest without cutting a new version.
