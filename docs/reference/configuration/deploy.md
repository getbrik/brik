# `deploy`

> [!NOTE]
> Declare the environments your application ships to and the target each one uses.

**Section:** `deploy` (optional) &nbsp;·&nbsp; **Schema:** [`brik.schema.json#$defs/deploy`](../../../schemas/config/v1/brik.schema.json)

## What it is for

Describe *where the application is deployed and how*.

You declare one or more named environments (for example `staging` and
`production`). Each environment names a target (`ssh`, `compose`, `k8s`,
`helm`, or `gitops`) and a condition that decides when it applies. Brik does
the rest.

The whole section is optional. With no `deploy` block the deploy stage is
skipped.

## What it does

- Iterates over the `environments` map, evaluates each environment's `when`
  condition, and runs the matching target adapter when the condition is true.

- Routes to the right adapter per target: copies an artifact and restarts a
  service over `ssh`, brings up a stack with `compose`, applies manifests to
  `k8s`, installs or upgrades a chart with `helm`, or commits a manifest update
  for a GitOps controller to reconcile.

- Loads a built-in workflow profile when `deploy.workflow` is set,
  pre-configuring environments from branch and tag patterns. User-defined
  fields override the profile defaults.

- Deploys the version computed by the Release stage, so the same
  `BRIK_APP_VERSION` flows through to the deployed image tag.

## When it runs

This section drives the Deploy stage of the CD flow. Brik consumes an
artifact built earlier and ships it to the environments declared here.

Each environment's `when` condition decides whether it applies on a given run,
and `deploy.trigger` decides when the stage runs at all (on a tag, on the
default branch, on feature branches, or only on a manual run). The stage runs
once Brik has a version to deploy and at least one environment condition holds.

## How to configure

Declare environments under `deploy.environments`; optionally pick a `workflow` profile and a `trigger`.

<!-- BEGIN AUTO-GENERATED: quick-reference -->
| Field | Type | Default |
|-------|------|---------|
| `deploy.workflow` | enum (`trunk-based`, `git-flow`, `github-flow`) | -- |
| `deploy.environments` | `object` | -- |

- **`deploy.workflow`**

  Git workflow convention for automatic environment mapping. When set, Brik loads a built-in profile that pre-configures environments based on branch/tag patterns. User-defined environments override profile defaults.

  - **`trunk-based`**: staging on the `main` branch, production on a `v*` tag
  - **`git-flow`**: dev on `develop`, staging on `release/*` branches
  - **`github-flow`**: preview on `feature/*` branches, production on `main`

- **`deploy.environments`**

  Named deployment environments. Each key is an environment name (e.g. staging, production). Each value defines the deployment condition and target.


*Example*

```yaml
deploy:
  workflow: github-flow
```

### `deploy.trigger`

When the deploy stage should run. At least one of the flags must be true for the stage to execute. When the entire block is absent, the legacy always-run behaviour is preserved.

| Field | Type | Default |
|-------|------|---------|
| `deploy.trigger.on-tag` | `boolean` | `true` |
| `deploy.trigger.on-main` | `boolean` | `false` |
| `deploy.trigger.on-feature` | `boolean` | `false` |
| `deploy.trigger.manual` | `boolean` | `false` |

- **`deploy.trigger.on-tag`**

  Run when the current commit carries a git tag.

- **`deploy.trigger.on-main`**

  Run on push to the default branch.

- **`deploy.trigger.on-feature`**

  Run on push to a branch other than the default (typical use: review apps per feature branch).

- **`deploy.trigger.manual`**

  Run only when the pipeline was triggered manually (BRIK_TRIGGER_MANUAL=true).


### `deploy.environments.<name>`

Named deployment environments. Each key is an environment name (e.g. staging, production). Each value defines the deployment condition and target.

| Field | Type | Default |
|-------|------|---------|
| `deploy.environments.<name>.env_file` | `string` | -- |
| `deploy.environments.<name>.when` | `string` | -- |
| `deploy.environments.<name>.target` | enum (`ssh`, `compose`, `k8s`, `helm`, `gitops`) | -- |
| `deploy.environments.<name>.namespace` | `string` | -- |
| `deploy.environments.<name>.manifest` | `string` | -- |
| `deploy.environments.<name>.repo` | `string` | -- |
| `deploy.environments.<name>.path` | `string` | -- |
| `deploy.environments.<name>.controller` | `string` | -- |
| `deploy.environments.<name>.app_name` | `string` | -- |
| `deploy.environments.<name>.git_token_var` | `string` | -- |
| `deploy.environments.<name>.auth_token_var` | `string` | -- |
| `deploy.environments.<name>.chart` | `string` | -- |
| `deploy.environments.<name>.release_name` | `string` | -- |
| `deploy.environments.<name>.values` | `string` | -- |
| `deploy.environments.<name>.host` | `string` | -- |
| `deploy.environments.<name>.compose_file` | `string` | `docker-compose.yml` |
| `deploy.environments.<name>.service` | `string` | -- |
| `deploy.environments.<name>.remote_path` | `string` | -- |
| `deploy.environments.<name>.restart_cmd` | `string` | -- |
| `deploy.environments.<name>.source` | `string` | -- |
| `deploy.environments.<name>.strategy` | enum (`rolling`, `blue-green`, `canary`) | -- |
| `deploy.environments.<name>.on_health_failure` | enum (`hold`, `rollback`) | `hold` |
| `deploy.environments.<name>.accepts_channel` | `string` | -- |
| `deploy.environments.<name>.config_ref` | `string` | -- |
| `deploy.environments.<name>.validates_for` | `string` | -- |

- **`deploy.environments.<name>.env_file`**

  Path to the env file (KEY=VALUE format) sourced when deploying this environment, relative to the project root. Optional. Existing environment variables take precedence over file entries. Brik returns an error if env_file is declared but the file is missing on disk.

- **`deploy.environments.<name>.when`**

  Condition expression evaluated by the shared library to decide whether this environment is deployed. Supports branch equality (branch == 'main'), glob matching (tag =~ 'v*'), the pipeline_source subject (pipeline_source == 'merge_request_event'), and BRIK_* environment variables.

- **`deploy.environments.<name>.target`**

  Deployment target type.

  - **`ssh`**: runs the deploy commands over SSH on a remote host
  - **`compose`**: brings up a Docker Compose stack on the target host
  - **`k8s`**: applies raw Kubernetes manifests to a cluster
  - **`helm`**: installs or upgrades a Helm release
  - **`gitops`**: commits the desired state to a config repo for a controller (ArgoCD) to reconcile

- **`deploy.environments.<name>.namespace`**

  Kubernetes namespace for k8s and helm targets.

- **`deploy.environments.<name>.manifest`**

  Path to the Kubernetes manifest file or directory for the k8s target.

- **`deploy.environments.<name>.repo`**

  GitOps infrastructure repository as a clonable git URL (e.g. https://gitlab.example.com/org/infra.git or git@github.com:org/infra.git). Use `git_token_var` to authenticate without embedding credentials in the URL.

- **`deploy.environments.<name>.path`**

  Path within the GitOps repository where manifests for this service are located.

- **`deploy.environments.<name>.controller`**

  GitOps controller responsible for reconciliation (e.g. argocd, fluxcd).

- **`deploy.environments.<name>.app_name`**

  Application name as known to the GitOps controller.

- **`deploy.environments.<name>.git_token_var`**

  Name of the environment variable that contains the token used to push to the `repo` GitOps repository (e.g. `GIT_TOKEN`). Brik resolves the value indirectly at deploy time and embeds it into the clone URL. Applies to `target: gitops` only.

- **`deploy.environments.<name>.auth_token_var`**

  Name of the environment variable that contains the auth token used to drive the GitOps `controller` (e.g. `ARGOCD_TOKEN`). Brik resolves the value indirectly at deploy time and passes it to the controller adapter. Falls back to the controller's default env var (`ARGOCD_AUTH_TOKEN` for argocd) when not set. Applies when `controller: argocd`.

- **`deploy.environments.<name>.chart`**

  Helm chart path or repository reference for the helm target (e.g. ./charts/myapp or oci://registry/chart).

- **`deploy.environments.<name>.release_name`**

  Helm release name for the helm target. Defaults to the environment name if omitted.

- **`deploy.environments.<name>.values`**

  Path to a Helm values file for the helm target (e.g. charts/values-staging.yaml).

- **`deploy.environments.<name>.host`**

  Remote host address for the ssh target (hostname or IP).

- **`deploy.environments.<name>.compose_file`**

  Path to the Docker Compose file for the compose target.

- **`deploy.environments.<name>.service`**

  Docker Compose service name inspected for the post-deploy digest read-back (compose target). When omitted, the read-back reports the live digest as unknown rather than guessing a service.

- **`deploy.environments.<name>.remote_path`**

  Absolute path on the remote host where the application is deployed (ssh target).

- **`deploy.environments.<name>.restart_cmd`**

  Command to restart the application on the remote host after deployment (ssh target).

- **`deploy.environments.<name>.source`**

  Local path to the artifact directory uploaded by the `ssh` and `compose` targets, or to the rendered manifest tree pushed to the GitOps repo by the `gitops` target. Relative to the project root.

- **`deploy.environments.<name>.strategy`**

  Deployment strategy for targets that support it.

  - **`rolling`**: replaces instances incrementally, keeping the service available
  - **`blue-green`**: stands up the new version beside the old, then switches traffic over
  - **`canary`**: shifts a small share of traffic to the new version before a full rollout

- **`deploy.environments.<name>.on_health_failure`**

  What brik does when a deployment or its post-rollout health check fails. A failed deploy is never reported as success.

  - **`hold`** (default): leaves the environment on the previous version and marks the run failed
  - **`rollback`**: additionally reverts the deployment where the target supports it (the gitops target reverts the last config-repo commit); a target with no rollback path holds and logs that rollback is unsupported

- **`deploy.environments.<name>.accepts_channel`**

  Name of the artifacts.channels.<name> this environment's artifact is resolved from. The CD flow resolves --version to a digest within this channel's registry. Optional; absent means no channel resolution (legacy tag-based deploy).

- **`deploy.environments.<name>.config_ref`**

  Git ref of this repository (branch, tag or sha) this environment's deployment definition is read at when deploying (independent Layer E regime). The CD flow materializes the ref into a disposable worktree and reads the environment's definition there -- brik.yml and the files it references -- so the env config can change and be redeployed without cutting a new version; the artifact stays the digest resolved for --version, and both layer refs (version_ref, env_config_ref) are recorded in the report. Fails closed when the declared ref cannot be resolved. Absent means co-versioned: the definition follows the version's tag. An explicit --config opts out (the caller pinned the file).

- **`deploy.environments.<name>.validates_for`**

  Name of the NEXT deploy.environments.<name> in the promotion chain (e.g. staging validates_for production). A successful CD run on this environment (rollout healthy, live read-back not contradicting the pinned digest) appends an artifact_validated_for event for the named environment to the project's PromotionJournal, which the next environment's requires_eligibility gate consumes. Fail-closed: it requires accepts_channel on this environment (events bind to the digest) and a declared state-repo (artifacts.evidence.repo); the named environment must be declared.


#### `deploy.environments.<name>.gates`

Deployment gates enforced before this environment is deployed.

| Field | Type | Default |
|-------|------|---------|
| `deploy.environments.<name>.gates.require_digest` | `boolean` | `false` |
| `deploy.environments.<name>.gates.require_attestation` | `boolean` | `false` |
| `deploy.environments.<name>.gates.expected_builder` | `string` | -- |
| `deploy.environments.<name>.gates.expected_source` | `string` | -- |
| `deploy.environments.<name>.gates.requires_eligibility` | array of enum (`artifact_validated_for`, `artifact_authorized_for`) | -- |
| `deploy.environments.<name>.gates.verify_identity` | `string` | -- |
| `deploy.environments.<name>.gates.verify_issuer` | `string` | -- |

- **`deploy.environments.<name>.gates.require_digest`**

  When true, the deployment must use a digest-pinned image ref; the CD flow fails closed if the version cannot be resolved to a digest in the accepted channel.

- **`deploy.environments.<name>.gates.require_attestation`**

  When true, the CD flow verifies the signed SBOM and SLSA provenance attestations on the resolved digest before deploying, and checks the verified provenance against the deploy expectations (version being deployed, builder identity, source repository). Fails closed when an attestation is missing, does not verify, or does not satisfy the expectations.

- **`deploy.environments.<name>.gates.expected_builder`**

  Expected builder identity (regexp) matched against the verified provenance's runDetails.builder.id (the brik convention: <orchestrator-url>/-/brik/<runner-class>). Optional; absent only requires a non-empty builder id.

- **`deploy.environments.<name>.gates.expected_source`**

  Expected source repository (regexp) matched against the verified provenance's resolvedDependencies[0].uri. Optional.

- **`deploy.environments.<name>.gates.requires_eligibility`**

  PromotionJournal event types that must ALL exist for the resolved digest and this environment before deploying (all_of semantics). The journal is read from the project's state-repo (artifacts.evidence.repo); an unreachable journal, a missing state-repo declaration or a missing grant fails closed. An attested artifact is not an eligible artifact: attestation says where it comes from, eligibility says where it may go.

- **`deploy.environments.<name>.gates.verify_identity`**

  Expected signer identity (regexp) for keyless attestation verification (e.g. the CI job's certificate identity). Required when require_attestation is set and the referential's Signing backend is keyless.

- **`deploy.environments.<name>.gates.verify_issuer`**

  Expected OIDC issuer (regexp) for keyless attestation verification (e.g. the platform's Sigstore issuer). Required when require_attestation is set and the referential's Signing backend is keyless.


<!-- END AUTO-GENERATED -->

`deploy.environments` is a map: each key is an environment name and each value
is a [`$defs/deployEnvironment`](../../../schemas/config/v1/brik.schema.json)
object. Because that value is a referenced object, its fields are documented
here rather than expanded in the table above.

### Environment record

The fields below are common to every environment; the target-specific fields
(`namespace`, `chart`, `host`, ...) follow.

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `target` | enum | -- | `ssh`, `compose`, `k8s`, `helm`, `gitops`. Required when the environment is not fully covered by a `workflow` profile. |
| `when` | string | (always true) | Condition evaluated by the shared library: `branch == 'main'`, `tag =~ 'v*'`, `$CI_PIPELINE_SOURCE == 'merge_request_event'`. |
| `env_file` | string | -- | Path to a `KEY=VALUE` env file sourced before the deploy. Brik fails if the file is declared but missing. CI environment variables take precedence over file entries. |
| `source` | string | -- | Local path to the artifact directory uploaded by the `ssh` and `compose` targets, or to the rendered manifest tree pushed to the GitOps repo by the `gitops` target. Relative to the project root. |
| `strategy` | enum | -- | Rollout strategy: `rolling`, `blue-green`, `canary`. Wired for `k8s` and `helm` targets, where the deploy stage routes through `rollout.strategy.run` when set. `ssh` and `compose` targets ignore the field (no native primitive). Rollback callbacks are not yet implemented for `k8s` and `helm`, so `blue-green` and `canary` currently behave like `rolling` on deploy failure (no automatic switch-back); the rollback path is not yet wired. |

### Target-specific fields

| Target | Fields |
|--------|--------|
| `ssh` | `host`, `remote_path`, `restart_cmd`, `source` |
| `compose` | `compose_file`, `source`, and `host` + `remote_path` to deploy remotely over SSH |
| `k8s` | `namespace`, `manifest` |
| `helm` | `namespace`, `chart`, `release_name`, `values` |
| `gitops` | `repo`, `path`, `controller`, `app_name`, `source`, `git_token_var`, `auth_token_var` |

Targets ignore fields that do not apply to them; the schema rejects unknown
keys via `additionalProperties: false`.

### Examples

The per-environment fields live here because `deploy.environments` is a
referenced object the table above does not expand. Each example below shows a
complete, instructive environment.

k8s manifest deploy on `main`:

```yaml
version: 1
project:
  name: my-app
  stack: node
deploy:
  environments:
    production:
      when: "branch == 'main'"
      target: k8s
      namespace: production
      manifest: manifests/
```

Helm chart with environment-specific values:

```yaml
version: 1
project:
  name: my-app
  stack: node
deploy:
  environments:
    staging:
      when: "branch == 'develop'"
      target: helm
      namespace: staging
      chart: ./charts/myapp
      release_name: myapp-staging
      values: charts/values-staging.yaml
```

GitOps via ArgoCD:

```yaml
version: 1
project:
  name: api
  stack: node
deploy:
  environments:
    production:
      when: "tag =~ 'v*'"
      target: gitops
      repo: https://gitlab.example.com/org/infra.git
      path: services/api
      controller: argocd
      app_name: api-prod
      git_token_var: GIT_TOKEN
      auth_token_var: ARGOCD_TOKEN
```

`git_token_var` and `auth_token_var` are NAMES of CI variables.
`git_token_var` provides the token used to push the manifest update to the
GitOps repo (here `GIT_TOKEN` resolves to `$GIT_TOKEN`). Brik embeds the token
into the clone URL using HTTPS basic auth, so the `repo` field can stay
credential-free.

`auth_token_var` provides the token used by the GitOps controller
(`ARGOCD_TOKEN` -> `$ARGOCD_TOKEN`) to authenticate against ArgoCD's API for
the post-push sync. When `auth_token_var` is omitted, the argocd adapter falls
back to the conventional `ARGOCD_AUTH_TOKEN` env var. The deploy stage commits
the new image tag to the config repo and ArgoCD reconciles the change.

SSH to a single host:

```yaml
version: 1
project:
  name: my-app
  stack: node
deploy:
  environments:
    staging:
      when: "branch == 'main'"
      target: ssh
      host: staging.example.com
      remote_path: /srv/app
      restart_cmd: systemctl restart my-app
      env_file: deploy/staging.env
```

Multi-environment with a `workflow` profile:

```yaml
version: 1
project:
  name: my-app
  stack: node
deploy:
  workflow: github-flow
  environments:
    staging:
      target: helm
      namespace: staging
      chart: ./charts/myapp
      values: charts/values-staging.yaml
    production:
      when: "tag =~ 'v*'"
      target: helm
      namespace: production
      chart: ./charts/myapp
      values: charts/values-prod.yaml
      strategy: blue-green
```

The `github-flow` profile pre-configures the `staging` environment to deploy on
every push to `main`; the explicit user fields override the target and manifest
details. `production` keeps the explicit `when`.

Docker Compose on a remote host:

```yaml
version: 1
project:
  name: my-app
deploy:
  environments:
    staging:
      when: "branch == 'main'"
      target: compose
      host: staging.example.com
      remote_path: /opt/my-app
      compose_file: docker-compose.staging.yml
```

The `compose` target copies `compose_file` to `host:remote_path` and runs
`docker compose up -d` there. With no `host`, the same target deploys the
compose stack locally instead.

## See also

- [`release`](release.md) - `BRIK_APP_VERSION` semantics that drive the deployed tag
- [`git`](git.md) - identity used by the GitOps target's commit
- [`notify`](notify.md) - deploy outcome triggers notifications
- [`hooks`](hooks.md) - `pre_deploy` / `post_deploy` hooks
- [Fixed flows](../../concepts/fixed-flows.md) - where the Deploy stage sits in the flow
- [`brik.yml` reference](README.md) - all top-level sections
