# Public API surface: `execution-environment`

> Source: `shared-libs/{gitlab,jenkins,local,common}/`.

## Public functions (per platform)

<!-- BEGIN AUTO-GENERATED: public-api -->
| Function| Platform | Source file |
|---|---|---|
| `_brik_wrapper_ensure_exit_codes` | common | `shared-libs/common/scripts/base-wrapper.sh:24` |
| `brik.wrapper.validate_home` | common | `shared-libs/common/scripts/base-wrapper.sh:47` |
| `brik.wrapper.set_standard_env` | common | `shared-libs/common/scripts/base-wrapper.sh:89` |
| `brik.wrapper.bootstrap` | common | `shared-libs/common/scripts/base-wrapper.sh:108` |
| `brik.wrapper.load_config` | common | `shared-libs/common/scripts/base-wrapper.sh:159` |
| `brik.wrapper.run_stage` | common | `shared-libs/common/scripts/base-wrapper.sh:192` |
| `brik.gitlab.setup` | gitlab | `shared-libs/gitlab/scripts/gitlab-wrapper.sh:26` |
| `_brik_gitlab_normalize_dry_run` | gitlab | `shared-libs/gitlab/scripts/gitlab-wrapper.sh:74` |
| `_brik_gitlab._ensure_artefact_markers` | gitlab | `shared-libs/gitlab/scripts/gitlab-wrapper.sh:111` |
| `brik.gitlab.mark_skipped` | gitlab | `shared-libs/gitlab/scripts/gitlab-wrapper.sh:180` |
| `brik.gitlab.run_stage` | gitlab | `shared-libs/gitlab/scripts/gitlab-wrapper.sh:187` |
| `brik.jenkins.setup` | jenkins | `shared-libs/jenkins/scripts/jenkins-wrapper.sh:26` |
| `brik.jenkins.run_stage` | jenkins | `shared-libs/jenkins/scripts/jenkins-wrapper.sh:100` |
| `_brik.local.docker.engine` | local | `shared-libs/local/scripts/docker-runner.sh:47` |
| `_brik.local.docker.platform_args` | local | `shared-libs/local/scripts/docker-runner.sh:53` |
| `_brik.local.docker.engine_run` | local | `shared-libs/local/scripts/docker-runner.sh:61` |
| `_brik.local.docker.work_mount` | local | `shared-libs/local/scripts/docker-runner.sh:72` |
| `_brik.local.docker.uid_gid` | local | `shared-libs/local/scripts/docker-runner.sh:81` |
| `_brik.local.docker.base_image` | local | `shared-libs/local/scripts/docker-runner.sh:85` |
| `brik.local.docker.check_engine` | local | `shared-libs/local/scripts/docker-runner.sh:92` |
| `brik.local.docker.run_id` | local | `shared-libs/local/scripts/docker-runner.sh:112` |
| `brik.local.docker.volume_name` | local | `shared-libs/local/scripts/docker-runner.sh:116` |
| `brik.local.docker.create_volume` | local | `shared-libs/local/scripts/docker-runner.sh:120` |
| `brik.local.docker.destroy_volume` | local | `shared-libs/local/scripts/docker-runner.sh:130` |
| `brik.local.docker.seed_workspace` | local | `shared-libs/local/scripts/docker-runner.sh:146` |
| `brik.local.docker.seed_plan` | local | `shared-libs/local/scripts/docker-runner.sh:186` |
| `_brik.local.docker.read_volume_env` | local | `shared-libs/local/scripts/docker-runner.sh:218` |
| `brik.local.docker.stage_image` | local | `shared-libs/local/scripts/docker-runner.sh:244` |
| `_brik.local.docker.env_ref_vars` | local | `shared-libs/local/scripts/docker-runner.sh:270` |
| `_brik.local.docker.add_host_args` | local | `shared-libs/local/scripts/docker-runner.sh:289` |
| `_brik.local.docker.container_config_path` | local | `shared-libs/local/scripts/docker-runner.sh:308` |
| `_brik.local.docker.common_run_args` | local | `shared-libs/local/scripts/docker-runner.sh:328` |
| `_brik.local.docker.check_signing_backend` | local | `shared-libs/local/scripts/docker-runner.sh:394` |
| `_brik.local.docker.socket_args` | local | `shared-libs/local/scripts/docker-runner.sh:417` |
| `_brik.local.docker._socket_mount_args` | local | `shared-libs/local/scripts/docker-runner.sh:426` |
| `brik.local.docker.run_plan_container` | local | `shared-libs/local/scripts/docker-runner.sh:448` |
| `brik.local.docker.run_stage_container` | local | `shared-libs/local/scripts/docker-runner.sh:473` |
| `brik.local.docker.extract_logs` | local | `shared-libs/local/scripts/docker-runner.sh:503` |
| `brik.local.docker.run_pipeline` | local | `shared-libs/local/scripts/docker-runner.sh:537` |
| `brik.local.docker.run_single_stage` | local | `shared-libs/local/scripts/docker-runner.sh:666` |
| `_brik.local.docker._run_cli_verb_container` | local | `shared-libs/local/scripts/docker-runner.sh:722` |
| `brik.local.docker.run_deploy_container` | local | `shared-libs/local/scripts/docker-runner.sh:786` |
| `brik.local.docker.run_status_container` | local | `shared-libs/local/scripts/docker-runner.sh:791` |
| `brik.local.setup` | local | `shared-libs/local/scripts/local-wrapper.sh:33` |
| `brik.local.setup_host` | local | `shared-libs/local/scripts/local-wrapper.sh:57` |
| `_brik_local_setup_git_context` | local | `shared-libs/local/scripts/local-wrapper.sh:76` |
| `brik.local.run_stage` | local | `shared-libs/local/scripts/local-wrapper.sh:115` |
| `brik.local.run_deploy` | local | `shared-libs/local/scripts/local-wrapper.sh:124` |
| `brik.local.run_integrate` | local | `shared-libs/local/scripts/local-wrapper.sh:144` |

## Total

**49 unique public functions** in notion `execution-environment`.
<!-- END AUTO-GENERATED -->
