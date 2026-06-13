# Briklab

[Briklab](https://github.com/getbrik/briklab) is Brik's local end-to-end test
infrastructure. It is a separate repository; this page explains what it is and
how it relates to Brik. The briklab repo is the source of truth for its setup,
its service list, and its scenario catalogue -- this page does not duplicate
those, because they change independently of Brik.

## What it is

Brik's shared libraries and runtime can only be fully proven against real CI
platforms. Briklab provides that, locally, via Docker Compose -- no cloud
accounts, no shared servers:

- **GitLab CE + Runner** -- exercises the GitLab shared library.
- **Gitea + Jenkins** -- exercises the Jenkins shared library.
- **Nexus 3 CE** -- a real artifact registry for the publish step (npm, Maven,
  PyPI, NuGet, Docker, Cargo).
- **k3d (K3s in Docker) + ArgoCD** -- Kubernetes and GitOps deploy targets.
- **An SSH target container** -- the `ssh` and `compose` deploy targets.

Everything is driven by a Bash CLI (`scripts/briklab.sh`); one `init` command
brings the whole stack up.

## Why it matters for the docs

Briklab is the third leg of Brik's [test strategy](development.md#test-strategy),
after unit tests and shared-library tests. A claim in Brik's documentation is
only "true" once it is backed by a spec, an example, or a briklab scenario. When
you add or change behavior, the end-to-end check is a briklab run, not just
green ShellSpec.

## Where it sits

Briklab is *test infrastructure for Brik*, not a way to use Brik in production.
It belongs in `internals/` for that reason: it explains how Brik proves itself,
not how a first-time user runs a pipeline. For that, start at
[getting-started](../getting-started/gitlab.md).

## See also

- [briklab repository](https://github.com/getbrik/briklab) -- setup, services, scenario catalogue
- [Development](development.md) -- the test strategy briklab completes
- [Troubleshooting](../how-to/troubleshoot.md) -- briklab as a place to reproduce CI failures
