# E2E Known Issues (GitLab + Jenkins)

This document tracks E2E test infrastructure issues surfaced during Phase 3
validation on briklab. None of these are Brik code bugs - they are
pre-existing test fixtures, environment setup, or runtime contention
problems. They are recorded here so future fixes can address them without
re-investigation.

Last validated: 2026-04-20 (Phase 3 domain reorg baseline).

## Status Overview

| Scenario | Platform | Class | Root cause |
| --- | --- | --- | --- |
| node-deploy-helm | GitLab + Jenkins | fixture missing | No `.gitlab-ci.yml` / Jenkins job not seeded |
| workflow-trunk-main | GitLab + Jenkins | fixture missing | No `.gitlab-ci.yml` / Jenkins job not seeded |
| node-deploy-gitops | GitLab + Jenkins | infra flake | ArgoCD port-forward unstable |
| rust-complete | GitLab + Jenkins | infra flake | cargo publish idempotency (crate already exists) |
| node-deploy | Jenkins only | infra contention | port 3000 already allocated |
| node-deploy-dryrun | Jenkins only | fixture missing | Jenkins job not seeded |
| node-deploy-ssh | Jenkins only | infra setup | uid 1000 has no /etc/passwd entry in SSH container |

## GitLab

### node-deploy-helm (pipeline #82 on briklab)

Job names in the pipeline: `build`, `test`, `code_quality`, `review`,
`browser_performance`, `stop_review`. These are Auto DevOps defaults - GitLab
fell back to Auto DevOps because the test project is missing `.gitlab-ci.yml`.

**Fix:** Add a minimal `.gitlab-ci.yml` to
`briklab/test-projects/node-deploy-helm/` that includes the Brik GitLab
template, matching the pattern used by `node-deploy-k8s`.

### workflow-trunk-main (pipeline #89 on briklab)

Same signature as helm: Auto DevOps job names (`build`, `test`,
`code_quality`, `semgrep-sast`, `container_scanning`), missing
`.gitlab-ci.yml`.

**Fix:** Add `.gitlab-ci.yml` to
`briklab/test-projects/node-workflow-trunk/`.

### node-deploy-gitops (pipeline #188 on briklab)

```
[ERROR] [deploy] argocd app sync failed for: brik-e2e-gitops
Failed to establish connection to host.docker.internal:9080:
  error dial proxy: dial tcp 192.168.65.254:9080: connect: connection refused
```

ArgoCD port-forward from Jenkins/GitLab runner to the k3d cluster is
intermittently unavailable. Already documented in
`docs/archives/deploy-remaining-issues.md` ("ArgoCD stability").

**Fix:** Either (a) make the port-forward persistent or self-healing on the
briklab host, or (b) retry with backoff inside `deploy.argocd.sync` before
marking failure.

### rust-complete (pipeline #192 on briklab)

```
error: crate rust-complete@0.1.0 already exists on `brik-cargo` index
[ERROR] [package] cargo publish failed
```

Successive runs fail because cargo does not allow overwriting an existing
version. Pre-existing publish idempotency problem, already documented.

**Fix:** Either (a) bump the version per run via the release stage, or (b)
teach `pkg.cargo.publish` to skip-if-exists when running against a test
registry, or (c) add a pre-flight clean on briklab Nexus `brik-cargo` repo
before the suite starts.

## Jenkins only

These three surfaced only under Jenkins because the runner, container, or
seed-job environment differs from GitLab.

### node-deploy (job `node-deploy`, build #1)

```
Error response from daemon: failed to set up container networking:
  driver failed programming external connectivity on endpoint node-deploy-app-1:
  Bind for 0.0.0.0:3000 failed: port is already allocated
```

Port 3000 was already in use on the briklab host when the Jenkins pipeline
ran compose-up. Likely leftover from a previous run (GitLab `node-deploy`
scenario) that did not tear down its stack, or from parallel contention
inside `--parallel-groups`.

**Fix:** Either (a) make the compose teardown unconditional (post-step or
trap) so stacks never linger, (b) let each test pick an ephemeral port
instead of hard-coding 3000, or (c) serialize compose-based deploy scenarios
across platforms.

### node-deploy-dryrun (job not found)

Jenkins returned an HTML "Not Found" page when the briklab runner tried to
trigger the build. The CasC seed job does not create `node-deploy-dryrun`
on Jenkins.

**Fix:** Add `node-deploy-dryrun` to the Jenkins seed-job definition
(`briklab/config/jenkins/casc/jobs.yaml` or equivalent).

### node-deploy-ssh (job `node-deploy-ssh`, build #1)

```
[deploy] running: rsync -avz --delete -e ssh ... deploy@ssh-target.briklab.test:/opt/app/
No user exists for uid 1000
rsync: connection unexpectedly closed (0 bytes received so far) [sender]
rsync error: unexplained error (code 255) at io.c(232)
```

The Jenkins agent container runs as uid 1000 but has no matching entry in
`/etc/passwd`. rsync refuses to open an SSH connection under an "unknown" uid.

**Fix:** Either (a) add a matching `jenkins` user to the agent container
image with uid 1000, (b) set `HOME` and `USER` env vars explicitly so ssh
does not look up the passwd entry, or (c) mount a nsswitch shim. The
GitLab runner image already handles this correctly.

## Procedure When a New Flake Appears

1. Apply the skill `e2e-triage-after-bulk-refactor`
   (`~/.claude/skills/learned/`) to classify the failure.
2. If pre-existing / infra / fixture: add an entry to this file with
   scenario name, platform, pipeline or build reference, exact error
   excerpt, and proposed fix.
3. Only block the current commit on Class 1 regressions (path moved,
   module renamed, loader broken).
