#shellcheck shell=bash
# Validation contract for the v1 deployments notion: per-target deploy output +
# brik.yml deploy targets pinning.
#
# (lib/deployments/).
# The deployments notion ships 6 deploy modules under lib/deployments/
# (argocd, compose, gitops, helm, k8s, ssh), but only 5 are exposed as
# brik.yml deploy.environments[].target: argocd is reached internally via
# target=gitops, not as a standalone user-facing target (same conclusion
# as rollout v1, cf. rollout_contract_spec.sh).
#
# Two contracts apply at the L0 boundary:
#
#   1) deploy.environments[].target ENUM in brik.yml schema
#      schema: schemas/config/v1/brik.schema.json (.properties.deploy)
#      Pins the 5 user-facing targets + the 3-value workflow enum
#      (trunk-based, git-flow, github-flow) that selects a builtin profile.
#
#   2) brik-artifacts/deploy/deploy.json artifact
#      schema: schemas/report/v1.1/fragment.schema.json (REUSED)
#      The deploy stage emits a v1.1 fragment whose business.environments[]
#      sub-block carries the actual deploy outcome per environment.
#
# Companion legacy specs:
#   - spec/_legacy/deployments/*_spec.sh test the BEHAVIOURAL contract
#     of each deploy target (L1).
#
# This spec pins the orthogonal axis: STATIC OUTPUT contract of the
# deploy fragment + brik.yml deploy section (L0).
#
# Mirror pattern: 9 sibling specs in this directory.

Describe "deployments notion contracts (fragment v1.1 reuse + brik.yml deploy enum)"
  FRAGMENT_V11_SCHEMA="${BRIK_HOME}/schemas/report/v1.1/fragment.schema.json"
  BRIK_YML_V1_SCHEMA="${BRIK_HOME}/schemas/config/v1/brik.schema.json"
  SAMPLES_DIR="${BRIK_HOME}/spec/contracts/samples"
  SCHEMA_MAP="https://brik.dev/schemas/=${BRIK_HOME}/schemas/"

  jv_missing() { ! command -v jv >/dev/null 2>&1; }

  validate_fragment_v11() {
    jv --map "$SCHEMA_MAP" "$FRAGMENT_V11_SCHEMA" "$1" >/dev/null 2>&1
  }

  Describe "schema files"
    It "fragment v1.1 schema exists at the expected path"
      When call test -f "$FRAGMENT_V11_SCHEMA"
      The status should be success
    End

    It "brik.yml v1 schema exists at the expected path"
      When call test -f "$BRIK_YML_V1_SCHEMA"
      The status should be success
    End

    It "fragment v1.1 is valid JSON"
      When call jq -e . "$FRAGMENT_V11_SCHEMA"
      The status should be success
      The output should not be blank
    End

    It "brik.yml v1 is valid JSON"
      When call jq -e . "$BRIK_YML_V1_SCHEMA"
      The status should be success
      The output should not be blank
    End
  End

  Describe "brik.yml deploy.* targets and workflow enums"
    It "deploy.environments[].target enum lists the 5 v1 targets (k8s, helm, compose, ssh, gitops)"
      check_target_enum() {
        jq -r '[.. | objects | select(.target?.enum?) | .target.enum] | first | sort | join(",")' "$BRIK_YML_V1_SCHEMA"
      }
      When call check_target_enum
      The output should equal "compose,gitops,helm,k8s,ssh"
      The status should be success
    End

    It "deploy.workflow enum mirrors the 3 builtin rollout profiles (trunk-based, git-flow, github-flow)"
      check_workflow_enum() {
        jq -r '."$defs".deploy.properties.workflow.enum | sort | join(",")' "$BRIK_YML_V1_SCHEMA"
      }
      When call check_workflow_enum
      The output should equal "git-flow,github-flow,trunk-based"
      The status should be success
    End
  End

  Describe "per-target output fragment v1.1 (valid samples, real campaign data)"
    It "accepts deployments-gitops-fragment.json (gitops target, error business.status, real sample)"
      Skip if "jv not installed" jv_missing
      When call validate_fragment_v11 "${SAMPLES_DIR}/valid/deployments-gitops-fragment.json"
      The status should be success
    End

    It "accepts deployments-k8s-fragment.json (k8s target, success status, real sample)"
      Skip if "jv not installed" jv_missing
      When call validate_fragment_v11 "${SAMPLES_DIR}/valid/deployments-k8s-fragment.json"
      The status should be success
    End
  End

  Describe "per-target output fragment v1.1 (invalid synthetic, contract violations)"
    It "rejects deployments-01-rc-negative.json (rc minimum: 0)"
      Skip if "jv not installed" jv_missing
      When call validate_fragment_v11 "${SAMPLES_DIR}/invalid/deployments-01-rc-negative.json"
      The status should not equal 0
    End

    It "rejects deployments-02-status-out-of-enum.json (status='rolling-back' outside enum)"
      Skip if "jv not installed" jv_missing
      When call validate_fragment_v11 "${SAMPLES_DIR}/invalid/deployments-02-status-out-of-enum.json"
      The status should not equal 0
    End

    It "rejects deployments-03-missing-timestamp.json (timestamp required)"
      Skip if "jv not installed" jv_missing
      When call validate_fragment_v11 "${SAMPLES_DIR}/invalid/deployments-03-missing-timestamp.json"
      The status should not equal 0
    End

    It "rejects deployments-04-business-status-out-of-enum.json (business.status='partial-success' outside enum)"
      Skip if "jv not installed" jv_missing
      When call validate_fragment_v11 "${SAMPLES_DIR}/invalid/deployments-04-business-status-out-of-enum.json"
      The status should not equal 0
    End

    It "rejects deployments-05-runner-platform-out-of-enum.json (runner.platform='argo' outside enum)"
      Skip if "jv not installed" jv_missing
      When call validate_fragment_v11 "${SAMPLES_DIR}/invalid/deployments-05-runner-platform-out-of-enum.json"
      The status should not equal 0
    End

    It "rejects deployments-06-tech-warning-banned.json (tech.warning explicitly banned in v1.1)"
      Skip if "jv not installed" jv_missing
      When call validate_fragment_v11 "${SAMPLES_DIR}/invalid/deployments-06-tech-warning-banned.json"
      The status should not equal 0
    End
  End

  Describe "campaign-wide validation (regression guard)"
    # Validate fragment v1.1 against ALL deploy.json artifacts captured
    # during the test campaign (5 samples).

    campaign_dir() {
      local d="${BRIK_HOME}/../docs/chantiers/e2e-cross-platform-v0.6.0/logs"
      [[ -d "$d" ]] && cd "$d" 2>/dev/null && pwd
    }

    campaign_missing() {
      local d
      d="$(campaign_dir)"
      [[ -z "$d" ]]
    }

    validate_all_campaign_deploy_fragments() {
      local d
      d="$(campaign_dir)"
      [[ -z "$d" ]] && return 1
      local fail=0
      while IFS= read -r -d '' f; do
        if ! jv --map "$SCHEMA_MAP" "$FRAGMENT_V11_SCHEMA" "$f" >/dev/null 2>&1; then
          fail=$((fail + 1))
          printf 'FAIL deploy fragment: %s\n' "$f" >&2
        fi
      done < <(find "$d" -name "deploy.json" -path "*/brik-artifacts/deploy/*" -print0 2>/dev/null)
      return "$fail"
    }

    It "all 5 campaign deploy.json fragments validate against v1.1"
      Skip if "jv not installed" jv_missing
      Skip if "campaign workspace not available" campaign_missing
      When call validate_all_campaign_deploy_fragments
      The status should be success
    End
  End
End
