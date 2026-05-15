# Brik GitLab Shared Library

GitLab CI templates that implement the Brik [fixed flow](../../docs/concepts/fixed-flow.md).

This README is an **implementation annex**. The user-facing documentation is
canonical and lives in the docs tree:

- [Getting started: GitLab CI](../../docs/getting-started/gitlab.md) -- first-time setup
- [GitLab platform reference](../../docs/platforms/gitlab.md) -- runner images, pipeline variables, cache relocation, coverage reports, troubleshooting
- [`brik.yml` configuration](../../docs/configuration/overview.md) -- the project config file

## Directory structure

```
shared-libs/gitlab/
  scripts/
    gitlab-wrapper.sh    - bridges GitLab CI env to stage.run
  templates/
    pipeline.yml         - main entry point (stages, defaults, includes)
    jobs/
      init.yml           - Init stage job
      release.yml        - Release stage job (conditional)
      build.yml          - Build stage job
      lint.yml           - Lint stage job (verify, parallel)
      sast.yml           - SAST stage job (verify, parallel, analysis image)
      sast-reports.yml   - SAST report artifact wiring
      scan.yml           - Scan stage job (verify, parallel, scanner image)
      scan-reports.yml   - Scan report artifact wiring
      test.yml           - Test stage job (verify, parallel)
      package.yml        - Package stage job (conditional)
      container-scan.yml - Container scan job (scanner image)
      deploy.yml         - Deploy stage job (conditional, deploy image)
      notify.yml         - Notify stage job (always)
  spec/                  - ShellSpec tests
```

## How a job works

Each GitLab CI job:

1. Checks for the `/.brik-runner` marker (skips prerequisite install if present).
2. Otherwise installs `yq`, `jq`, `git`, `bash` via the detected package manager.
3. Clones `brik/brik` to `/opt/brik` (depth 1, pinned to `BRIK_LIB_REF`).
4. Sources `scripts/gitlab-wrapper.sh`.
5. Calls `brik.gitlab.run_stage <stage_name>`.
6. The wrapper invokes `stage.run` from the Brik runtime.

The Init job emits `.brik-logs/pipeline.env` as a `reports: dotenv:` artifact
(produced by the post-stage projection hook from the report env section) so
downstream jobs receive the resolved `BRIK_CI_IMAGE` and the trigger gating
flags. Per-project job overrides (for example a non-default coverage path) are
merged by GitLab into the templated job -- see the
[GitLab platform reference](../../docs/platforms/gitlab.md#coverage-reports).

## Tests

```bash
shellspec shared-libs/gitlab/spec/
```
