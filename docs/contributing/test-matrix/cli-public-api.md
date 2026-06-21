# Public API surface: `cli`

> Source: `lib/cli/**/*.sh`.

## Public functions

Format: `<notion>.<submodule>.<verb>` (convention layout.md).

<!-- BEGIN AUTO-GENERATED: public-api -->
| Function| Source file |
|---|---|
| `_cli.authorize._notify` | `cli/authorize.sh:24` |
| `cli.authorize.run` | `cli/authorize.sh:46` |
| `_cli.deploy._resolve_version_tag` | `cli/deploy.sh:22` |
| `_cli.deploy._notify` | `cli/deploy.sh:42` |
| `_cli.deploy._protection_mode` | `cli/deploy.sh:77` |
| `cli.deploy.run` | `cli/deploy.sh:102` |
| `doctor._tool_version` | `cli/doctor.sh:12` |
| `doctor._check_tools` | `cli/doctor.sh:25` |
| `doctor.run` | `cli/doctor.sh:46` |
| `cli.doctor.run` | `cli/doctor.sh:168` |
| `cli.extension.run` | `cli/extension.sh:26` |
| `cli.extension.test` | `cli/extension.sh:42` |
| `cli.help._stage_list` | `cli/help.sh:13` |
| `cli.help.run` | `cli/help.sh:26` |
| `brik_print` | `cli/helpers.sh:10` |
| `brik_error` | `cli/helpers.sh:14` |
| `brik_hint` | `cli/helpers.sh:18` |
| `brik_usage_error` | `cli/helpers.sh:24` |
| `brik_print_verb_help` | `cli/helpers.sh:34` |
| `brik_require_arg` | `cli/helpers.sh:56` |
| `brik_host_local` | `cli/helpers.sh:71` |
| `_brik_detect_install_method` | `cli/helpers.sh:78` |
| `cli.infra.run` | `cli/infra.sh:14` |
| `_cli.infra._init` | `cli/infra.sh:48` |
| `_cli.infra._validate` | `cli/infra.sh:104` |
| `_cli.infra._secrets` | `cli/infra.sh:147` |
| `_cli.infra._scaffold_p_local` | `cli/infra.sh:221` |
| `_cli.infra._scaffold_p_open` | `cli/infra.sh:232` |
| `_cli.infra._scaffold_p_entreprise` | `cli/infra.sh:319` |
| `_cli.infra._scaffold_p_lab` | `cli/infra.sh:422` |
| `cli.init.run` | `cli/init.sh:12` |
| `_cli.init._generate_config` | `cli/init.sh:99` |
| `_cli.init._generate_bootstrap` | `cli/init.sh:127` |
| `brikIntegrate` | `cli/init.sh:160` |
| `cli.integrate.run` | `cli/integrate.sh:14` |
| `cli.local_runner.default_infra` | `cli/local_runner.sh:18` |
| `cli.local_runner.setup_env` | `cli/local_runner.sh:29` |
| `cli.local_runner.setup_docker_env` | `cli/local_runner.sh:47` |
| `cli.local_runner.runtime` | `cli/local_runner.sh:67` |
| `cli.plan.run` | `cli/plan.sh:20` |
| `cli.plan.gate` | `cli/plan.sh:198` |
| `cli.plan._reason_text` | `cli/plan.sh:279` |
| `cli.plan._render_explain` | `cli/plan.sh:346` |
| `_cli.promote._notify` | `cli/promote.sh:22` |
| `cli.promote.run` | `cli/promote.sh:47` |
| `cli.provider.run` | `cli/provider.sh:29` |
| `cli.provider.test` | `cli/provider.sh:45` |
| `cli.provider._check_schema` | `cli/provider.sh:121` |
| `cli.registry.run` | `cli/registry.sh:15` |
| `cli.registry._usage` | `cli/registry.sh:34` |
| `cli.registry.stages` | `cli/registry.sh:56` |
| `cli.registry._stage_entry` | `cli/registry.sh:102` |
| `cli.self_uninstall.run` | `cli/self_uninstall.sh:12` |
| `cli.self_update.run` | `cli/self_update.sh:12` |
| `_cli.self_update._git` | `cli/self_update.sh:77` |
| `cli.stage.run` | `cli/stage.sh:12` |
| `cli.status.run` | `cli/status.sh:29` |
| `validate.run` | `cli/validate.sh:16` |
| `cli.validate.run` | `cli/validate.sh:54` |
| `cli.version.run` | `cli/version.sh:11` |

## Total

**60 unique public functions** in notion `cli`.
<!-- END AUTO-GENERATED -->
