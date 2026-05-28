# Public API surface: `findings`

> Source: `lib/transverse/findings*` (sub-notion physiquement nested sous transverse, traitée comme notion à part par layout.md §9).

## Public functions

| Function| Source file |
|---|---|
| `findings.from_sarif` | `transverse/findings.sh:59` |
| `findings.apply_policy` | `transverse/findings.sh:120` |
| `findings.aggregate` | `transverse/findings.sh:383` |
| `findings.process` | `transverse/findings.sh:527` |
| `findings.scan_gate` | `transverse/findings.sh:591` |
| `findings.gate` | `transverse/findings.sh:633` |
| `findings.from_json` | `transverse/findings.sh:697` |
| `findings.expiring_soon` | `transverse/findings.sh:766` |
| `findings.merge_pipeline` | `transverse/findings.sh:800` |

## Total

**9 unique public functions** in the sub-notion `findings`.

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
