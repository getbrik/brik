# Extending a Stage

Adding a stage to the [fixed flow](../concepts/fixed-flows.md) is rare and
deliberate -- the flow is fixed on purpose. When it is genuinely needed, the
change touches the stage entry point, every platform adapter, and the schema.

## Recipe: add a stage

1. **Stage entry point** -- create `lib/stages/<stage>.sh` implementing
   `stages.<stage>` following the pattern of the existing stages (it runs
   through [`stage.run`](stage-lifecycle.md)).

2. **Shared library template** -- add the stage to
   `shared-libs/gitlab/templates/brik-integrate.yml` (and the other platform
   adapters). For GitLab specifically, the new job template **must declare**
   `artifacts.reports.dotenv: .brik-logs/pipeline.env`, otherwise downstream
   jobs will see a stale snapshot of `pipeline.env` and lose any keys
   published by upstream stages. The parity is enforced by
   `spec/integration/gitlab_dotenv_parity_spec.sh`; see
   [GitLab env propagation](../reference/platforms/gitlab.md#env-propagation) for the
   underlying mechanism.

3. **Pipeline flow** -- add the stage name to the `stages:` list in the GitLab
   template so it appears in the DAG.

4. **Schema** -- add any stage-specific configuration properties to
   `schemas/config/v1/brik.schema.json`.

5. **Tests** -- add ShellSpec tests under `spec/stages/<stage>_spec.sh`.

## Repository layout

The stage files live in `lib/stages/`; the rest of the runtime is organized by
the nine domain notions (see [layout.md](layout.md)). The annotated tree:

```
brik/
  bin/brik                  Thin CLI dispatcher, delegates to lib/cli/
  lib/
    pipeline/               Execution engine: stage.run, pipeline.run, loader,
                            logging, context, report, hooks, tools, bootstrap
    cli/                    CLI command modules (validate, doctor, init, run, ...)
    stages/                 The 12 pipeline stages
      verify/               Internal umbrella consumed by lint/sast/scan/container-scan
        verify.sh           verify.run dispatcher
        format.sh, lint.sh, type_check.sh
        scan/               scan.sh dispatcher + container, deps, iac, license, sast, secret
    stacks/                 Per-stack build + test + install_deps (node, python,
                            java, rust, dotnet, docker)
    transverse/             Cross-cutting helpers (git, version, env, changelog,
                            conditions, config, csv, secrets, ssh, wait, yaml, tools)
      config/               Per-stack config modules
    deployments/            Deploy targets (k8s, helm, compose, ssh, gitops, argocd)
    rollout/                Post-deploy rollout (health, strategy, profile)
    package-managers/       Registry publishers (npm, pypi, maven, cargo, nuget, docker)
  spec/                     ShellSpec tests, mirrors lib/
  shared-libs/              Platform adapters
    common/                 base-wrapper.sh, platform-agnostic
    gitlab/                 GitLab CI pipeline template
    jenkins/                Jenkins shared library (vars/ + wrapper)
    local/                  Local execution wrapper
    github/                 GitHub Actions (planned)
  schemas/                  JSON Schema for brik.yml + report + policy
  examples/                 minimal-node, java-maven, python-pytest, mono-dotnet
```

The `verify/` directory is internal implementation, not a CI-visible stage:
`lint`, `sast`, `scan`, and `container-scan` each call into it. See the
[fixed flow](../concepts/fixed-flows.md) for which stages are CI-visible.

## See also

- [Stage lifecycle](stage-lifecycle.md) -- what `stage.run` wraps your stage with
- [Layout](layout.md) -- the nine domain notions in detail
- [Extending a stack](extending-stack.md) -- the more common extension
- [Architecture](../concepts/architecture.md) -- why the flow is fixed
