# `brik.yml` reference

> Every top-level section of `brik.yml`, one line each. Follow a section to its
> dedicated page: what it is for, what it does, when it runs, and how to
> configure it.

Only **`version`** and **`project`** are required. Everything else is optional
and has a per-stack default -- you set a section only to override what matters
for your project. New to the file? Start with the
[configuration overview](overview.md) ("declare what, not how").

| Section | | What it configures |
|---------|---|--------------------|
| [`version`](#version) | required | The schema version of this file (currently `1`). |
| [`project`](project.md) | required | Identity: name, stack, and toolchain version. |
| [`build`](build.md) | | How the application is compiled or assembled. |
| [`quality`](quality.md) | | Lint, format check, and type check. |
| [`security`](security.md) | | SAST, dependency and secret scanning, container scanning. |
| [`test`](test.md) | | Test framework, coverage thresholds, and reports. |
| [`package`](package.md) | | Building the release container image. |
| [`publish`](publish.md) | | The registries the built image is pushed to. |
| [`artifacts`](artifacts.md) | | Channels (where CI publishes and CD resolves) and the evidence journal. |
| [`deploy`](deploy.md) | | Environments, targets, gates, and promotion chains. |
| [`release`](release.md) | | Versioning from git tags and changelog generation. |
| [`notify`](notify.md) | | Slack, email, and webhook notifications. |
| [`git`](git.md) | | The git identity Brik uses for the commits and tags it makes. |
| [`hooks`](hooks.md) | | Inline shell commands to run before or after stages. |
| [`pipeline`](pipeline.md) | | Pipeline-level settings. |

Each page also links to the JSON schema
([`brik.schema.json`](../../../schemas/config/v1/brik.schema.json)), the source
of truth from which the field tables on every page are generated.

## version

The only mandatory scalar: the schema version of the file, currently `1`. It
lets Brik evolve the format without breaking existing projects. With
`project.name`, it is the whole of a minimal `brik.yml`:

```yaml
version: 1
project:
  name: my-app
```
