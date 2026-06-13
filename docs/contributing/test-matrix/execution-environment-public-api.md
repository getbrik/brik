# Public API surface: `execution-environment`

> Source: `shared-libs/{gitlab,jenkins,local,common}/`.

## Public functions (per platform)

| Function| Platform | Source file |
|---|---|---|
| `_brik_wrapper_ensure_exit_codes` | common | `shared-libs/common/scripts/base-wrapper.sh:24` |
| `brik.wrapper.validate_home` | common | `shared-libs/common/scripts/base-wrapper.sh:47` |
| `brik.wrapper.set_standard_env` | common | `shared-libs/common/scripts/base-wrapper.sh:84` |
| `brik.wrapper.bootstrap` | common | `shared-libs/common/scripts/base-wrapper.sh:103` |
| `brik.wrapper.load_config` | common | `shared-libs/common/scripts/base-wrapper.sh:154` |
| `brik.wrapper.run_stage` | common | `shared-libs/common/scripts/base-wrapper.sh:187` |
| `brik.gitlab.setup` | gitlab | `shared-libs/gitlab/scripts/gitlab-wrapper.sh:26` |
| `_brik_gitlab_normalize_dry_run` | gitlab | `shared-libs/gitlab/scripts/gitlab-wrapper.sh:74` |
| `_brik_gitlab._ensure_artefact_markers` | gitlab | `shared-libs/gitlab/scripts/gitlab-wrapper.sh:111` |
| `brik.gitlab.mark_skipped` | gitlab | `shared-libs/gitlab/scripts/gitlab-wrapper.sh:180` |
| `brik.gitlab.run_stage` | gitlab | `shared-libs/gitlab/scripts/gitlab-wrapper.sh:187` |
| `brik.jenkins.setup` | jenkins | `shared-libs/jenkins/scripts/jenkins-wrapper.sh:26` |
| `brik.jenkins.run_stage` | jenkins | `shared-libs/jenkins/scripts/jenkins-wrapper.sh:88` |
| `brik.local.setup` | local | `shared-libs/local/scripts/local-wrapper.sh:33` |
| `_brik_local_setup_git_context` | local | `shared-libs/local/scripts/local-wrapper.sh:58` |
| `brik.local.run_stage` | local | `shared-libs/local/scripts/local-wrapper.sh:97` |
| `brik.local.run_integrate` | local | `shared-libs/local/scripts/local-wrapper.sh:117` |

## Total

**17 unique public functions** in notion `execution-environment`.
