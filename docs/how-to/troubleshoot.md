# Troubleshooting

Common failures when running Brik pipelines, and how to fix them. Grouped by
symptom; platform-specific notes are called out inline.

## `yq` or `jq` not found

Brik needs `yq` and `jq` on every runner.

- **GitLab**: the job `before_script` downloads `yq` automatically. If that
  fails, the runner has no internet access: use a `brik-runner-*` image (which
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
[configuration reference](../reference/configuration/README.md) for the valid shape of
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
brikIntegrate(brikHome: '/custom/path/to/brik')
```

## Sandbox restrictions (Jenkins)

The Brik library must be a **trusted** Global Pipeline Library (not sandboxed),
because it uses `sh` steps. This is the default when configured via CasC with
`modernSCM` (see [getting-started/jenkins.md](../getting-started/jenkins.md)).

## `GIT_BRANCH` has an `origin/` prefix (Jenkins)

`jenkins-wrapper.sh` strips the `origin/` prefix from `GIT_BRANCH` automatically.
No manual intervention is needed; if you see it surface anyway, the wrapper was
bypassed.

## Docker network issues (Jenkins)

If runner containers cannot reach external services (registries, Git servers,
ArgoCD), pass the correct network explicitly:

```groovy
brikIntegrate(dockerNetwork: 'my-network')
```

By default `brikIntegrate` auto-detects the network from the Jenkins container.

## Private registry / cannot pull `ghcr.io`

If runners cannot pull from `ghcr.io`, mirror
[brik-images](https://github.com/getbrik/brik-images) to your private registry,
then point Brik at a copy of the runner-class registry that names the mirror.

- Copy [`lib/registry/runner_classes.yml`](../concepts/runner-classes.md),
  rewrite each `image:` to your mirror, and set `BRIK_RUNNER_CLASSES_FILE`
  to that file. This redirects every runner image (base, stack, analysis,
  scanner, deploy) in one place, on both GitLab and Jenkins.
- **GitLab**: set `BRIK_RUNNER_CLASSES_FILE` as a CI/CD variable (a FILE-type
  variable, or a path resolvable inside the runner).
- **Jenkins**: pass `BRIK_RUNNER_CLASSES_FILE` as a build parameter; a path
  relative to the brik library root is resolved to absolute automatically.

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
See [risk management](accept-a-finding.md) for the decision tree.

## Deploy fails: infrastructure referential not found

If `brik deploy` fails with a referential error, check:

- Is `BRIK_INFRA_DIR` set?
- Does the path exist and contain valid endpoint/credential/policy documents?
- On local runs: mount the referential at the path or export `BRIK_INFRA_DIR`.
- On GitLab: the deploy job template mounts the referential as a volume or injects
  it via the shared library setup.
- On Jenkins: pass `brikInfraDir` to `brikIntegrate()` and ensure the path is
  reachable from the agent.

## Deploy fails: attestation verification

If the deploy stage fails to verify attestations:

- The signing certificate or key was misconfigured in the referential.
- The container image has no attached SBOM or SLSA provenance (did CI complete
  without errors?).
- The registry does not support referrers (OCI 1.1). Check the registry
  documentation.
- The deployment environment's `gates.expected_builder` or `gates.expected_source`
  regex does not match the attested builder identity or source. Check the
  [builder-identity convention](../concepts/supply-chain.md#the-builder-identity-convention).

The CD trace logs each gate decision; the gates run in order (digest, attestation, eligibility) and the first refusal names its reason.

## Deploy fails: promotion journal missing or unverifiable

If `requires_eligibility` blocks the deploy:

- Is the state-repo (`artifacts.evidence.repo`) reachable and writable?
- Did `brik authorize --version <v> --for <env>` run to grant the version?
- If the journal is signed, do the credentials and `allowed_signers` file match?
- Does the journal entry bind the correct digest? Journal entries are digest-bound;
  re-promoting with a different digest breaks eligibility.

The CD trace names the missing grant type and the digest it looked for.

## See also

- [GitLab platform](../reference/platforms/gitlab.md): runner images, variables, requirements
- [Jenkins platform](../reference/platforms/jenkins.md): parameters, Docker agents, prerequisites
- [Credentials](manage-credentials.md): secret wiring per platform
- [Briklab](../contributing/briklab.md): a local environment to reproduce CI failures
