Describe "pipeline.run + plan gate (D.5a)"
  Include "$BRIK_PIPELINE_LIB/pipeline.sh"

  setup_pipeline() {
    PIPELINE_LOG_DIR="$(mktemp -d)"
    export BRIK_LOG_DIR="$PIPELINE_LOG_DIR"
    export BRIK_WORKSPACE="$PIPELINE_LOG_DIR"
    export BRIK_CONFIG_FILE="$PIPELINE_LOG_DIR/brik.yml"
    : > "$BRIK_CONFIG_FILE"
    export BRIK_RUN_ID="run-plan-gate-test"
    stages.init()            { return 0; }
    stages.release()         { return 0; }
    stages.build()           { return 0; }
    stages.lint()            { return 0; }
    stages.sast()            { return 0; }
    stages.scan()            { return 0; }
    stages.test()            { return 0; }
    stages.package()         { return 0; }
    stages.container_scan()  { return 0; }
    stages.deploy()          { return 0; }
    stages.notify()          { return 0; }
  }
  cleanup_pipeline() {
    rm -rf "$PIPELINE_LOG_DIR"
    unset BRIK_RUN_ID BRIK_PLAN_FILE
  }

  # Write a synthetic plan.json that marks every stage as "skip" except
  # the ones listed in $1 (space-separated). The schema validity isn't
  # required by the gate -- jq only reads .stages[].decision/.reason.
  write_plan() {
    local run_stages="$1"
    local plan_file="$BRIK_PLAN_FILE"
    : > "$plan_file"
    {
      printf '{"schemaVersion":"v1","brikVersion":"0.5.0","context":"snapshot","mode":"balanced",'
      printf '"workspace":"/tmp","changes":{"source":"none","files":[]},'
      printf '"stages":['
      local first=1 stage decision
      for stage in init release build lint sast scan test package container-scan deploy notify; do
        case " $run_stages " in
          *" $stage "*) decision="run" ;;
          *)            decision="skip" ;;
        esac
        [[ "$first" -eq 1 ]] || printf ','
        first=0
        printf '{"id":"%s","decision":"%s","reason":"plan-test","gate":{"mode":"blocking"},"runner_class":"base"}' \
          "$stage" "$decision"
      done
      printf '],"dag":{"edges":[]},"fingerprint":"0000000000000000000000000000000000000000000000000000000000000000"}'
    } > "$plan_file"
  }

  Describe "BRIK_PLAN_FILE points to a plan that runs only init"
    Before 'setup_pipeline'
    After 'cleanup_pipeline'

    It "marks every non-init stage as skipped + not-applicable"
      run_with_plan() {
        BRIK_PLAN_FILE="$PIPELINE_LOG_DIR/plan.json"
        export BRIK_PLAN_FILE
        write_plan "init"
        pipeline.run >/dev/null 2>&1
        jq -r '.stages | map(select(.tech.kind == "not-applicable")) | map(.name) | join(",")' \
          "$PIPELINE_LOG_DIR/aggregate-report.json"
      }
      When call run_with_plan
      The output should equal "release,build,lint,sast,scan,test,package,container-scan,deploy,notify"
    End

    It "records the plan reason in business.reason for skipped stages"
      reason_recorded() {
        BRIK_PLAN_FILE="$PIPELINE_LOG_DIR/plan.json"
        export BRIK_PLAN_FILE
        write_plan "init"
        pipeline.run >/dev/null 2>&1
        jq -r '.stages | map(select(.name == "build")) | .[0].business.reason' \
          "$PIPELINE_LOG_DIR/aggregate-report.json"
      }
      When call reason_recorded
      The output should equal "plan-test"
    End

    It "runs the init stage normally (no gate override)"
      init_ran() {
        BRIK_PLAN_FILE="$PIPELINE_LOG_DIR/plan.json"
        export BRIK_PLAN_FILE
        write_plan "init"
        pipeline.run >/dev/null 2>&1
        jq -r '.stages | map(select(.name == "init")) | .[0].tech.status' \
          "$PIPELINE_LOG_DIR/aggregate-report.json"
      }
      When call init_ran
      The output should equal "success"
    End
  End

  Describe "backward-compat: no plan file"
    Before 'setup_pipeline'
    After 'cleanup_pipeline'

    It "behaves like v0.5.0 when BRIK_PLAN_FILE is unset"
      legacy_flow() {
        unset BRIK_PLAN_FILE
        pipeline.run >/dev/null 2>&1
        jq -r '.stages | map(select(.tech.status == "success")) | map(.name) | join(",")' \
          "$PIPELINE_LOG_DIR/aggregate-report.json"
      }
      When call legacy_flow
      The output should equal "init,build,lint,sast,scan,test"
    End
  End
End
