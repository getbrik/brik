# Public API surface: `execution`

> Source: `lib/pipeline/**/*.sh`.

## Public functions

Format: `<notion>.<submodule>.<verb>` (convention layout.md).

<!-- BEGIN AUTO-GENERATED: public-api -->
| Function| Source file |
|---|---|
| `banner.brik` | `pipeline/banner.sh:25` |
| `banner.stage` | `pipeline/banner.sh:55` |
| `_bootstrap._is_brik_runner` | `pipeline/bootstrap.sh:36` |
| `_bootstrap._is_virtualized` | `pipeline/bootstrap.sh:46` |
| `_bootstrap._detect_system_pkg_manager` | `pipeline/bootstrap.sh:61` |
| `_bootstrap._tool_command` | `pipeline/bootstrap.sh:78` |
| `_bootstrap._ensure_brik_bin` | `pipeline/bootstrap.sh:99` |
| `_bootstrap._self_host_binary` | `pipeline/bootstrap.sh:114` |
| `_bootstrap._install_via_apk` | `pipeline/bootstrap.sh:145` |
| `_bootstrap._install_via_apt` | `pipeline/bootstrap.sh:171` |
| `_bootstrap._install_via_yum` | `pipeline/bootstrap.sh:202` |
| `_bootstrap._install_via_dnf` | `pipeline/bootstrap.sh:228` |
| `_bootstrap._install_via_mise` | `pipeline/bootstrap.sh:258` |
| `_bootstrap._sys_pkg_install` | `pipeline/bootstrap.sh:294` |
| `_bootstrap._yq_url` | `pipeline/bootstrap.sh:323` |
| `_bootstrap._jq_url` | `pipeline/bootstrap.sh:337` |
| `bootstrap.install_yq` | `pipeline/bootstrap.sh:359` |
| `bootstrap.install_prerequisites` | `pipeline/bootstrap.sh:399` |
| `bootstrap.install_stack` | `pipeline/bootstrap.sh:465` |
| `bootstrap.check_stack` | `pipeline/bootstrap.sh:530` |
| `_bootstrap._python_post_install` | `pipeline/bootstrap.sh:572` |
| `bootstrap.prepare_env` | `pipeline/bootstrap.sh:613` |
| `_business._validate_count` | `pipeline/business.sh:48` |
| `business.evaluate` | `pipeline/business.sh:71` |
| `context.create` | `pipeline/context.sh:20` |
| `_context._get` | `pipeline/context.sh:65` |
| `_context._set` | `pipeline/context.sh:77` |
| `_context._set_result` | `pipeline/context.sh:100` |
| `_context._exists` | `pipeline/context.sh:114` |
| `error.raise` | `pipeline/error.sh:52` |
| `_hook._resolve` | `pipeline/hooks.sh:23` |
| `_hook._resolve_config` | `pipeline/hooks.sh:45` |
| `_hook._run` | `pipeline/hooks.sh:64` |
| `hook.pre_stage` | `pipeline/hooks.sh:92` |
| `hook.post_stage` | `pipeline/hooks.sh:111` |
| `hook.on_success` | `pipeline/hooks.sh:130` |
| `hook.on_failure` | `pipeline/hooks.sh:138` |
| `hook.on_cleanup` | `pipeline/hooks.sh:147` |
| `brik.use` | `pipeline/loader.sh:31` |
| `_log._level_to_int` | `pipeline/logging.sh:55` |
| `_log._should_log` | `pipeline/logging.sh:67` |
| `_log._color_enabled` | `pipeline/logging.sh:78` |
| `_log._style_for` | `pipeline/logging.sh:95` |
| `_log._emit` | `pipeline/logging.sh:119` |
| `log.debug` | `pipeline/logging.sh:140` |
| `log.info` | `pipeline/logging.sh:145` |
| `log.success` | `pipeline/logging.sh:150` |
| `log.warn` | `pipeline/logging.sh:155` |
| `log.error` | `pipeline/logging.sh:160` |
| `_brik.log_dir._resolve` | `pipeline/logging.sh:175` |
| `pipeline.env.init` | `pipeline/pipeline-env.sh:26` |
| `_pipeline.env.append` | `pipeline/pipeline-env.sh:54` |
| `pipeline.env.load` | `pipeline/pipeline-env.sh:79` |
| `_pipeline._resolve_context` | `pipeline/pipeline.sh:36` |
| `_pipeline._resolve_continue_on_error` | `pipeline/pipeline.sh:50` |
| `_pipeline._compute_business_summary` | `pipeline/pipeline.sh:77` |
| `_pipeline._stamp_context` | `pipeline/pipeline.sh:106` |
| `_pipeline._stamp_dry_run` | `pipeline/pipeline.sh:130` |
| `_pipeline._stamp_pipeline_source` | `pipeline/pipeline.sh:154` |
| `_pipeline._should_skip` | `pipeline/pipeline.sh:183` |
| `pipeline.run` | `pipeline/pipeline.sh:219` |
| `_pipeline._archive_report` | `pipeline/pipeline.sh:383` |
| `report.write_fragment` | `pipeline/report/fragment.sh:53` |
| `report.aggregate_fragments` | `pipeline/report/fragment.sh:180` |
| `_report._ancestors_map` | `pipeline/report/fragment.sh:497` |
| `_report._stamp_lifecycle` | `pipeline/report/fragment.sh:524` |
| `_report._enrich_findings_items` | `pipeline/report/fragment.sh:641` |
| `_report._stage_order` | `pipeline/report/fragment.sh:717` |
| `_report._classify_lifecycle` | `pipeline/report/lifecycle.sh:38` |
| `_report._render_aggregate_md` | `pipeline/report/render_md.sh:29` |
| `report.render` | `pipeline/report/render_md.sh:362` |
| `_report._render_md` | `pipeline/report/render_md.sh:460` |
| `report.render_terminal` | `pipeline/report/render_terminal.sh:48` |
| `report.render_aggregate_terminal` | `pipeline/report/render_terminal.sh:144` |
| `_report._backend_path` | `pipeline/report/store.sh:27` |
| `_report._require_jq` | `pipeline/report/store.sh:34` |
| `report.init` | `pipeline/report/store.sh:46` |
| `report.record` | `pipeline/report/store.sh:96` |
| `report.record_object` | `pipeline/report/store.sh:131` |
| `report.has_status` | `pipeline/report/store.sh:171` |
| `report.read` | `pipeline/report/store.sh:198` |
| `_report._append_json` | `pipeline/report/store.sh:239` |
| `_report._append_json_object` | `pipeline/report/store.sh:291` |
| `_report._render_html_head` | `pipeline/report_html/head.sh:17` |
| `_report._render_html` | `pipeline/report_html/render.sh:35` |
| `_report._render_html_tail` | `pipeline/report_html/tail.sh:15` |
| `runner.base_image` | `pipeline/runner-images.sh:44` |
| `runner.resolve_image` | `pipeline/runner-images.sh:53` |
| `runner.resolve_stack_or_base` | `pipeline/runner-images.sh:88` |
| `_stage._load_runtime` | `pipeline/stage.sh:19` |
| `_helpers.epoch_ms` | `pipeline/stage.sh:55` |
| `_helpers.set_if_unset` | `pipeline/stage.sh:75` |
| `_pipeline.detect_metadata` | `pipeline/stage.sh:103` |
| `_pipeline._normalize_remote_url` | `pipeline/stage.sh:221` |
| `stage.create_log_file` | `pipeline/stage.sh:255` |
| `stage.with_logging` | `pipeline/stage.sh:275` |
| `stage.execute` | `pipeline/stage.sh:291` |
| `stage.cleanup` | `pipeline/stage.sh:324` |
| `_stage._finalize_fragment` | `pipeline/stage.sh:350` |
| `_stage._record_business` | `pipeline/stage.sh:411` |
| `_stage.run._project_env` | `pipeline/stage.sh:483` |
| `stage.run` | `pipeline/stage.sh:512` |
| `stage.dispatch` | `pipeline/stage.sh:613` |
| `summary.build` | `pipeline/summary.sh:22` |
| `summary.write_json` | `pipeline/summary.sh:110` |
| `summary.print_human` | `pipeline/summary.sh:121` |
| `pipeline.require_tool` | `pipeline/tools.sh:16` |
| `pipeline.require_file` | `pipeline/tools.sh:27` |
| `pipeline.require_dir` | `pipeline/tools.sh:38` |

## Total

**109 unique public functions** in notion `execution`.
<!-- END AUTO-GENERATED -->

## Outputs publiés (observés sur campagne v0.6.0)

La notion `execution` (lib/pipeline/) produit plusieurs fichiers de coordination et d'agrégation.

### Fichiers produits dans `.brik-logs/`

| Fichier | Producteur | Notes |
|---|---|---|
| `pipeline.env` | bootstrap | env vars partagées entre stages (passées via GitLab dotenv ou Jenkins stash) |
| `policy.cache.json` | init/stage.run | cache de la politique organisationnelle (brik-policy.yml) résolue pour la run |
| `aggregate-report.json` | notify | agrégation des `<stage>-summary.json` + business overall |
| `aggregate-report.md` | notify (report module) | version markdown lisible |
| `aggregate-report.html` | notify (report_html module) | rapport HTML avec assets CSS/JS séparés |

### Fichiers produits dans `brik-artifacts/`

| Fichier | Producteur | Notes |
|---|---|---|
| `brik-artifacts/aggregate-report.{json,md,html}` | notify | mirror du aggregate dans le répertoire "publiable" |
| `brik-artifacts/aggregate.sarif` | notify (findings export) | SARIF agrégé multi-stages (lint+sast+scan+container-scan) |
