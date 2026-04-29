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
| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `deploy.workflow` | enum (`trunk-based`, `git-flow`, `github-flow`) | -- | Git workflow convention for automatic environment mapping. When set, Brik loads a built-in profile that pre-configures environments based on branch/tag patterns. User-defined environments override profile defaults. |
| `deploy.environments` | object | -- | Named deployment environments. Each key is an environment name (e.g. staging, production). Each value defines the deployment condition and target. |

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
| `strategy` | enum | -- | Rollout strategy where supported by the target: `rolling`, `blue-green`, `canary`. |

### Target-specific fields

| Target | Fields |
|--------|--------|
| `ssh` | `host`, `remote_path`, `restart_cmd`, `compose_file` (when copying a compose stack) |
| `compose` | `compose_file` |
| `k8s` | `namespace`, `manifest` |
| `helm` | `namespace`, `chart`, `release_name`, `values` |
| `gitops` | `repo`, `path`, `controller`, `app_name` |

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
      repo: https://oauth2:${GIT_TOKEN}@gitlab.example.com/org/infra.git
      path: services/api
      controller: argocd
      app_name: api-prod
```

`repo` is a clonable git URL. Embed the auth token in the URL via a
CI variable (here `$GIT_TOKEN`); there is no separate `token_var`
field for the GitOps repo today. The deploy stage commits the new
image tag to the config repo and ArgoCD reconciles the change.

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
      target: ssh
      host: staging.example.com
      remote_path: /opt/my-app
      compose_file: docker-compose.staging.yml
      restart_cmd: docker compose up -d
```

## See also

- [`reference/release.md`](release.md) - `BRIK_APP_VERSION` semantics that drive the deployed tag
- [`reference/git.md`](git.md) - identity used by the GitOps target's commit
- [`reference/notify.md`](notify.md) - deploy outcome triggers notifications
- [`reference/hooks.md`](hooks.md) - `pre_deploy` / `post_deploy` hooks
- [`overview.md`](../overview.md) - declarative model
