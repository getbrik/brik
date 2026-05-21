Describe "shared-libs/gitlab templates - classic plan-aware pipeline"
  # Guards the migration from the dynamic child pipeline to a single
  # classic pipeline: a brik-plan job computes plan.json and every
  # gateable stage job consults it via /tmp/brik-plan-gate.sh. No child
  # pipeline, no generated YAML.

  TEMPLATES_DIR="${BRIK_HOME}/shared-libs/gitlab/templates"
  JOBS_DIR="${TEMPLATES_DIR}/jobs"

  yq_missing() { ! command -v yq >/dev/null 2>&1; }

  Describe "pipeline.yml"
    PIPELINE="${TEMPLATES_DIR}/pipeline.yml"

    It "declares 'plan' as the first stage"
      Skip if "yq not installed" yq_missing
      first_stage() { yq -r '.stages[0]' "$PIPELINE"; }
      When call first_stage
      The output should equal "plan"
    End

    It "includes the brik-plan job template first"
      Skip if "yq not installed" yq_missing
      first_include() { yq -r '.include[0].local' "$PIPELINE"; }
      When call first_include
      The output should equal "/templates/jobs/plan.yml"
    End

    It "generates the plan-gate helper in before_script"
      When run grep -qF "/tmp/brik-plan-gate.sh" "$PIPELINE"
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

  Describe "gateable stage jobs source the plan gate first"
    Parameters
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
    End

    It "job brik-$1 gates on the plan as its first script step"
      Skip if "yq not installed" yq_missing
      gate_step() { yq -r ".brik-$1.script[0]" "${JOBS_DIR}/$1.yml"; }
      When call gate_step "$1"
      The output should equal ". /tmp/brik-plan-gate.sh $1"
    End

    It "job brik-$1 depends on brik-plan"
      When run grep -qF "job: brik-plan" "${JOBS_DIR}/$1.yml"
      The status should be success
    End
  End

  Describe "always-on jobs are not plan-gated"
    Parameters
      "init"
      "notify"
    End

    It "job brik-$1 has no plan gate"
      When run grep -qF ". /tmp/brik-plan-gate.sh" "${JOBS_DIR}/$1.yml"
      The status should be failure
    End
  End
End
