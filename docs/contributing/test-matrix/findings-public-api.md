# Public API surface: `findings`

> Source: `lib/transverse/findings*` (sub-notion physiquement nested sous transverse, traitée comme notion à part par layout.md §9).

## Public functions

<!-- BEGIN AUTO-GENERATED: public-api -->
| Function| Source file |
|---|---|
| `findings.aggregate` | `transverse/findings/aggregate.sh:45` |
| `findings.merge_pipeline` | `transverse/findings/aggregate.sh:154` |
| `findings.converters.bandit.to_sarif` | `transverse/findings/converters/bandit.sh:43` |
| `findings.converters.clippy.to_sarif` | `transverse/findings/converters/clippy.sh:36` |
| `findings.converters.dockle.to_sarif` | `transverse/findings/converters/dockle.sh:30` |
| `findings.converters.junit.to_sarif` | `transverse/findings/converters/junit.sh:27` |
| `findings.converters.ruff.to_sarif` | `transverse/findings/converters/ruff.sh:33` |
| `findings.converters.scancode.to_sarif` | `transverse/findings/converters/scancode.sh:34` |
| `findings.converters.trufflehog.to_sarif` | `transverse/findings/converters/trufflehog.sh:21` |
| `findings.exporters.gitlab.from_sarif` | `transverse/findings/exporters/gitlab.sh:31` |
| `findings.process` | `transverse/findings/gate.sh:40` |
| `findings.scan_gate` | `transverse/findings/gate.sh:104` |
| `findings.gate` | `transverse/findings/gate.sh:146` |
| `findings.from_sarif` | `transverse/findings/ingest.sh:29` |
| `findings.from_json` | `transverse/findings/ingest.sh:73` |
| `org_policy.cache_path` | `transverse/findings/org_policy.sh:24` |
| `org_policy.is_active` | `transverse/findings/org_policy.sh:35` |
| `_org_policy._glob_to_regex` | `transverse/findings/org_policy.sh:46` |
| `_org_policy._epoch_to_date` | `transverse/findings/org_policy.sh:74` |
| `org_policy.load` | `transverse/findings/org_policy.sh:94` |
| `org_policy.state_repo_protection` | `transverse/findings/org_policy.sh:250` |
| `org_policy.expiring_soon` | `transverse/findings/org_policy.sh:296` |
| `findings.apply_policy` | `transverse/findings/policy.sh:55` |
| `findings.expiring_soon` | `transverse/findings/policy.sh:276` |

## Total

**24 unique public functions** in notion `findings`.
<!-- END AUTO-GENERATED -->

## Outputs publiés (observés sur campagne v0.6.0)

La notion `findings` est transverse aux stages `lint`, `sast`, `scan`, `container-scan`. Elle normalise (pivot SARIF), classifie (fix-classification), et exporte (platform-aware).

### Fichiers produits

| Fichier | Producteur | Notes |
|---|---|---|
| `brik-artifacts/<verify-stage>/<verify-stage>.sarif` | lint/sast/scan/container-scan | SARIF pivot normalisé par stage |
| `brik-artifacts/aggregate.sarif` | notify (findings.exporter) | agrégat multi-stages |
| `brik-artifacts/gl-sast-report.json` (GitLab-aware) | findings.exporter.gitlab | export GitLab security dashboard |
| `<stage>-summary.json` enrichi (champs business.*) | findings.classifier | (à venir master #1) intégration `business.{status, reason}` dans les summaries |

### Pipeline canonique findings

```
scanner natif -> SARIF natif -> findings.pivot.normalize -> SARIF pivot
                                                          -> findings.classifier.fix_classify -> annoté
                                                          -> findings.exporter.<platform>     -> output platform-spécifique
```
