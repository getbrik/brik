# Public API surface: `stages`

> Source: `lib/stages/**/*.sh`.

## Public functions

Format: `<notion>.<submodule>.<verb>` (convention layout.md).

<!-- BEGIN AUTO-GENERATED: public-api -->
| Function| Source file |
|---|---|
| `stages.build` | `stages/build.sh:7` |
| `_stages.build._record_artifact` | `stages/build.sh:94` |
| `stages.container_scan` | `stages/container_scan.sh:23` |
| `_stages.container_scan._sign_evidence` | `stages/container_scan.sh:125` |
| `_stages.container_scan._record_evidence` | `stages/container_scan.sh:185` |
| `stages.deploy` | `stages/deploy.sh:7` |
| `stages.init` | `stages/init.sh:7` |
| `_stages.init._resolve_git_identity` | `stages/init.sh:151` |
| `_stages.init._warn_legacy_enabled_keys` | `stages/init.sh:177` |
| `_stages.init._resolve_runner_image` | `stages/init.sh:197` |
| `_stages.init._collect_prereqs` | `stages/init.sh:221` |
| `_stages.init._collect_tool_versions` | `stages/init.sh:236` |
| `_stages.init._build_commit_object` | `stages/init.sh:269` |
| `_stages.init._build_pipeline_ref_object` | `stages/init.sh:302` |
| `_stages.init._has_block` | `stages/init.sh:319` |
| `_stages.init._record_env_section` | `stages/init.sh:331` |
| `_stages.init._load_org_policy` | `stages/init.sh:446` |
| `_stages.init._record_expiring_soon` | `stages/init.sh:488` |
| `stages.lint` | `stages/lint.sh:10` |
| `_lint._record_business` | `stages/lint.sh:105` |
| `_notify._is_ci_aggregation_mode` | `stages/notify.sh:29` |
| `_notify._build_notify_metadata` | `stages/notify.sh:60` |
| `_notify._inject_notify_metadata` | `stages/notify.sh:122` |
| `_notify._should_send` | `stages/notify.sh:164` |
| `_notify._webhook_endpoint` | `stages/notify.sh:181` |
| `notify.slack` | `stages/notify.sh:213` |
| `notify.email` | `stages/notify.sh:280` |
| `notify.webhook_configured` | `stages/notify.sh:333` |
| `notify.webhook` | `stages/notify.sh:345` |
| `notify.send` | `stages/notify.sh:445` |
| `stages.notify` | `stages/notify.sh:485` |
| `_notify._merge_findings_pipeline` | `stages/notify.sh:685` |
| `_notify._export_gitlab_sast` | `stages/notify.sh:706` |
| `stages.package` | `stages/package.sh:7` |
| `_stages.package._record_pushed_image` | `stages/package.sh:182` |
| `_stages.package._parse_registry` | `stages/package.sh:210` |
| `_promote.docker_login` | `stages/promote.sh:23` |
| `_promote.channels` | `stages/promote.sh:70` |
| `stages.promote` | `stages/promote.sh:129` |
| `stages.release` | `stages/release.sh:7` |
| `_stages.release._prepare` | `stages/release.sh:92` |
| `_stages.release._finalize` | `stages/release.sh:199` |
| `stages.sast` | `stages/sast.sh:8` |
| `stages.scan` | `stages/scan.sh:10` |
| `_scan._record_business` | `stages/scan.sh:65` |
| `stages.test` | `stages/test.sh:9` |
| `_stages.test._record_junit_business` | `stages/test.sh:149` |
| `_stages.test._integrate_coverage_findings` | `stages/test.sh:193` |
| `_verify_cfg.has_ruff` | `stages/verify/_cfg.sh:17` |
| `_verify_cfg.has_black` | `stages/verify/_cfg.sh:27` |
| `_verify_cfg.has_checkstyle` | `stages/verify/_cfg.sh:37` |
| `_verify_cfg.has_dotnet_format` | `stages/verify/_cfg.sh:55` |
| `_verify_cfg.has_prettier` | `stages/verify/_cfg.sh:61` |
| `_verify_cfg.has_biome` | `stages/verify/_cfg.sh:76` |
| `_verify_cfg.has_rustfmt` | `stages/verify/_cfg.sh:82` |
| `_verify_cfg.has_google_java_format` | `stages/verify/_cfg.sh:88` |
| `verify.format.run` | `stages/verify/format.sh:15` |
| `verify.lint.run` | `stages/verify/lint.sh:15` |
| `_verify._scan._run` | `stages/verify/scan/_scan.sh:23` |
| `_verify.scan._flag_tool_error` | `stages/verify/scan/_scan.sh:83` |
| `_verify.scan.container._build_grype_command` | `stages/verify/scan/container.sh:20` |
| `verify.scan.container.run` | `stages/verify/scan/container.sh:29` |
| `verify.scan.deps.run` | `stages/verify/scan/deps.sh:27` |
| `_verify.scan.deps._run_osv` | `stages/verify/scan/deps.sh:101` |
| `_verify.scan.deps._run_table` | `stages/verify/scan/deps.sh:187` |
| `_verify.scan.deps._write_empty_reports` | `stages/verify/scan/deps.sh:233` |
| `_verify.scan.deps._log_findings` | `stages/verify/scan/deps.sh:252` |
| `_verify.scan.deps._emit_sbom` | `stages/verify/scan/deps.sh:275` |
| `verify.scan.iac.run` | `stages/verify/scan/iac.sh:20` |
| `verify.scan.license.run` | `stages/verify/scan/license.sh:19` |
| `_verify.scan.sast._build_command` | `stages/verify/scan/sast.sh:26` |
| `verify.scan.sast.run` | `stages/verify/scan/sast.sh:65` |
| `verify.scan.run` | `stages/verify/scan/scan.sh:14` |
| `_verify.scan.secret._gitleaks_platform` | `stages/verify/scan/secret.sh:26` |
| `verify.scan.secret.run` | `stages/verify/scan/secret.sh:40` |
| `verify.type_check.run` | `stages/verify/type_check.sh:12` |
| `verify.run` | `stages/verify/verify.sh:11` |
| `_verify._run_one_check` | `stages/verify/verify.sh:48` |

## Total

**78 unique public functions** in notion `stages`.
<!-- END AUTO-GENERATED -->

## Outputs publiés (observés sur campagne v0.6.0)

Chaque stage écrit dans `.brik-logs/<stage>-summary.json` (sauf `plan` qui n'a pas de summary, voir notion `planning`).

### Schéma observé `<stage>-summary.json`

| Champ | Type | Notes |
|---|---|---|
| `stage_name` | string | nom canonique brik (init, release, build, lint, sast, scan, test, package, container-scan, promote, deploy, notify) |
| `status` | string | "SUCCESS" / "FAILURE" / etc. |
| `exit_code` | integer | code de sortie du stage |
| `started_at` | string | timestamp ISO 8601 avec offset |
| `finished_at` | string | timestamp ISO 8601 avec offset |
| `duration_ms` | integer | durée en millisecondes |
| `log_file` | string | chemin absolu du log dans le workspace |
| `artifacts` | array | liste d'artefacts produits |
| `warnings` | array | warnings collectés |
| `errors` | array | erreurs collectées |

Stages observés produisant cette structure (12/12 sauf plan) : init, release, build, lint, sast, scan, test, package, container-scan, promote, deploy, notify.

### Outputs additionnels par stage

Chaque stage écrit aussi dans `brik-artifacts/<stage>/<stage>.json` (rapport business) et dans `<stage>-<hash>.log` (log file référencé par `log_file`).
