# cd-channels-promote

`node 22` · **CI + CD** · complete reference

> [!NOTE]
> The candidate -> release promotion model: every build lands in a candidate
> channel; a tag promotes the audited image into an immutable release channel.

## When to use this
You want a two-stage registry flow where releases are promoted -- not rebuilt --
from audited candidates.

## What it configures
- **release** `profile: trunk-based` with separate `candidate` and `release`
  Docker registries.
- **artifacts.channels** both `candidate` and `release` -- declaring both is
  the promotion opt-in.
- **pipeline** `selection.mode: safe` so `promote` runs on the tag pipeline.

## Try it
```bash
brik validate --config examples/cd-channels-promote/brik.yml
```

## Reference
- [`artifacts`](../../docs/reference/configuration/artifacts.md) - channels
- [`release`](../../docs/reference/configuration/release.md) - profile and candidate/release zones

> [!TIP]
> The promote stage copies the image and its signed evidence to the release
> channel; it never rebuilds, so the digest is preserved.
