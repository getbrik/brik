# Runner-class registry (image mapping)

`lib/registry/runner_classes.yml` is the single source of truth that maps
each stage's runner *class* to the container image that runs it. Both the
GitLab and the Jenkins adapter consume it identically, so a stage's image
is defined in exactly one place.

## The five classes

```yaml
classes:
  base:
    image: ghcr.io/getbrik/brik-runner-base
    tag: latest
  stack:
    # Dynamic: image computed by the init stage from the project stack
    # (node/python/java/...) and read back from BRIK_CI_IMAGE.
    image_env: BRIK_CI_IMAGE
  analysis:
    image: ghcr.io/getbrik/brik-runner-analysis
    tag: latest
  scanner:
    image: ghcr.io/getbrik/brik-runner-scanner
    tag: latest
  deploy:
    image: ghcr.io/getbrik/brik-runner-deploy
    tag: latest
```

| Class | Kind | Resolves to | Stages |
|---|---|---|---|
| `base` | static | `brik-runner-base:latest` | init, release, notify |
| `stack` | dynamic | stack image (e.g. `brik-runner-node:22`) | build, lint, test, package |
| `analysis` | static | `brik-runner-analysis:latest` | sast |
| `scanner` | static | `brik-runner-scanner:latest` | scan, container-scan |
| `deploy` | static | `brik-runner-deploy:latest` | deploy, promote |

A stage selects its class via `spec.runner.class` in its manifest (see
[manifest-stage.md](../contributing/registry/manifest-stage.md)).

## Static vs dynamic

The four static classes declare an `image` and a `tag`;
`registry.runner_class.image <class>` returns `image:tag`. The `stack`
class declares `image_env: BRIK_CI_IMAGE` instead: the accessor returns
the current value of that environment variable, which the init stage sets
to the project's language-stack image. This keeps the per-project image
(node 22, python 3.13, ...) out of the shared registry while still routing
it through the same accessor.

This is orthogonal to language-stack image *versions*, which are declared
in the stack manifests (`spec.runner.{image,defaultVersion,versions}`, see
[manifest-stack.md](../contributing/registry/manifest-stack.md)). The base image is not a language
stack; `lib/pipeline/runner-images.sh` owns only the last-resort base
fallback (`runner.base_image`, `runner.resolve_stack_or_base`) used before
the init dotenv exists.

## The dotenv contract

The init stage resolves all five classes and publishes them into
`.brik-logs/pipeline.env`:

```text
BRIK_IMG_BASE=ghcr.io/getbrik/brik-runner-base:latest
BRIK_IMG_ANALYSIS=ghcr.io/getbrik/brik-runner-analysis:latest
BRIK_IMG_SCANNER=ghcr.io/getbrik/brik-runner-scanner:latest
BRIK_IMG_DEPLOY=ghcr.io/getbrik/brik-runner-deploy:latest
BRIK_CI_IMAGE=ghcr.io/getbrik/brik-runner-node:22
BRIK_IMG_STACK=ghcr.io/getbrik/brik-runner-node:22
```

- **GitLab** job templates reference `${BRIK_IMG_<CLASS>}` directly in
  their `image:` directive; the dotenv is forwarded via
  `artifacts.reports.dotenv`.
- **Jenkins** reads the same file via `brikReadDotenv` and resolves each
  stage's image with `brikDriver.resolveImage`, which looks up the
  matching `BRIK_IMG_<CLASS>` variable.

## Overriding every image: `BRIK_RUNNER_CLASSES_FILE`

Set `BRIK_RUNNER_CLASSES_FILE` to an alternate copy of
`runner_classes.yml` to supersede every image without editing the bundled
default. Use cases: a registry mirror, an air-gapped environment, or an
e2e stub fleet where every class points at a single no-op image.

```yaml
# my-mirror-classes.yml
classes:
  base:     { image: registry.internal/brik-runner-base,     tag: latest }
  stack:    { image_env: BRIK_CI_IMAGE }
  analysis: { image: registry.internal/brik-runner-analysis, tag: latest }
  scanner:  { image: registry.internal/brik-runner-scanner,  tag: latest }
  deploy:   { image: registry.internal/brik-runner-deploy,   tag: latest }
```

- **GitLab**: set `BRIK_RUNNER_CLASSES_FILE` as a CI/CD variable (FILE
  type, or a path resolvable inside the runner). Init reads it and the
  resolved images flow through the dotenv as usual.
- **Jenkins**: pass `BRIK_RUNNER_CLASSES_FILE` as a build parameter. A
  path relative to the brik library root is resolved to absolute before it
  reaches the stage containers (the library is checked out under
  `${WORKSPACE}@libs/<hash>/`, so a relative value would not resolve from
  a stage container's working directory otherwise).

The stages that *read* the classes file (init, plan) still run on their
own default bootstrap image; the override only affects the images of the
stages that are launched from the resolved map.

## API

| Function | Returns |
|---|---|
| `registry.runner_class.image <class>` | `image:tag` for a static class; `$BRIK_CI_IMAGE` for the dynamic `stack` class. rc=`IO_FAILURE` (classes file missing), `MISSING_DEP` (`yq` absent), `INVALID_INPUT` (unknown class). |

See [api.md](../contributing/registry/api.md) for the full registry API.
