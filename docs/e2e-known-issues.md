# E2E Known Issues (GitLab + Jenkins + Local)

This document tracks E2E test infrastructure issues surfaced during ongoing
validation on briklab. None of these are Brik core code bugs - they are
test fixtures, briklab infrastructure, or runner-image gaps. They are
recorded here so future fixes can address them without re-investigation.

Last validated: **2026-04-22** (R3.1 run, timestamp `20260422T224208`).
Prior baselines: `20260422T172517` (R2), `20260422T140016` (initial),
`2026-04-20` (Phase 3 reference).

## Run Snapshot - 2026-04-22

Three batches were executed sequentially today. Local first, then GitLab
(`--all --parallel-groups`), then Jenkins (`--all --parallel-groups`).
Briklab Jenkins was recreated between batches to apply CasC + mount
changes.

| Platform | Total | Passed | Failed | Run timestamp                                  |
|----------|------:|-------:|-------:|------------------------------------------------|
| Local    |     3 |      3 | 0      | `local-20260422T224208.log`                    |
| GitLab   |    28 |     19 | 2 + 7 cascade | `gitlab-20260422T224208.log`            |
| Jenkins  |    28 |     16 | 5 + 7 cascade | `jenkins-20260422T224208.log`           |

Detailed batch summaries:
- `e2e-results/summary-20260422T140016.md` (initial baseline before fixes)
- `e2e-results/summary-20260422T172517.md` (R3 - first verification round)

### Local (3/3 PASS)

`brik run stage init / build / test` against `examples/minimal-node/`.
Restored `package.json`, `src/index.js`, `test/index.test.js` plus
`test.framework: npm` in `brik.yml` (commit `e037886` in brik). All
three stages pass.

### GitLab batch (19/28 PASS, 2 real fail + 7 cascade-skip)

Real failures:
- `node-deploy-gitops` - ArgoCD unreachable (infra).
- `java-complete` - intermittent `brik-package: skipped` (flake; passed in
  R3, fails in R3.1). See java-complete entry below.

Notable wins:
- `node-deploy` PASS (port-3000 collision with `brik-gitea` resolved by
  bumping host port to 13000 in compose fixture).
- `node-deploy-helm` PASS (was missing `.gitlab-ci.yml`; added).
- `node-deploy-dryrun` PASS.
- `rust-complete` PASS (cargo crate cleanup runs before scenario).
- `workflow-trunk-main` PASS (`wait_pipeline_by_sha` stdout fix - prior
  failure was a stdout-capture bug, the pipeline itself succeeded).

Cascade-skipped: `node-deploy-rollback`, `workflow-trunk-{tag,feature}`,
`error-{build,test,config,deploy}` (depend on the failing scenarios).

### Jenkins batch (16/28 PASS, 5 real fail + 7 cascade-skip)

Real failures:
- `node-deploy-gitops` - same ArgoCD infra issue as GitLab.
- `workflow-trunk-main` - seed job now exists, but no Gitea webhook /
  no SCM-polling trigger means git push lands but no build is triggered.
- `rust-complete` - cargo auth resolved; new failure mode: dirty working
  tree.
- `java-minimal` and `java-complete` - osv-scanner deps scan failed
  (CVE-database flake; both passed earlier in the day).

Notable wins (compared to R2 baseline):
- `node-deploy` PASS (port bump).
- `node-deploy-dryrun` PASS (`BRIK_DRY_RUN` declared as `booleanParam`).
- `node-deploy-ssh` PASS (deploy container runs `-u 0:0`, SSH key
  mounted, `SSH_PRIVATE_KEY` propagated through the env-grep).
- `node-deploy-helm` PASS (CasC seed job added).

Cascade-skipped: same set as GitLab.

## Status Overview - Remaining Issues

| Scenario              | Platform        | Class            | Status              |
|-----------------------|-----------------|------------------|---------------------|
| node-deploy-gitops    | GitLab + Jenkins| infra (ArgoCD)   | open                |
| workflow-trunk-main   | Jenkins only    | trigger config   | open                |
| rust-complete         | Jenkins only    | publish strict mode | open             |
| java-minimal          | Jenkins         | CVE flake        | open / monitoring   |
| java-complete         | GitLab + Jenkins| flake            | open / monitoring   |

Issues that were on this list and are now resolved are listed in the
"Recently Fixed" section at the bottom for audit trail.

## GitLab

### node-deploy-gitops - ArgoCD unreachable

```
[ERROR] [deploy] argocd app sync failed for: brik-e2e-gitops
Failed to establish connection to host.docker.internal:9080:
  error dial proxy: dial tcp 192.168.65.254:9080: connect: connection refused
```

ArgoCD port-forward from the runner container to the k3d cluster on the
briklab host is intermittently unavailable. The yaml-migration positive
signal stands - `image tags substituted to :0.1.0` logged correctly, so
`transverse.yaml.set_image_tag` is not the problem.

Fix options:
- (a) Make the port-forward persistent or self-healing on briklab.
- (b) Retry with backoff inside `deploy.argocd.sync` before failing.

### java-complete - brik-package skipped

```
[FAIL] Job 'brik-package' status -- expected='success' actual='skipped'
[WARN]  brik-quality: not_found (optional)
[WARN]  brik-security: not_found (optional)
```

The pipeline ran but `brik-package` was skipped, meaning a `rules:` clause
in the GitLab template excluded it. Optional jobs (`brik-quality`,
`brik-security`) were also `not_found`, suggesting the template evaluated
a different rule branch than expected for this scenario.

Fix options:
- Reproduce on a single scenario run and inspect the pipeline's
  `parsed_yaml` to see which rule excluded `brik-package`.
- This was PASS in batches `20260422T140016` and `20260422T172517` - mark
  as flake until reproducible.

## Jenkins

### workflow-trunk-main - no build triggered after push

```
[INFO]  Triggering via git push (ref: main)...
[OK]    Push SHA: 85216442f3a33ca0a4de89586137a270d48a3c63
[INFO]  Waiting for build triggered by SHA 85216442...
..................                   <- 90s of polling, then timeout
```

The CasC seed job for `node-workflow-trunk` is in place (verified: HTTP
200 on `/job/node-workflow-trunk/api/json`). Git push to Gitea succeeds.
Jenkins does not auto-build because the seed job has no `triggers`
clause, no Gitea webhook is configured to call back to Jenkins, and no
SCM-polling schedule is set.

Fix options (pick one):
- Add `triggers { scm('* * * * *') }` to the JobDSL block in
  `briklab/config/jenkins/casc.yaml` for `node-workflow-trunk` (and any
  other push-driven scenarios added later).
- Configure a Gitea push webhook pointing at
  `http://jenkins.briklab.test:9090/gitea-webhook/post`.
- For the E2E harness, after `git push` poll Jenkins's `/queue/api/json`
  with the SHA in the build cause instead of waiting on `lastBuild`.

### rust-complete - cargo refuses dirty working tree

```
error: 4 files in the working directory contain changes that were not yet committed into git:
[ERROR] [package] cargo publish failed
[ERROR] [brik] stage package failed with exit code 5
```

Authentication is now correct (the previous `token rejected for brik-cargo`
401 is resolved by `NEXUS_CARGO_TOKEN` propagation). New failure: cargo
publishes refuse to run when the workspace has uncommitted changes,
which happens on Jenkins because earlier stages (build, test, scan) wrote
artifacts into the workspace.

Fix options:
- Add `--allow-dirty` to the cargo publish command in
  `brik/lib/package-managers/cargo.sh` (one-line change). This is the
  GitLab-Runner default behavior because GitLab-Runner re-clones a fresh
  workspace per stage; Jenkins reuses the workspace across stages.
- Alternative: clean the workspace (`git stash` / `git checkout -- .`)
  before the publish step. Less surgical.

### java-minimal / java-complete - osv-scanner CVE flake

```
[WARN] [scan] security scan failed: deps
[INFO] [scan] security summary: 1/2 scans passed, 1 failed
[ERROR] [brik] stage scan failed with exit code 10
```

osv-scanner found a deps vulnerability in the java fixture that was not
reported earlier in the day. CVE feeds change daily; java fixtures are
small and pinned to old versions, so each new CVE in those exact deps
flips the scan from PASS to FAIL.

Fix options:
- Bump the java fixture deps to current LTS versions periodically.
- Lower the deps-scan severity threshold for fixtures (e.g.
  `security.deps.severity: critical` instead of `high` in the brik.yml).
- Pin the osv-scanner database snapshot in CI so feed drift doesn't
  flip green-to-red between runs.

### node-deploy-gitops (Jenkins)

Same root cause as the GitLab side: ArgoCD port-forward from the runner
to the k3d cluster is unreachable. Single fix covers both platforms.

## Procedure When a New Flake Appears

1. Apply the skill `e2e-triage-after-bulk-refactor`
   (`~/.claude/skills/learned/`) to classify the failure.
2. If pre-existing / infra / fixture: add an entry to this file with
   scenario name, platform, pipeline or build reference, exact error
   excerpt, and proposed fix.
3. Only block the current commit on real Brik regressions (path moved,
   module renamed, loader broken). Everything else goes here for
   later cleanup.

## Recently Fixed (2026-04-22)

For audit trail. Each line names the fixed scenario, the resolving
commit, and the briklab/brik repo it landed in.

- `node-deploy` (GitLab + Jenkins) - port collision with `brik-gitea`
  on host port 3000. Fixed by bumping `node-deploy/docker-compose.yml`
  host mapping to `13000:3000`. briklab `71bf6b6`.
- `node-deploy-helm` (GitLab) - missing `.gitlab-ci.yml`. Added in
  briklab `71bf6b6`.
- `node-deploy-helm` (Jenkins) - missing CasC seed job. Added in
  briklab `3f5a161`.
- `node-deploy-dryrun` (Jenkins) - `BRIK_DRY_RUN` parameter not
  declared. Added `properties([parameters([booleanParam(...)])])` to
  `brikPipeline.groovy`. brik `236591b`.
- `node-deploy-ssh` (Jenkins) - "No user exists for uid 1000" inside
  brik-runner-deploy. Run the deploy container as `-u 0:0` plus mount
  the briklab ssh key into `/opt/brik/ssh/deploy_key` and propagate
  `SSH_PRIVATE_KEY` through the env-grep. brik `236591b` + briklab
  `3f5a161`.
- `rust-complete` (GitLab) - "crate already exists on brik-cargo".
  Added `e2e.nexus.delete_cargo_crate` pre-cleanup before the
  scenario. briklab `facca85`.
- `rust-complete` (Jenkins) - "token rejected for brik-cargo" / 401.
  Two-part fix: add `CARGO_` to the env-grep in `brikPipeline.groovy`
  and propagate `NEXUS_CARGO_TOKEN` through the briklab compose env.
  brik `236591b` + briklab `9e9bc20`.
- `workflow-trunk-main` (GitLab) - silent failure when pipeline
  succeeded. Root cause was `wait_pipeline_by_sha` writing log_info
  to stdout, contaminating the captured `pipeline_id status` value
  with ANSI text. Redirected log_info / log_error to stderr.
  briklab `facca85`.
- `workflow-trunk-main` (Jenkins) - missing CasC seed job. Added in
  briklab `9e9bc20`. (Triggering still open - see above.)
- E2E harness "Logs clean: brik-deploy" false positive on a failed
  job - skip `assert.job_logs_clean` when the job/build status is
  already `failed`. Race-prone secondary checks must not mask
  primary-status assertions. briklab `facca85`.
- E2E harness pre-cleanup helpers: new
  `e2e.compose.teardown_stack <project>` and
  `e2e.nexus.delete_cargo_crate <name> <version>`, wired as per-scenario
  pre-hooks in both `gitlab-suite.sh` and `jenkins-suite.sh`. briklab
  `facca85`.
- `examples/minimal-node` local build - missing `package.json`,
  `src/`, `test/`. Restored. brik `e037886`.
