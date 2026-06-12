# Credentials

How to configure secrets and credentials for Brik pipelines. For supply-chain
security and the infrastructure referential, see
[artifact attestation](../concepts/artifact-attestation.md).

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

## Infrastructure referential

The infrastructure referential (`BRIK_INFRA_DIR`) holds endpoints, credentials,
policies, and trust material. It is **not** part of `brik.yml`; instead, it is
a separate configuration tree mounted into every container:

- **Endpoints**: registry, git host, ArgoCD, Kubernetes, state-repo
- **Credentials**: resolved via `env://` or `file://` references (never inline values)
- **TLS posture**: system CA, custom CA bundle, or insecure (explicit and loud)
- **Trust material**: signing keys, cosign verification keys, allowed signers for
  evidence commits
- **Policy**: org-wide findings allowlist and expiration

Brik validates the referential **eagerly** at init and deploy. An invalid or
missing referential fails closed. On local execution, the referential is mounted
read-only at `/etc/brik/infra`; on CI platforms, it is delivered as a volume or
injected via the shared library setup.

For the full structure and validation rules, see
[artifact attestation](../concepts/artifact-attestation.md) and
[local execution](../concepts/local-execution.md).

---

## Signing credentials

Attestations are signed in the **Container Scan** stage. The signing credential
must be scoped to the signing container only so it never reaches user-defined
build, test, or lint scripts. This isolation claim is a prerequisite for
**SLSA Build L2**.

### GitLab CI

Create a `brik/signing` environment in your project and scope the signing
credential to it:

1. Go to **Settings > CI/CD > Variables**
2. Add your signing credential (e.g. `BRIK_SIGNING_BAO_TOKEN` for OpenBAO)
3. Set its **Environment scope** to `brik/signing`

The `brik-container-scan` job template already declares the `brik/signing`
environment (with `action: prepare`, so no deployment record is created):
GitLab delivers the scoped variable to that job only. Other jobs (build,
test, lint) never see it.

### Jenkins

Signing credentials are delivered via a dedicated env-file to the
`container-scan` container. The shared library wires them automatically:

1. Create the credential in **Manage Jenkins > Credentials** (e.g.,
   `brik-signing-bao-token` for OpenBAO)
2. The shared library delivers the signing env-file to the signing stage only

**Caveat**: If a credential is also declared as a **global Jenkins parameter**
(JCasC `globalNodeProperties`), `docker.inside()` re-injects all globals as
trailing `-e` flags on every container, leaking the signing secret. Keep signing
credentials **scoped to the signing stage** via `withCredentials` or per-stage
env-files, never as controller globals.

### Key names: BRIK_SIGNING_ prefix

Name all signing credentials with the `BRIK_SIGNING_` prefix so Brik can
identify and isolate them. Examples:

- `BRIK_SIGNING_COSIGN_KEY` -- cosign private key
- `BRIK_SIGNING_BAO_TOKEN` -- OpenBAO token for signing
- `BRIK_SIGNING_REGISTRY_USER`, `BRIK_SIGNING_REGISTRY_PASSWORD` -- registry
  credentials for writing attestations (remapped to `BRIK_REGISTRY_*` in the
  signing container only)

---

## Publish credentials

Publish credentials authenticate artifact uploads to package registries.
**The variable name is yours to choose** -- declare it via `token_var`,
`username_var`, or `password_var` in `brik.yml`, and Brik resolves the
matching CI variable at publish time.

For the full `publish` configuration reference, see
[`reference/publish.md`](../configuration/reference/publish.md).

### How the indirection works

```yaml
# brik.yml
publish:
  npm:
    token_var: MY_NPM_TOKEN          # name of the CI variable (your choice)
```

```
# CI platform
MY_NPM_TOKEN = npm_aBcDeFgHiJkL...    # value
```

At publish time Brik:

1. Reads `${MY_NPM_TOKEN}` from the environment.
2. Copies the value into the env var the publishing tool expects (see
   *Tool-internal variables* below) -- scoped to the publish step only.
3. Runs the tool, then unsets the internal variable.

You never have to name your CI variable `NPM_TOKEN`, `NUGET_API_KEY`,
or anything specific. It is purely a value source.

### Per-target field reference

| Target | Required `*_var` field(s) |
|--------|---------------------------|
| `publish.npm` | `token_var` |
| `publish.docker` | `username_var` + `password_var` |
| `publish.maven` | `username_var` + `password_var` |
| `publish.pypi` | `token_var` |
| `publish.cargo` | `token_var` |
| `publish.nuget` | `token_var` |

Scoped npm packages also accept `publish.npm.access: public | restricted`.

### Example (using conventional names)

You may name your CI variables after the conventional ecosystem names
if you prefer -- nothing in Brik enforces it, and it makes log lines
slightly easier to read.

```yaml
publish:
  npm:
    token_var: NPM_TOKEN
  docker:
    image: ghcr.io/org/my-app
    registry: ghcr.io
    username_var: GHCR_USER
    password_var: GHCR_TOKEN
  maven:
    repository: https://nexus.example.com/repository/maven-releases/
    username_var: MAVEN_USERNAME
    password_var: MAVEN_PASSWORD
  pypi:
    token_var: PYPI_API_TOKEN
  cargo:
    token_var: CARGO_REGISTRY_TOKEN
  nuget:
    token_var: NUGET_API_KEY
```

### Tool-internal variables

For curiosity / log-reading: Brik copies the resolved credential into
the env var the underlying tool natively reads, then unsets it. You do
not need to set these yourself.

| Tool | Internal env var |
|------|-------------------|
| npm CLI | `NPM_TOKEN` (used in a generated `.npmrc`) |
| nuget CLI | `NUGET_API_KEY` |
| twine (PyPI fallback) | `TWINE_USERNAME`, `TWINE_PASSWORD` |
| uv (PyPI primary) | `UV_PUBLISH_TOKEN` |
| poetry (PyPI) | `POETRY_PYPI_TOKEN_PYPI` |
| maven CLI | written to a temporary `settings.xml` (chmod 600) |
| docker CLI | injected into a temporary `DOCKER_CONFIG`, login via `--password-stdin` |
| cargo CLI | passed via `CARGO_REGISTRIES_<NAME>_TOKEN` |

---

## Deploy credentials

Deploy credentials are **not** configured via `brik.yml` indirection. They are
environment variables that the Brik runtime reads directly at deploy time, and
they are **separate from CI publish credentials** for security isolation. A CD
job (the decoupled `brik deploy` verb) receives a distinct set of deploy
credentials with read-only permissions on the registry and write access to the
target platform only.

This separation means revoking the CI publish account does not strand a
deployment, and the production pull account cannot push to the registry.

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

Host key policy comes from the infrastructure referential: the `SshTarget`
endpoint declaring the host carries the `known_hosts` reference, or an
explicit `strict_host_key: false` opt-out. An undeclared host fails closed.

**Note on SSH_PRIVATE_KEY format:** This variable can contain either the key content
directly (inline) or a file path. GitLab CI "File" type variables automatically write
the content to a temporary file and set the variable to the file path -- Brik handles
both cases transparently.

### Kubernetes (k8s and helm targets)

| CI variable | Description |
|-------------|-------------|
| `KUBECONFIG` | Path to the kubeconfig file. On GitLab, use a "File" type variable. |

Cluster trust (CA material or `insecure-skip-tls-verify`) lives inside the
kubeconfig itself; there is no kubectl flag passthrough.

### ArgoCD (gitops target with controller: argocd)

| CI variable | Description |
|-------------|-------------|
| `ARGOCD_AUTH_TOKEN` | ArgoCD authentication token |

The server address and TLS posture come from the referential's `ArgoCD`
endpoint (an explicit `--server` flag still wins when a caller passes one).

### GitOps config repo (gitops target)

The `gitops` target clones a configuration repository, updates the
image tag, and pushes the change. The schema field
`deploy.environments.<env>.repo` takes a clonable git URL; there is no
separate token field today, so credentials must be embedded in the URL
or provided via SSH.

- **HTTPS**: embed credentials in the repo URL using a CI variable
  (e.g. `repo: https://oauth2:${GIT_TOKEN}@gitlab.example.com/org/infra.git`)
- **SSH**: use an SSH URL (`repo: git@github.com:org/infra.git`) and
  provide `SSH_PRIVATE_KEY` with read/write access on the config repo

### Notifications

| CI variable | Description |
|-------------|-------------|
| `SLACK_WEBHOOK_URL` | Slack Incoming Webhook URL (default for `notify.slack`). Override the variable name via `BRIK_NOTIFY_SLACK_WEBHOOK_VAR=MY_SLACK_VAR`. |
| `BRIK_NOTIFY_WEBHOOK_URL` | Default webhook URL for `notify.webhook`. Override via the `--url-var` flag when calling `notify.webhook` directly. |

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

- **Never commit secrets** to `brik.yml`, the infrastructure referential, or any
  file in version control
- **Credentials in the referential use `env://` or `file://` references**, never
  inline values. Brik resolves them at use time.
- **Mask variables** in your CI platform to prevent them from appearing in job
  logs
- **Protect variables** so they are only available on protected branches/tags
- **Use "File" type variables** (GitLab) for multi-line secrets like SSH keys
  and kubeconfig -- this avoids encoding issues
- **Separate CI and CD credentials**. The publish account (CI) and the deploy
  account (CD) should map to distinct identities at the provider. Revoking one
  does not break the other.
- **Scope signing credentials to the signing container** (GitLab `brik/signing`
  environment, Jenkins per-stage env-files with `BRIK_SIGNING_` prefix). Never
  declare them as controller globals.
- **Rotate credentials** regularly and at the secret-manager level. Brik reads
  every credential at use time, so rotation is transparent.
- **Scope credentials** to the minimum required permissions (read-only tokens
  for CD resolution, scoped npm tokens, etc.)
- **Use short-lived tokens** when your provider supports them (e.g., OIDC tokens
  for cloud providers, project access tokens with expiry on GitLab)
