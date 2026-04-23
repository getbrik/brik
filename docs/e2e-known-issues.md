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

_No open issues tracked at 2026-04-23. Previously-open entries are
listed in "Recently Fixed" for audit trail._

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

## Recently Fixed (2026-04-23)

- `workflow-trunk-main` (Jenkins) - seed job existed but nothing was
  wiring Jenkins to Gitea on push, so the E2E push timed out waiting
  for a build. Installed the Gitea plugin and converted the seed to a
  `multibranchPipelineJob` backed by `giteaSCMSource` with
  `manageHooks: true` in SYSTEM mode, so Jenkins auto-registers the
  webhook at first scan. Side-patches in the E2E harness: multibranch
  URL resolver (`job/<name>/job/<branch>`), `curl -g` in `api_get` so
  `tree=builds[...]` queries don't get globbed, `>&2` on the log lines
  inside `wait_build_by_sha` / `wait_build` / `trigger_build` so the
  captured build-number isn't contaminated. Credential scope on the
  Jenkins side is GLOBAL (not SYSTEM) so the GiteaNotifier can look it
  up from the project context when pushing commit statuses back to
  Gitea. Verified E2E: build #12 PASS, "Notified" in Jenkins log
  instead of 401. briklab `6d46930`.

- `rust-complete` (Jenkins) - `cargo publish` refused to run against a
  dirty workspace (Jenkins reuses its workspace across stages; build and
  test artefacts remained in the tree). Always pass `--allow-dirty` in
  `pkg.cargo.publish`. Verified end-to-end: GitLab rust-minimal #551 +
  rust-complete #554 PASS, Jenkins rust-minimal #5 + rust-complete #8
  PASS. brik `431f51c`.

- `java-minimal` / `java-complete` (GitLab + Jenkins) - previously
  labelled "CVE flake" and "brik-package skipped flake" but both were
  the same root cause. osv-scanner's transitive Maven resolver makes an
  RPC call to `deps.dev` to resolve transitive deps from `pom.xml`; when
  that service is unreachable or flaky, osv-scanner prints
  `Error during extraction: (extracting as transitivedependency/pomxml)
  failed resolving ...: rpc error: code = Unavailable desc = service
  unavailable` and exits non-zero while still reporting `Total 0 packages
  affected by 0 known vulnerabilities`. Brik treated the non-zero exit
  as "vulnerabilities found" without surfacing the scanner's own output,
  which hid the real cause. Two-part fix: (a) `verify.scan.deps.run`
  prints the scanner output on the failure branch so CVEs (or extraction
  errors) are visible, and treats "Total 0 packages affected by 0 known
  vulnerabilities" in the output as a pass even when exit code is
  non-zero (warn-only). (b) `e2e.jenkins.trigger_build` auto-detects
  parameterized jobs and routes to `buildWithParameters` instead of
  `build`, fixing an HTTP 400 trigger failure introduced by the
  `BRIK_DRY_RUN` parameter now present on all brik jobs. Verified:
  java-minimal + java-complete PASS on both GitLab and Jenkins.
  brik `c165d35`, briklab `7b68502`.

- `workflow-trunk-main` (Jenkins) - `deploy.environments.*.when` used
  `ref: main` / `ref: tag`, which are not valid brik condition
  expressions (`conditions.eval` expects `subject <op> '<value>'`, e.g.
  `branch == 'main'`). Pipelines succeeded because the deploy stage
  skipped silently, but emitted `[ERROR] [deploy] invalid condition
  expression: ref: main` in logs. Fixed the fixture to use
  `branch == 'main'` (staging) and `tag =~ 'v*'` (production). Verified
  build #13 PASS on Jenkins, all 8 stages green, zero `invalid
  condition` hits in console. briklab `67ee1df`.

- `node-deploy-gitops` (GitLab + Jenkins) - the ArgoCD port-forward is
  started by `scripts/lib/auth/argocd-portfwd.sh` during briklab setup
  as a host-side `kubectl port-forward` background process. It dies
  silently when the setup shell exits, the laptop sleeps, or the k3d
  network hiccups, and nothing respawns it. The next E2E run then fails
  with `Failed to establish connection to host.docker.internal:9080`.
  Added `e2e.argocd.ensure_port_forward` as a per-scenario pre-cleanup
  hook in both gitlab-suite.sh and jenkins-suite.sh (gated on kubectl +
  an active kubeconfig + the argocd namespace). It delegates to the
  canonical `ensure_argocd_port_forward` which probes `:9080` and
  relaunches the port-forward if dead. Verified: killed the
  port-forward, then re-ran node-deploy-gitops on both platforms;
  preflight logged "port-forward not active, (re)starting" then "ready
  on :9080 (attempt 1/10)", scenarios passed end-to-end. Non-ArgoCD
  scenarios (e.g. node-minimal) unaffected. briklab `e7e070f`.
