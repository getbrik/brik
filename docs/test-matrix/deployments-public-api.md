# Public API surface: `deployments`

> Source: `lib/deployments/**/*.sh`.

## Public functions

Format: `<notion>.<submodule>.<verb>` (convention layout.md).

| Function| Source file |
|---|---|
| `_deploy.argocd._validate_app_name` | `deployments/argocd.sh:15` |
| `_deploy.argocd._add_server_auth` | `deployments/argocd.sh:29` |
| `deploy.argocd.sync` | `deployments/argocd.sh:58` |
| `deploy.argocd.wait_healthy` | `deployments/argocd.sh:113` |
| `deploy.argocd.rollback` | `deployments/argocd.sh:163` |
| `deploy.argocd.diff` | `deployments/argocd.sh:235` |
| `deploy.argocd.status` | `deployments/argocd.sh:273` |
| `deploy.argocd.is_synced` | `deployments/argocd.sh:327` |
| `deploy.argocd.deploy` | `deployments/argocd.sh:366` |
| `deploy.compose.run` | `deployments/compose.sh:13` |
| `_deploy.gitops._inject_token` | `deployments/gitops.sh:21` |
| `_deploy.gitops._safe_url` | `deployments/gitops.sh:39` |
| `deploy.gitops.render_manifests` | `deployments/gitops.sh:46` |
| `deploy.gitops.push_manifests` | `deployments/gitops.sh:150` |
| `deploy.gitops.wait_sync` | `deployments/gitops.sh:276` |
| `deploy.gitops.diff` | `deployments/gitops.sh:311` |
| `deploy.gitops.rollback` | `deployments/gitops.sh:370` |
| `deploy.gitops.run` | `deployments/gitops.sh:469` |
| `deploy.helm.run` | `deployments/helm.sh:13` |
| `deploy.ssh.run` | `deployments/ssh.sh:13` |

## Total

**20 unique public functions** in notion `deployments`.
