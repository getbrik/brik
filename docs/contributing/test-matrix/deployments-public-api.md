# Public API surface: `deployments`

> Source: `lib/deployments/**/*.sh`.

## Public functions

Format: `<notion>.<submodule>.<verb>` (convention layout.md).

<!-- BEGIN AUTO-GENERATED: public-api -->
| Function| Source file |
|---|---|
| `deploy.image_ref.is_pinned` | `deployments/_image_ref.sh:21` |
| `deploy.image_ref.extract_digest` | `deployments/_image_ref.sh:30` |
| `deploy.image_ref.pinned` | `deployments/_image_ref.sh:44` |
| `_deploy.argocd._validate_app_name` | `deployments/argocd.sh:15` |
| `_deploy.argocd._add_server_auth` | `deployments/argocd.sh:34` |
| `deploy.argocd.sync` | `deployments/argocd.sh:91` |
| `deploy.argocd.wait_healthy` | `deployments/argocd.sh:159` |
| `deploy.argocd.rollback` | `deployments/argocd.sh:209` |
| `deploy.argocd.diff` | `deployments/argocd.sh:281` |
| `deploy.argocd.status` | `deployments/argocd.sh:319` |
| `deploy.argocd.get_deployed_digest` | `deployments/argocd.sh:375` |
| `deploy.argocd.is_synced` | `deployments/argocd.sh:424` |
| `deploy.argocd.deploy` | `deployments/argocd.sh:463` |
| `deploy.compose.run` | `deployments/compose.sh:13` |
| `deploy.compose.get_deployed_digest` | `deployments/compose.sh:142` |
| `_deploy.gitops._inject_token` | `deployments/gitops.sh:22` |
| `_deploy.gitops._safe_url` | `deployments/gitops.sh:28` |
| `deploy.gitops.render_manifests` | `deployments/gitops.sh:36` |
| `deploy.gitops.push_manifests` | `deployments/gitops.sh:140` |
| `deploy.gitops.wait_sync` | `deployments/gitops.sh:270` |
| `deploy.gitops.diff` | `deployments/gitops.sh:305` |
| `deploy.gitops.rollback` | `deployments/gitops.sh:377` |
| `deploy.gitops.run` | `deployments/gitops.sh:476` |
| `deploy.helm.run` | `deployments/helm.sh:13` |
| `deploy.helm.get_deployed_digest` | `deployments/helm.sh:111` |
| `deploy.k8s.run` | `deployments/k8s.sh:13` |
| `deploy.k8s.get_deployed_digest` | `deployments/k8s.sh:85` |
| `_deploy.readback._resolve` | `deployments/readback.sh:14` |
| `_deploy.readback._k8s_deployment_name` | `deployments/readback.sh:21` |
| `_deploy.readback._live` | `deployments/readback.sh:31` |
| `deploy.readback.live_digest` | `deployments/readback.sh:102` |
| `deploy.readback.record` | `deployments/readback.sh:120` |
| `deploy.ssh.run` | `deployments/ssh.sh:13` |
| `deploy.ssh.get_deployed_digest` | `deployments/ssh.sh:141` |

## Total

**34 unique public functions** in notion `deployments`.
<!-- END AUTO-GENERATED -->
