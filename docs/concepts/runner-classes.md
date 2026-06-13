# Runner classes

> [!NOTE]
> Each stage runs in a pinned, provable OCI image chosen by its declared class,
> the same image on your laptop and in CI.

**Audience:** users, operators &nbsp;·&nbsp; **Type:** Explanation

## What it is (functionally)

Stages do not run on "whatever image the runner happens to have". Each stage
declares a **runner class**, and a single registry maps that class to a specific
container image from
[brik-images](https://github.com/getbrik/brik-images) (multi-arch, scanned,
rebuilt weekly for CVE fixes):

| Class | Image | Stages that use it |
|-------|-------|--------------------|
| `base` | `brik-runner-base` | init, release, notify |
| `stack` | the project's toolchain image (e.g. `brik-runner-node:22`) | build, lint, test, package |
| `analysis` | `brik-runner-analysis` (semgrep, checkov, ...) | sast |
| `scanner` | `brik-runner-scanner` (grype, syft, gitleaks, ...) | scan, container-scan |
| `deploy` | `brik-runner-deploy` (helm, kubectl, argocd, ...) | deploy, promote |

The `stack` class is **dynamic**: Init detects your stack and resolves the
matching toolchain image, so the build, lint, and test stages run with your
language's real tools. The other four are fixed.

## Why it matters

- **The linter really runs in the analysis image, and the deploy really runs in
  the deploy image** on GitLab, on Jenkins, and on your laptop, because every
  adapter and the local containerized runner resolve images through the same
  map. Reproducing a CI failure locally is running the same stage in the same
  image, not "read the runner docs and pray".
- **Which image ran a stage is an auditable fact, not a guess.** The
  actually-executed image is stamped into the report and into the SLSA builder
  identity, so provenance can name the toolchain that produced an artifact.
- **One place to retarget the whole fleet.** Point at an alternate map to use a
  registry mirror, a digest-pinned set, or an air-gapped registry without
  touching the bundled default.

## How it works

A stage selects its class in its manifest (`spec.runner.class`). Init resolves
all five classes once and publishes them so every later stage (and every
platform adapter) reads the same image for a given class. The `stack` class
resolves to the project's language image (kept per-project, out of the shared
map), while the four static classes resolve to a fixed `image:tag`.

The language-stack image *versions* (node 22, python 3.13, ...) are declared in
the stack manifests, separately from the class-to-image map: the base image is
not a language stack.

## Configuration & reference

- **Source of truth:** [`lib/registry/runner_classes.yml`](../../lib/registry/runner_classes.yml)
  maps each class to its image; a stage picks its class in its manifest.
- **Retarget every image:** set `BRIK_RUNNER_CLASSES_FILE` to an alternate copy
  of `runner_classes.yml` (a mirror, a digest-pinned fleet, an air-gapped
  registry, or an e2e stub) to supersede every image without editing the
  bundled default. On GitLab set it as a CI/CD variable; on Jenkins pass it as a
  build parameter. The stages that *read* the file (init, plan) still run on
  their bootstrap image; the override only affects the stages launched from the
  resolved map.
- **How adapters consume it:** Init writes the resolved images into the
  inter-stage dotenv (`BRIK_IMG_<CLASS>`, `BRIK_CI_IMAGE` for the stack); GitLab
  job templates reference `${BRIK_IMG_<CLASS>}` in their `image:` directive,
  Jenkins resolves each stage's image from the same variables.
- **Contributor detail** (the registry API, the manifest fields, the dotenv
  contract): [registry deep-dive](../contributing/registry/README.md),
  [stage manifest](../contributing/registry/manifest-stage.md),
  [stack manifest](../contributing/registry/manifest-stack.md).

## Related

- [Fixed flows](fixed-flows.md): which stage runs where in the flow
- [Local execution](local-execution.md): the same images, run on your machine
- [Supply-chain gates](supply-chain.md): the builder identity the image stamps into provenance
- [Declarations](declarations.md): the manifests that declare classes and stacks
