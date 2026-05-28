# Sprint S2 Purity Audit

Static audit of `brik/spec/_legacy/` specs against the L1 purity criterion:
"A spec must run inside a minimal Alpine container (bash + jq + yq +
ShellSpec). If it invokes `docker`, `kubectl`, `grype`, `npm`, etc., it
belongs to L2."

## Method

A spec is classified **L2-bound** when its content matches any of the
following CLI-invocation patterns (real, not mocked):

```
docker run|docker build|docker pull|docker push|docker buildx
kubectl apply|kubectl get|kubectl create|kubectl delete|kubectl rollout|kubectl exec
helm install|helm upgrade|helm template|helm rollback
argocd app|argocd login
grype dir:|grype sbom:|trivy fs|trivy image
gitleaks detect|trufflehog filesystem|semgrep ci|semgrep --
npm publish|npm install --prefix|pip install|cargo publish|mvn deploy|gradle publish
ssh -o|scp -o
```

Specs that do NOT match these patterns are classified **L1-pure** and
candidate for migration to `spec/unit/<notion>/`.

## Results

| Notion | L1-pure | L2-bound | Total |
|---|---:|---:|---:|
| cli | 22 | 0 | 22 |
| deployments | 2 | 4 | 6 |
| integration | 13 | 1 | 14 |
| package-managers | 2 | 4 | 6 |
| pipeline | 40 | 1 | 41 |
| planning | 4 | 0 | 4 |
| registry | 7 | 0 | 7 |
| rollout | 1 | 2 | 3 |
| schemas | 7 | 0 | 7 |
| stacks | 9 | 3 | 12 |
| stages | 30 | 6 | 36 |
| transverse | 46 | 2 | 48 |
| **TOTAL** | **183** | **23** | **206** |

## L2-bound specs (stay in `_legacy/` until S3)

```
deployments/argocd_spec.sh
deployments/gitops_spec.sh
deployments/helm_spec.sh
deployments/k8s_spec.sh
integration/stage_quality_security_spec.sh
package-managers/cargo_spec.sh
package-managers/docker_spec.sh
package-managers/maven_spec.sh
package-managers/npm_spec.sh
pipeline/report_render_html_spec.sh
rollout/health_spec.sh
rollout/strategy_spec.sh
stacks/_deps_spec.sh
stacks/docker_spec.sh
stacks/python_spec.sh
stages/lint_spec.sh
stages/package_spec.sh
stages/promote_spec.sh
stages/scan_spec.sh
stages/test_spec.sh
stages/verify/scan/secret_spec.sh
transverse/config_export_core_spec.sh
transverse/config_validate_publish_spec.sh
```

These 23 specs invoke external CLIs that the Alpine baseline does not
ship. They will migrate to `spec/integration/` (L2) during S3 when the
notion-pair test architecture lands.

## Migration order

S2 migrates the 183 L1-pure specs to `spec/unit/<notion>/`. Recommended
order, starting with the cleanest notions:

1. **Quick wins** (all-L1 notions): `planning` (4) + `registry` (7) +
   `schemas` (7) = 18 specs
2. **Pilot validation**: a subset of `transverse` helpers (yaml, csv,
   severity, conditions, junit) to validate the migration mechanics
3. **Bulk**: `cli` (22) + `pipeline` (40) + `stages` (30) + remainder of
   `transverse` (46) = 138 specs
4. **Cleanup**: `integration` (13) + `stacks` (9) + the partial notions
   (`deployments` 2, `package-managers` 2, `rollout` 1) = 27 specs

Each migration follows the same procedure:

```bash
# 1. Move
git mv brik/spec/_legacy/<notion>/<spec>.sh brik/spec/unit/<notion>/<spec>.sh

# 2. Validate paths still resolve (the spec uses $BRIK_HOME for Includes)
shellspec brik/spec/unit/<notion>/<spec>.sh

# 3. Run the full unit/ layer to confirm no regression
shellspec brik/spec/unit/
```

The legacy `_legacy/` directory shrinks as specs migrate. At end of S2 it
should hold only the 23 L2-bound specs, ready for S3.
