# publish-registries

`node` · **CI** · reference

> [!NOTE]
> Every supported publish target in one file -- a shape reference for the
> publish stage.

## When to use this
When you need the exact syntax for a given registry. A real project publishes
to one or two of these, not all six.

## What it configures
- **publish** blocks for npm, Docker, Maven, PyPI, Cargo, and NuGet.
- **package.docker.image** the image the Docker publish pushes.

## Try it
```bash
brik validate --config examples/publish-registries/brik.yml
```

## Reference
- [`publish`](../../docs/reference/configuration/publish.md) - all registry targets
- [`package`](../../docs/reference/configuration/package.md) - the image to publish

> [!TIP]
> Publishing credentials are not set in `brik.yml`: it names only the registry
> (authority and path). The infrastructure referential binds each registry
> endpoint to a credential. See
> [credentials](../../docs/how-to/manage-credentials.md).
