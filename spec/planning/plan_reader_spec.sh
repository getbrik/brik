Describe "planning/plan_reader.sh"
  Include "$BRIK_HOME/lib/planning/plan_writer.sh"
  Include "$BRIK_HOME/lib/planning/plan_reader.sh"

  setup_plan() {
    PLAN_FILE="$(mktemp)"
    plan_writer.write -- --workspace /tmp --mode safe > "$PLAN_FILE"
    export PLAN_FILE
  }
  teardown_plan() {
    rm -f "$PLAN_FILE"
  }
  BeforeAll setup_plan
  AfterAll teardown_plan

  Describe "pipeline.plan.should_run"
    It "returns run for init in snapshot/safe"
      When call pipeline.plan.should_run init "$PLAN_FILE"
      The status should be success
    End

    It "returns skip for package (opt-in, not requested)"
      When call pipeline.plan.should_run package "$PLAN_FILE"
      The status should equal 1
    End

    It "defaults to run when no plan file exists"
      When call pipeline.plan.should_run init /nonexistent/plan.json
      The status should be success
    End
  End

  Describe "pipeline.plan.reason"
    It "returns the reason for a skipped stage"
      When call pipeline.plan.reason package "$PLAN_FILE"
      The output should equal "opt-in-flag-missing"
    End

    It "returns context-match for a running stage"
      When call pipeline.plan.reason build "$PLAN_FILE"
      The output should equal "context-match"
    End

    It "returns empty when no plan file exists"
      When call pipeline.plan.reason init /nonexistent/plan.json
      The output should equal ""
    End
  End

  Describe "pipeline.plan.runner_class"
    It "returns the runner_class for build"
      When call pipeline.plan.runner_class build "$PLAN_FILE"
      The output should equal "stack"
    End
  End

  Describe "pipeline.plan.gate"
    It "returns opt_in for package"
      When call pipeline.plan.gate package "$PLAN_FILE"
      The output should equal "opt_in"
    End

    It "returns blocking for build"
      When call pipeline.plan.gate build "$PLAN_FILE"
      The output should equal "blocking"
    End
  End

  Describe "pipeline.plan.stages"
    It "lists the canonical stage order from the plan"
      When call pipeline.plan.stages "$PLAN_FILE"
      The line 1 of output should equal "init"
      The line 11 of output should equal "notify"
    End
  End

  Describe "pipeline.plan.fingerprint"
    It "returns a 64-hex sha256"
      fp=$(pipeline.plan.fingerprint "$PLAN_FILE")
      When call test "${#fp}" -eq 64
      The status should be success
    End
  End
End
