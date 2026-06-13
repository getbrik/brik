# Public API surface: `planning`

> Source: `lib/planning/**/*.sh`.

## Public functions

Format: `<notion>.<submodule>.<verb>` (convention layout.md).

| Function| Source file |
|---|---|
| `impact.match_one` | `planning/impact.sh:32` |
| `impact.match_any` | `planning/impact.sh:49` |
| `impact.stage_patterns` | `planning/impact.sh:66` |
| `impact.stage_is_impacted` | `planning/impact.sh:103` |
| `impact.stage_matched_globs` | `planning/impact.sh:128` |
| `plan.stages.ordered` | `planning/plan.sh:22` |
| `plan.dag.edges` | `planning/plan.sh:31` |
| `plan.decide` | `planning/plan.sh:68` |
| `plan.compute` | `planning/plan.sh:126` |
| `_plan_reader._resolve_path` | `planning/plan_reader.sh:22` |
| `pipeline.plan.should_run` | `planning/plan_reader.sh:47` |
| `pipeline.plan.reason` | `planning/plan_reader.sh:67` |
| `pipeline.plan.runner_class` | `planning/plan_reader.sh:80` |
| `pipeline.plan.gate` | `planning/plan_reader.sh:93` |
| `pipeline.plan.stages` | `planning/plan_reader.sh:107` |
| `pipeline.plan.fingerprint` | `planning/plan_reader.sh:118` |
| `pipeline.plan.release_profile` | `planning/plan_reader.sh:134` |
| `pipeline.plan.release_version` | `planning/plan_reader.sh:146` |
| `pipeline.plan.is_candidate` | `planning/plan_reader.sh:158` |
| `plan_writer.from_stream` | `planning/plan_writer.sh:21` |
| `plan_writer.write` | `planning/plan_writer.sh:170` |

## Total

**21 unique public functions** in notion `planning`.

## Outputs publiés (observés sur campagne v0.6.0)

La notion `planning` écrit `.brik-logs/plan.json` consommé par chaque stage via `brik plan gate <stage>`.

### Schéma observé `plan.json`

| Champ | Type | Notes |
|---|---|---|
| `schemaVersion` | string | version du contrat plan.json (ex: "1") |
| `brikVersion` | string | version brik qui a généré le plan (ex: "0.6.0") |
| `context` | string | contexte d'exécution ("release", "snapshot", ...) |
| `mode` | string | mode planner ("safe", "balanced", ...) |
| `workspace` | object | métadonnées du workspace courant |
| `changes` | object | `{files, from_ref, to_ref, source}`, résultat de l'analyse d'impact |
| `release` | object | métadonnées de release (tag, version calculée) |
| `stages` | array/object | décisions par stage (RUN / SKIP avec reason) |
| `dag` | object | `{edges: [{from, to}], ...}`, DAG d'orchestration |
| `fingerprint` | string | hash byte-reproductible du plan |
