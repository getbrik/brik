Describe "shared-libs/gitlab templates - classic plan-aware pipeline"
  # Guards the migration from the dynamic child pipeline to a single
  # classic pipeline: a brik-plan job computes plan.json and every
  # gateable stage job consults it via /tmp/brik-plan-gate.sh. No child
  # pipeline, no generated YAML.

  TEMPLATES_DIR="${BRIK_HOME}/shared-libs/gitlab/templates"
  JOBS_DIR="${TEMPLATES_DIR}/jobs"

  yq_missing() { ! command -v yq >/dev/null 2>&1; }

  Describe "brik-integrate.yml"
    PIPELINE="${TEMPLATES_DIR}/brik-integrate.yml"

    It "declares 'plan' as the first stage"
      Skip if "yq not installed" yq_missing
      first_stage() { yq -r '.stages[0]' "$PIPELINE"; }
      When call first_stage
      The output should equal "plan"
    End

    It "includes _brik-stage.yml first so per-stage jobs can extend it"
      Skip if "yq not installed" yq_missing
      first_include() { yq -r '.include[0].local' "$PIPELINE"; }
      When call first_include
      # Lot 3 of chantier 20260526: _brik-stage.yml carries the factored
      # script + artifacts contract and must be loaded before any job
      # that references it via extends:.
      The output should equal "/templates/_brik-stage.yml"
    End

    It "includes the brik-plan job template second (after _brik-stage)"
      Skip if "yq not installed" yq_missing
      second_include() { yq -r '.include[1].local' "$PIPELINE"; }
      When call second_include
      The output should equal "/templates/jobs/plan.yml"
    End

    It "generates the plan-gate helper in before_script"
      When run grep -qF "/tmp/brik-plan-gate.sh" "$PIPELINE"
      The status should be success
    End

    It "seeds cache/artefact markers on the plan-gate skip path"
      # A plan-skipped job exits before brik.gitlab.run_stage; the gate
      # helper must seed the markers itself or GitLab logs "no files to
      # cache/upload" for a green skipped job.
      When run grep -qF "brik.gitlab.mark_skipped" "$PIPELINE"
      The status should be success
    End

    It "no longer references the dynamic child pipeline"
      When run grep -qE 'parent_pipeline|dynamic-pipeline|child pipeline' "$PIPELINE"
      The status should be failure
    End
  End

  Describe "brik-plan job"
    PLAN_JOB="${JOBS_DIR}/plan.yml"

    It "runs in the plan stage"
      Skip if "yq not installed" yq_missing
      plan_stage() { yq -r '.brik-plan.stage' "$PLAN_JOB"; }
      When call plan_stage
      The output should equal "plan"
    End

    It "does not gate itself"
      When run grep -qF ". /tmp/brik-plan-gate.sh" "$PLAN_JOB"
      The status should be failure
    End
  End

  # After Lot 3 of chantier 20260526 the gate is factored into the hidden
  # template .brik-stage. Standard jobs inherit it; package overrides
  # script (Docker install) but still calls the gate as its first step;
  # init/notify also inherit the gate but it's a no-op for them (always-on
  # contexts in their manifests).
  Describe "the plan gate is factored in .brik-stage"
    BRIK_STAGE_TEMPLATE="${TEMPLATES_DIR}/_brik-stage.yml"

    It ".brik-stage script[0] sources /tmp/brik-plan-gate.sh"
      Skip if "yq not installed" yq_missing
      gate_step() { yq -r '.[".brik-stage"].script[0]' "$BRIK_STAGE_TEMPLATE"; }
      When call gate_step
      The output should include "brik-plan-gate.sh"
    End
  End

  Describe "stage jobs depend on brik-plan via needs"
    Parameters
      "init"
      "release"
      "build"
      "lint"
      "sast"
      "scan"
      "test"
      "package"
      "container-scan"
      "promote"
      "deploy"
      "notify"
    End

    It "job brik-$1 depends on brik-plan"
      When run grep -qF "job: brik-plan" "${JOBS_DIR}/$1.yml"
      The status should be success
    End
  End

  Describe "package overrides script but still sources the plan gate first"
    It "package.yml first script step calls the gate"
      Skip if "yq not installed" yq_missing
      gate_step() { yq -r '.["brik-package"].script[0]' "${JOBS_DIR}/package.yml"; }
      When call gate_step
      The output should include "brik-plan-gate.sh"
    End
  End
End
