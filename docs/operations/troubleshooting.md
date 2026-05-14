# Troubleshooting

Common failures when running Brik pipelines, and how to fix them. Grouped by
symptom; platform-specific notes are called out inline.

## `yq` or `jq` not found

Brik needs `yq` and `jq` on every runner.

- **GitLab**: the job `before_script` downloads `yq` automatically. If that
  fails, the runner has no internet access -- use a `brik-runner-*` image (which
  ships `yq`, `jq`, `git`, `bash` preinstalled) or mirror the images to a
  reachable registry.
- **Jenkins**: with Docker agents (the default) `yq` and `jq` are preinstalled
  in the runner images. Without Docker agents (`useDockerAgent: false`), install
  `yq` and `jq` on the agent node.
- **Local**: run `brik doctor` to see which tools are missing; see
  [getting-started/local.md](../getting-started/local.md#install).

## `brik.yml` fails validation

The Init stage validates `brik.yml` against the JSON Schema and aborts with
`BRIK_EXIT_CONFIG_ERROR` on a bad config. Reproduce it locally before pushing:

```bash
brik validate --config brik.yml
```

The validator prints the offending path and the schema rule it broke. See the
[configuration reference](../configuration/reference/) for the valid shape of
each section.

## Runtime not cloned (GitLab)

If a job fails before any stage logic runs, the runner could not clone the Brik
runtime. Check that the `brik/brik` project exists on your GitLab instance, that
it carries the tag pinned by `BRIK_LIB_REF`, and that the runner can reach the
repo URL (`BRIK_REPO`). See [getting-started/gitlab.md](../getting-started/gitlab.md).

## Runner not registered (GitLab)

The pipeline needs a GitLab Runner with the **Docker executor**. If jobs stay
pending, register a runner and confirm the executor is `docker`.

## Scripts not executable (Jenkins)

If stages fail with "permission denied", the shell scripts lost their execute
bit in the repository. Restore it, or point Brik at a known-good path:

```groovy
brikPipeline(brikHome: '/custom/path/to/brik')
```

## Sandbox restrictions (Jenkins)

The Brik library must be a **trusted** Global Pipeline Library (not sandboxed),
because it uses `sh` steps. This is the default when configured via CasC with
`modernSCM` -- see [getting-started/jenkins.md](../getting-started/jenkins.md).

## `GIT_BRANCH` has an `origin/` prefix (Jenkins)

`jenkins-wrapper.sh` strips the `origin/` prefix from `GIT_BRANCH` automatically.
No manual intervention is needed; if you see it surface anyway, the wrapper was
bypassed.

## Docker network issues (Jenkins)

If runner containers cannot reach external services (registries, Git servers,
ArgoCD), pass the correct network explicitly:

```groovy
brikPipeline(dockerNetwork: 'my-network')
```

By default `brikPipeline` auto-detects the network from the Jenkins container.

## Private registry / cannot pull `ghcr.io`

If runners cannot pull from `ghcr.io`, mirror
[brik-images](https://github.com/getbrik/brik-images) to your private registry.

- **GitLab**: override `BRIK_CI_IMAGE`, `BRIK_ANALYSIS_IMAGE`,
  `BRIK_SCANNER_IMAGE`, and `BRIK_DEPLOY_IMAGE` in your `.gitlab-ci.yml`.
- **Jenkins**: the stack image is resolved from `brik.yml`; for the specialized
  images, configure Jenkins environment variables or update the image names in
  a fork.

## A stage fails but the pipeline still exits 0

That is expected in [snapshot context](../concepts/pipeline-context.md): a
failing stage maps to `business.status=warning` and the run exits clean so you
get a full report. To force fail-fast on snapshot, set
`BRIK_CONTINUE_ON_ERROR=0`. To understand the verdict, read the **Business
outcome** block in `aggregate-report.md` and see
[business outcome](../concepts/business-outcome.md).

## A finding blocks a release and you cannot fix it now

Do not paper over it with `BRIK_CONTINUE_ON_ERROR=1`. Use the supported path:
write a `brik-policy.yml` allowlist entry with a `reason` and an `expires` date.
See [risk management](risk-management.md) for the decision tree.

## See also

- [GitLab platform](../platforms/gitlab.md) -- runner images, variables, requirements
- [Jenkins platform](../platforms/jenkins.md) -- parameters, Docker agents, prerequisites
- [Credentials](credentials.md) -- secret wiring per platform
- [Briklab](../internals/briklab.md) -- a local environment to reproduce CI failures
