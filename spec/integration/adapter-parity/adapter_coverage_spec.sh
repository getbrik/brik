#shellcheck shell=bash
# Anti-drift contract: every stage declared in the registry has its
# materialisation in BOTH adapters (Lot 5 of chantier
# 20260526_pipeline-invariants-centralization.md).
#
# Catches the original Jenkins/promote omission and any future case
# where a developer adds a manifest but forgets to:
#   - create shared-libs/gitlab/templates/jobs/<id>.yml
#   - ensure `brik registry stages` returns the stage (covers Jenkins
#     since brikDriver iterates that output verbatim)
#
# This spec is the operational form of the design rule "no orchestrator
# may know an invariant otherwise than by reading its SoT".

Describe "adapter coverage - every manifest stage is reachable from both adapters"
  MANIFESTS_DIR="${BRIK_HOME}/lib/registry/manifests/stages"
  GITLAB_JOBS_DIR="${BRIK_HOME}/shared-libs/gitlab/templates/jobs"
  BRIK_BIN="${BRIK_HOME}/bin/brik"

  jq_missing() { ! command -v jq >/dev/null 2>&1; }
  yq_missing() { ! command -v yq >/dev/null 2>&1; }

  manifest_ids() {
    local f
    for f in "$MANIFESTS_DIR"/*.yml; do
      yq -r '.metadata.id' "$f"
    done | LC_ALL=C sort
  }

  registry_cli_ids() {
    "$BRIK_BIN" registry stages --format json | jq -r '.[].id' | LC_ALL=C sort
  }

  # plan.yml + sast-reports.yml + scan-reports.yml are intentionally
  # excluded: plan is the planner CLI job (not a Brik stage), and
  # *-reports.yml are GitLab Ultimate overlays (not the standard
  # stage-job schema).
  gitlab_job_ids() {
    local f base
    for f in "$GITLAB_JOBS_DIR"/*.yml; do
      base="$(basename "$f" .yml)"
      case "$base" in
        plan|sast-reports|scan-reports) continue ;;
      esac
      printf '%s\n' "$base"
    done | LC_ALL=C sort
  }

  Describe "Jenkins coverage (via brik registry stages)"
    It "every manifest stage appears in brik registry stages output"
      Skip if "jq not installed" jq_missing
      Skip if "yq not installed" yq_missing
      diff_jenkins() { diff <(manifest_ids) <(registry_cli_ids); }
      When call diff_jenkins
      The status should be success
      The output should equal ""
    End

    It "no orphan id in brik registry stages (not declared in manifests)"
      Skip if "jq not installed" jq_missing
      Skip if "yq not installed" yq_missing
      orphan_cli() {
        comm -23 <(registry_cli_ids) <(manifest_ids)
      }
      When call orphan_cli
      The output should equal ""
    End
  End

  Describe "GitLab coverage (via templates/jobs/*.yml)"
    It "every manifest stage has its templates/jobs/<id>.yml"
      Skip if "yq not installed" yq_missing
      missing_yaml() {
        local id
        while IFS= read -r id; do
          [[ -f "$GITLAB_JOBS_DIR/${id}.yml" ]] || printf '%s\n' "$id"
        done < <(manifest_ids)
      }
      When call missing_yaml
      The output should equal ""
    End

    It "no orphan templates/jobs/<id>.yml (not declared in manifests)"
      Skip if "yq not installed" yq_missing
      orphan_yaml() {
        comm -23 <(gitlab_job_ids) <(manifest_ids)
      }
      When call orphan_yaml
      The output should equal ""
    End
  End

  Describe "Cross-adapter parity"
    It "the Jenkins-visible set equals the GitLab-visible set"
      Skip if "jq not installed" jq_missing
      Skip if "yq not installed" yq_missing
      diff_adapters() { diff <(registry_cli_ids) <(gitlab_job_ids); }
      When call diff_adapters
      The status should be success
      The output should equal ""
    End
  End
End
