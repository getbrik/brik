#shellcheck shell=bash
# Validation contract for the v1 rollout notion: deploy profile schema.
#
# (lib/rollout/).
# The rollout notion owns the deploy profiles bundled under
# lib/rollout/data/deploy-profiles/ (3 builtins as of the current release: trunk-based,
# github-flow, git-flow). Profile manifests are YAML; samples stay in
# their native YAML form and are converted on the fly via `yq -o=json`
# before validation with `jv`.
#
# A profile is consumed by rollout.profile.resolve and rollout.profile.merge
# (lib/rollout/profile.sh) to build the effective deploy.environments map
# for a brik.yml-driven pipeline.
#
# This spec pins the v1 contract: deploy.environments map of {when, target,
# namespace}, target enum aligned with brik.yml schema (5 values), strict
# additionalProperties everywhere.
#
# Mirror pattern: stages_contract_spec.sh + registry_contract_spec.sh
# (sibling files in this directory).

Describe "schemas/rollout/v1/deploy-profile.schema.json"
  PROFILE_V1_SCHEMA="${BRIK_HOME}/schemas/rollout/v1/deploy-profile.schema.json"
  SAMPLES_DIR="${BRIK_HOME}/spec/contracts/samples"

  jv_missing() { ! command -v jv >/dev/null 2>&1; }
  yq_missing() { ! command -v yq >/dev/null 2>&1; }
  tools_missing() { jv_missing || yq_missing; }

  validate_yaml_sample() {
    local yaml_file="$1"
    yq -o=json . "$yaml_file" 2>/dev/null | jv "$PROFILE_V1_SCHEMA" /dev/stdin >/dev/null 2>&1
  }

  Describe "schema file"
    It "deploy-profile.schema.json exists at the expected path"
      When call test -f "$PROFILE_V1_SCHEMA"
      The status should be success
    End

    It "is valid JSON"
      When call jq -e . "$PROFILE_V1_SCHEMA"
      The status should be success
      The output should not be blank
    End

    It "declares draft 2020-12"
      check_draft() { jq -r '."$schema"' "$PROFILE_V1_SCHEMA"; }
      When call check_draft
      The output should equal "https://json-schema.org/draft/2020-12/schema"
      The status should be success
    End

    It "has additionalProperties: false at top-level"
      check_strict() { jq -r '.additionalProperties' "$PROFILE_V1_SCHEMA"; }
      When call check_strict
      The output should equal "false"
      The status should be success
    End
  End

  Describe "v1 contract pinning"
    It "requires the top-level 'deploy' block"
      check_required() {
        jq -r '.required | sort | join(",")' "$PROFILE_V1_SCHEMA"
      }
      When call check_required
      The output should equal "deploy"
      The status should be success
    End

    It "deploy.environments has additionalProperties typed as object (free-form env names, typed env spec)"
      check_env_addprops() {
        jq -r '.properties.deploy.properties.environments.additionalProperties.type' "$PROFILE_V1_SCHEMA"
      }
      When call check_env_addprops
      The output should equal "object"
      The status should be success
    End

    It "each environment requires exactly {when, target, namespace}"
      check_env_required() {
        jq -r '.properties.deploy.properties.environments.additionalProperties.required | sort | join(",")' "$PROFILE_V1_SCHEMA"
      }
      When call check_env_required
      The output should equal "namespace,target,when"
      The status should be success
    End

    It "target enum lists the 5 v1 deploy targets (k8s, helm, compose, ssh, gitops -- mirror brik.yml schema)"
      check_target_enum() {
        jq -r '.properties.deploy.properties.environments.additionalProperties.properties.target.enum | sort | join(",")' "$PROFILE_V1_SCHEMA"
      }
      When call check_target_enum
      The output should equal "compose,gitops,helm,k8s,ssh"
      The status should be success
    End
  End

  Describe "valid samples (extracted from lib/rollout/data/deploy-profiles/ builtins)"
    It "accepts rollout-trunk-based.yml (staging on main, production on tag)"
      Skip if "jv or yq not installed" tools_missing
      When call validate_yaml_sample "${SAMPLES_DIR}/valid/rollout-trunk-based.yml"
      The status should be success
    End

    It "accepts rollout-github-flow.yml (preview on feature/*, production on main)"
      Skip if "jv or yq not installed" tools_missing
      When call validate_yaml_sample "${SAMPLES_DIR}/valid/rollout-github-flow.yml"
      The status should be success
    End

    It "accepts rollout-git-flow.yml (dev/staging/production with release branch)"
      Skip if "jv or yq not installed" tools_missing
      When call validate_yaml_sample "${SAMPLES_DIR}/valid/rollout-git-flow.yml"
      The status should be success
    End
  End

  Describe "invalid samples (synthetic, contract violations)"
    It "rejects rollout-01-no-deploy-block.yml (top-level deploy required)"
      Skip if "jv or yq not installed" tools_missing
      When call validate_yaml_sample "${SAMPLES_DIR}/invalid/rollout-01-no-deploy-block.yml"
      The status should not equal 0
    End

    It "rejects rollout-02-no-environments.yml (deploy.environments required)"
      Skip if "jv or yq not installed" tools_missing
      When call validate_yaml_sample "${SAMPLES_DIR}/invalid/rollout-02-no-environments.yml"
      The status should not equal 0
    End

    It "rejects rollout-03-target-out-of-enum.yml (target='kubernetes' instead of canonical 'k8s')"
      Skip if "jv or yq not installed" tools_missing
      When call validate_yaml_sample "${SAMPLES_DIR}/invalid/rollout-03-target-out-of-enum.yml"
      The status should not equal 0
    End

    It "rejects rollout-04-environment-missing-when.yml (when required per env)"
      Skip if "jv or yq not installed" tools_missing
      When call validate_yaml_sample "${SAMPLES_DIR}/invalid/rollout-04-environment-missing-when.yml"
      The status should not equal 0
    End

    It "rejects rollout-05-environment-extra-property.yml (additionalProperties: false per env -- no 'replicas' field in v1)"
      Skip if "jv or yq not installed" tools_missing
      When call validate_yaml_sample "${SAMPLES_DIR}/invalid/rollout-05-environment-extra-property.yml"
      The status should not equal 0
    End

    It "rejects rollout-06-namespace-empty.yml (namespace requires minLength: 1)"
      Skip if "jv or yq not installed" tools_missing
      When call validate_yaml_sample "${SAMPLES_DIR}/invalid/rollout-06-namespace-empty.yml"
      The status should not equal 0
    End
  End

  Describe "builtin profiles regression guard"
    # Validate all builtin profiles shipped under lib/rollout/data/deploy-profiles/.
    # Any new profile (or change to existing) must keep validating.

    validate_all_builtin_profiles() {
      local fail=0
      while IFS= read -r -d '' f; do
        if ! yq -o=json . "$f" 2>/dev/null | jv "$PROFILE_V1_SCHEMA" /dev/stdin >/dev/null 2>&1; then
          fail=$((fail + 1))
          printf 'FAIL profile: %s\n' "$f" >&2
        fi
      done < <(find "${BRIK_HOME}/lib/rollout/data/deploy-profiles" -name "*.yml" -print0 2>/dev/null)
      return "$fail"
    }

    It "all 3 builtin profiles validate against v1"
      Skip if "jv or yq not installed" tools_missing
      When call validate_all_builtin_profiles
      The status should be success
    End
  End
End
