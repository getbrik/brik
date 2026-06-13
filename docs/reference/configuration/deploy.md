# `deploy` configuration

> Schema source: [`brik.schema.json#$defs/deploy`](../../../schemas/config/v1/brik.schema.json)

The `deploy` section declares one or more named environments and the
target each one ships to. The deploy stage iterates over the
environments map, evaluates each environment's `when` condition, and
runs the matching target adapter when the condition is true.

The whole section is optional. With no `deploy` block the deploy stage
is skipped.

## Top-level shape

<!-- BEGIN AUTO-GENERATED: quick-reference -->
| Field | Type | Default |
|-------|------|---------|
| `deploy.workflow` | enum (`trunk-based`, `git-flow`, `github-flow`) | -- |
| `deploy.environments` | `object` | -- |

- **`deploy.workflow`**

  Git workflow convention for automatic environment mapping. When set, Brik loads a built-in profile that pre-configures environments based on branch/tag patterns. User-defined environments override profile defaults.

- **`deploy.environments`**

  Named deployment environments. Each key is an environment name (e.g. staging, production). Each value defines the deployment condition and target.


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


<!-- END AUTO-GENERATED -->

`deploy.environments` is a map: each key is an environment name and
each value matches the [`deployEnvironment`](#environment-record)
schema below.

## Environment record

Every value under `deploy.environments` is a
[`$defs/deployEnvironment`](../../../schemas/config/v1/brik.schema.json)
object. The fields below are common; the target-specific fields
(`namespace`, `chart`, `host`, ...) are documented in the per-target
sections.

### Common fields

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `target` | enum | -- | `ssh`, `compose`, `k8s`, `helm`, `gitops`. Required when the environment is not fully covered by a `workflow` profile. |
| `when` | string | (always true) | Condition evaluated by the shared library: `branch == 'main'`, `tag =~ 'v*'`, `$CI_PIPELINE_SOURCE == 'merge_request_event'`. |
| `env_file` | string | -- | Path to a `KEY=VALUE` env file sourced before the deploy. Brik fails if the file is declared but missing. CI environment variables take precedence over file entries. |
| `source` | string | -- | Local path to the artifact directory uploaded by the `ssh` and `compose` targets, or to the rendered manifest tree pushed to the GitOps repo by the `gitops` target. Relative to the project root. |
| `strategy` | enum | -- | Rollout strategy: `rolling`, `blue-green`, `canary`. Wired for `k8s` and `helm` targets - the deploy stage routes through `rollout.strategy.run` when set. `ssh` and `compose` targets ignore the field (no native primitive). Rollback callbacks are not yet implemented for `k8s` and `helm`, so `blue-green` and `canary` currently behave like `rolling` on deploy failure (no automatic switch-back); the rollback path is not yet wired. |

### Target-specific fields

| Target | Fields |
|--------|--------|
| `ssh` | `host`, `remote_path`, `restart_cmd`, `compose_file` (when copying a compose stack), `source` |
| `compose` | `compose_file`, `source` |
| `k8s` | `namespace`, `manifest` |
| `helm` | `namespace`, `chart`, `release_name`, `values` |
| `gitops` | `repo`, `path`, `controller`, `app_name`, `source`, `git_token_var`, `auth_token_var` |

Targets ignore fields that don't apply to them; the schema rejects
unknown keys via `additionalProperties: false`.

## Examples

### k8s manifest deploy on `main`

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

### Helm chart with environment-specific values

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

### GitOps via ArgoCD

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
`git_token_var` provides the token used to push the manifest update
to the GitOps repo (here `GIT_TOKEN` resolves to `$GIT_TOKEN`). Brik
embeds the token into the clone URL using HTTPS basic auth, so the
`repo` field can stay credential-free.

`auth_token_var` provides the token used by the GitOps controller
(`ARGOCD_TOKEN` -> `$ARGOCD_TOKEN`) to authenticate against ArgoCD's
API for the post-push sync. When `auth_token_var` is omitted, the
argocd adapter falls back to the conventional `ARGOCD_AUTH_TOKEN` env
var. The deploy stage commits the new image tag to the config repo and
ArgoCD reconciles the change.

### SSH to a single host

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

### Multi-environment with `workflow` profile

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

The `github-flow` profile pre-configures the `staging` environment to
deploy on every push to `main`; the explicit user fields override the
target/manifest details. `production` keeps the explicit `when`.

### Docker Compose on a remote host

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

- [`reference/release.md`](release.md) - `BRIK_APP_VERSION` semantics that drive the deployed tag
- [`reference/git.md`](git.md) - identity used by the GitOps target's commit
- [`reference/notify.md`](notify.md) - deploy outcome triggers notifications
- [`reference/hooks.md`](hooks.md) - `pre_deploy` / `post_deploy` hooks
- [`overview.md`](overview.md) - declarative model
