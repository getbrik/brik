# Credentials

How to configure secrets and credentials for Brik pipelines.

## Indirection principle

Brik never stores secrets in `brik.yml`. Instead, it uses **credential indirection**:
`brik.yml` contains the **name** of an environment variable, and the CI platform
provides the **value** at runtime.

```yaml
# brik.yml -- contains the variable NAME, not the secret
publish:
  npm:
    token_var: NPM_TOKEN      # <-- name of the CI variable
```

```
CI platform (GitLab, Jenkins, GitHub):
  NPM_TOKEN = "npm_aBcDeFgHiJkL..."   # <-- actual secret value
```

This separation means:
- `brik.yml` can be committed safely to version control
- Secrets are managed exclusively in the CI platform
- The same `brik.yml` works across environments with different credentials

---

## Publish credentials

Publish credentials authenticate artifact uploads to package registries. They are
configured under the `publish` section of `brik.yml` using `token_var`, `username_var`,
and `password_var` keys.

For the full `publish` configuration reference, see [reference.md](reference.md#publish).

### npm

```yaml
publish:
  npm:
    registry: https://registry.npmjs.org   # optional, this is the default
    token_var: NPM_TOKEN
```

| CI variable | Description |
|-------------|-------------|
| `NPM_TOKEN` | npm authentication token (from `npm token create`) |

### Docker

```yaml
publish:
  docker:
    image: ghcr.io/my-org/my-app
    registry: ghcr.io
    username_var: DOCKER_USERNAME
    password_var: DOCKER_PASSWORD
```

| CI variable | Description |
|-------------|-------------|
| `DOCKER_USERNAME` | Registry username |
| `DOCKER_PASSWORD` | Registry password or personal access token |

### Maven

```yaml
publish:
  maven:
    repository: https://nexus.example.com/repository/maven-releases/
    username_var: NEXUS_USERNAME
    password_var: NEXUS_PASSWORD
```

| CI variable | Description |
|-------------|-------------|
| `NEXUS_USERNAME` | Repository username |
| `NEXUS_PASSWORD` | Repository password |

### PyPI

```yaml
publish:
  pypi:
    repository: https://upload.pypi.org/legacy/   # optional, this is the default
    token_var: PYPI_TOKEN
```

| CI variable | Description |
|-------------|-------------|
| `PYPI_TOKEN` | PyPI API token (starts with `pypi-`) |

### Cargo (crates.io)

```yaml
publish:
  cargo:
    registry: crates-io   # optional, this is the default
    token_var: CARGO_REGISTRY_TOKEN
```

| CI variable | Description |
|-------------|-------------|
| `CARGO_REGISTRY_TOKEN` | crates.io API token |

### NuGet

```yaml
publish:
  nuget:
    source: https://api.nuget.org/v3/index.json   # optional, this is the default
    token_var: NUGET_API_KEY
```

| CI variable | Description |
|-------------|-------------|
| `NUGET_API_KEY` | NuGet API key |

---

## Deploy credentials

Deploy credentials are **not** configured via `brik.yml` indirection. They are
environment variables that the Brik runtime reads directly at deploy time.

### Docker Registry (compose target)

When deploying with `target: compose`, the runtime authenticates to a Docker registry
to pull images if these variables are set:

| CI variable | Description |
|-------------|-------------|
| `BRIK_REGISTRY_HOST` | Registry hostname (e.g. `registry.example.com`) |
| `BRIK_REGISTRY_USER` | Registry username |
| `BRIK_REGISTRY_PASSWORD` | Registry password or token |

### SSH (ssh and compose targets)

The `ssh` and `compose` (remote) targets use SSH to connect to the deployment host.

| CI variable | Description |
|-------------|-------------|
| `SSH_PRIVATE_KEY` | SSH private key content or file path (see note below) |
| `BRIK_SSH_STRICT_HOST_KEY` | Set to `no` to disable strict host key checking (default: `yes`) |

**Note on SSH_PRIVATE_KEY format:** This variable can contain either the key content
directly (inline) or a file path. GitLab CI "File" type variables automatically write
the content to a temporary file and set the variable to the file path -- Brik handles
both cases transparently.

### Kubernetes (k8s and helm targets)

| CI variable | Description |
|-------------|-------------|
| `KUBECONFIG` | Path to the kubeconfig file. On GitLab, use a "File" type variable. |
| `BRIK_KUBECTL_OPTS` | Extra options appended to every `kubectl` command (e.g. `--insecure-skip-tls-verify`) |

### ArgoCD (gitops target with controller: argocd)

| CI variable | Description |
|-------------|-------------|
| `ARGOCD_SERVER` | ArgoCD server address (e.g. `argocd.example.com:443`) |
| `ARGOCD_AUTH_TOKEN` | ArgoCD authentication token |

### GitOps config repo (gitops target)

The `gitops` target clones a configuration repository, updates the image tag, and
pushes the change. Authentication to the config repo depends on the protocol:

- **HTTPS**: Embed credentials in the repo URL using a CI variable
  (e.g. `https://token:${GIT_TOKEN}@gitlab.example.com/org/infra.git`)
- **SSH**: Provide `SSH_PRIVATE_KEY` with access to the config repo

### Notifications

| CI variable | Description |
|-------------|-------------|
| `SLACK_WEBHOOK_URL` | Slack Incoming Webhook URL (for `notify.slack`) |

---

## Platform setup examples

### GitLab CI

GitLab CI variables are configured in **Settings > CI/CD > Variables**.

1. Go to your project (or group) settings
2. Navigate to **CI/CD > Variables**
3. Click **Add variable**
4. Set:
   - **Key**: the variable name (e.g. `NPM_TOKEN`)
   - **Value**: the secret value
   - **Type**: "Variable" for tokens, "File" for SSH keys and kubeconfig
   - **Protected**: enable for production secrets (only available on protected branches/tags)
   - **Masked**: enable to hide the value in job logs

```
Example variables:
  NPM_TOKEN          = npm_aBcDeFgHiJkL...     (Variable, Masked)
  SSH_PRIVATE_KEY     = -----BEGIN OPENSSH...    (File, Protected)
  KUBECONFIG          = apiVersion: v1...        (File, Protected)
  ARGOCD_AUTH_TOKEN   = eyJhbGciOiJI...         (Variable, Masked, Protected)
```

**Tip:** For SSH keys, always use "File" type -- this avoids newline issues and the
Brik runtime detects file paths automatically.

### Jenkins

Jenkins credentials are configured in **Manage Jenkins > Credentials**.

1. Go to **Manage Jenkins > Credentials > System > Global credentials**
2. Click **Add Credentials**
3. Choose the appropriate kind:
   - **Secret text** for tokens (NPM_TOKEN, ARGOCD_AUTH_TOKEN, etc.)
   - **SSH Username with private key** for SSH_PRIVATE_KEY
   - **Secret file** for KUBECONFIG

Brik's Jenkins shared library maps credentials to environment variables automatically.
In your `Jenkinsfile`, credentials are injected via the Jenkins Credentials Binding
plugin. The Brik Jenkins shared library handles the mapping -- you only need to create
the credentials in Jenkins with the expected IDs.

```
Example credential IDs:
  npm-token           -> NPM_TOKEN
  ssh-deploy-key      -> SSH_PRIVATE_KEY
  kubeconfig-staging  -> KUBECONFIG
  argocd-token        -> ARGOCD_AUTH_TOKEN
```

### GitHub Actions

GitHub secrets are configured in **Settings > Secrets and variables > Actions**.

1. Go to your repository settings
2. Navigate to **Secrets and variables > Actions**
3. Click **New repository secret**
4. Set the name and value

In your workflow, pass secrets as environment variables:

```yaml
jobs:
  pipeline:
    runs-on: ubuntu-latest
    env:
      NPM_TOKEN: ${{ secrets.NPM_TOKEN }}
      SSH_PRIVATE_KEY: ${{ secrets.SSH_PRIVATE_KEY }}
      KUBECONFIG: ${{ secrets.KUBECONFIG }}
      ARGOCD_AUTH_TOKEN: ${{ secrets.ARGOCD_AUTH_TOKEN }}
```

---

## Security best practices

- **Never commit secrets** to `brik.yml` or any file in version control
- **Mask variables** in your CI platform to prevent them from appearing in job logs
- **Protect variables** so they are only available on protected branches/tags
- **Use "File" type variables** (GitLab) for multi-line secrets like SSH keys and kubeconfig -- this avoids encoding issues
- **Rotate credentials** regularly and after any suspected exposure
- **Scope credentials** to the minimum required permissions (read-only tokens when possible, scoped npm tokens, etc.)
- **Use short-lived tokens** when your CI platform supports them (e.g. OIDC tokens for cloud providers)
