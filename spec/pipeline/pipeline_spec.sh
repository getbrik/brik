Describe "pipeline.sh"
  Include "$BRIK_PIPELINE_LIB/pipeline.sh"

  setup_pipeline() {
    PIPELINE_LOG_DIR="$(mktemp -d)"
    export BRIK_LOG_DIR="$PIPELINE_LOG_DIR"
    export BRIK_WORKSPACE="$PIPELINE_LOG_DIR"
    export BRIK_CONFIG_FILE="$PIPELINE_LOG_DIR/brik.yml"
    : > "$BRIK_CONFIG_FILE"
    export BRIK_RUN_ID="run-pipeline-test"
    # Mock every stages.* with deterministic return code.
    # Default: all green (rc=0). Tests that need failure redefine a stage.
    stages.init()            { printf 'ran:init\n'; return 0; }
    stages.release()         { printf 'ran:release\n'; return 0; }
    stages.build()           { printf 'ran:build\n'; return 0; }
    stages.lint()            { printf 'ran:lint\n'; return 0; }
    stages.sast()            { printf 'ran:sast\n'; return 0; }
    stages.scan()            { printf 'ran:scan\n'; return 0; }
    stages.test()            { printf 'ran:test\n'; return 0; }
    stages.package()         { printf 'ran:package\n'; return 0; }
    stages.container_scan()  { printf 'ran:container_scan\n'; return 0; }
    stages.deploy()          { printf 'ran:deploy\n'; return 0; }
    stages.notify()          { printf 'ran:notify\n'; return 0; }
  }
  cleanup_pipeline() {
    rm -rf "$PIPELINE_LOG_DIR"
    unset BRIK_RUN_ID
  }

  Describe "pipeline.run (default flow, no opt-in flags)"
    Before 'setup_pipeline'
    After 'cleanup_pipeline'

    It "runs the default subset: init build lint sast scan test"
      default_flow_ran_stages() {
        pipeline.run >/dev/null 2>&1
        jq -r '.stages | map(select(.tech.status == "success")) | map(.name) | join(",")' \
          "$PIPELINE_LOG_DIR/pipeline-report.json"
      }
      When call default_flow_ran_stages
      The output should equal "init,build,lint,sast,scan,test"
    End

    It "marks release/package/container-scan/deploy/notify as skipped"
      default_flow_skipped_stages() {
        pipeline.run >/dev/null 2>&1
        jq -r '.stages | map(select(.tech.status == "skipped")) | map(.name) | join(",")' \
          "$PIPELINE_LOG_DIR/pipeline-report.json"
      }
      When call default_flow_skipped_stages
      The output should equal "release,package,container-scan,deploy,notify"
    End

    It "returns 0 when all ran stages pass"
      When call pipeline.run
      The status should be success
      The output should be present
      The error should be present
    End

    It "produces both pipeline-report.md and pipeline-report.json"
      When call pipeline.run
      The status should be success
      The file "$PIPELINE_LOG_DIR/pipeline-report.md" should be exist
      The file "$PIPELINE_LOG_DIR/pipeline-report.json" should be exist
      The output should be present
      The error should be present
    End

    It "records an exit_code for each executed stage"
      exit_codes_recorded() {
        pipeline.run >/dev/null 2>&1
        jq -r '.stages | map(select(.tech.status == "success")) | all(.tech.exit_code == "0")' \
          "$PIPELINE_LOG_DIR/pipeline-report.json"
      }
      When call exit_codes_recorded
      The output should equal "true"
    End
  End

  Describe "pipeline.run --with-release --with-package --with-deploy"
    Before 'setup_pipeline'
    After 'cleanup_pipeline'

    It "runs every stage when all opt-in flags are set"
      all_stages_ran() {
        pipeline.run --with-release --with-package --with-deploy >/dev/null 2>&1
        jq -r '.stages | map(.name) | join(",")' \
          "$PIPELINE_LOG_DIR/pipeline-report.json"
      }
      When call all_stages_ran
      The output should equal "init,release,build,lint,sast,scan,test,package,container-scan,deploy,notify"
    End

    It "marks zero stages as skipped with all opt-in flags"
      no_skips_with_all_flags() {
        pipeline.run --with-release --with-package --with-deploy >/dev/null 2>&1
        jq -r '.stages | map(select(.tech.status == "skipped")) | length' \
          "$PIPELINE_LOG_DIR/pipeline-report.json"
      }
      When call no_skips_with_all_flags
      The output should equal "0"
    End
  End

  Describe "pipeline.run --with-package"
    Before 'setup_pipeline'
    After 'cleanup_pipeline'

    It "enables package AND container-scan (coupled)"
      package_and_container_scan_ran() {
        pipeline.run --with-package >/dev/null 2>&1
        jq -r '.stages | map(select(.name == "package" or .name == "container-scan")) | map(.tech.status) | join(",")' \
          "$PIPELINE_LOG_DIR/pipeline-report.json"
      }
      When call package_and_container_scan_ran
      The output should equal "success,success"
    End
  End

  Describe "pipeline.run --with-deploy"
    Before 'setup_pipeline'
    After 'cleanup_pipeline'

    It "enables deploy AND notify (coupled)"
      deploy_and_notify_ran() {
        pipeline.run --with-deploy >/dev/null 2>&1
        jq -r '.stages | map(select(.name == "deploy" or .name == "notify")) | map(.tech.status) | join(",")' \
          "$PIPELINE_LOG_DIR/pipeline-report.json"
      }
      When call deploy_and_notify_ran
      The output should equal "success,success"
    End
  End

  Describe "pipeline.run failure behavior"
    Before 'setup_pipeline'
    After 'cleanup_pipeline'

    It "fails fast by default: stops iteration after first failure"
      fail_fast_stops_remaining() {
        stages.build() { return 1; }
        pipeline.run >/dev/null 2>&1
        jq -r '.stages | map(select(.name == "lint" or .name == "sast" or .name == "scan" or .name == "test")) | map(.tech.status) | unique | join(",")' \
          "$PIPELINE_LOG_DIR/pipeline-report.json"
      }
      When call fail_fast_stops_remaining
      The output should equal "skipped"
    End

    It "returns BRIK_EXIT_FAILURE when a stage fails"
      stages.build() { return 1; }
      When call pipeline.run
      The status should equal 1
      The output should be present
      The error should be present
    End

    It "records the failed stage status"
      failed_stage_status() {
        stages.build() { return 1; }
        pipeline.run >/dev/null 2>&1
        jq -r '.stages | map(select(.name == "build")) | map(.tech.status) | first' \
          "$PIPELINE_LOG_DIR/pipeline-report.json"
      }
      When call failed_stage_status
      The output should equal "failed"
    End

    It "with --continue-on-error runs remaining stages after a failure"
      continue_on_error_runs_rest() {
        stages.build() { return 1; }
        pipeline.run --continue-on-error >/dev/null 2>&1
        jq -r '.stages | map(select(.name == "lint" or .name == "sast" or .name == "scan" or .name == "test")) | map(.tech.status) | unique | join(",")' \
          "$PIPELINE_LOG_DIR/pipeline-report.json"
      }
      When call continue_on_error_runs_rest
      The output should equal "success"
    End

    It "with --continue-on-error still returns BRIK_EXIT_FAILURE if any failed"
      stages.build() { return 1; }
      When call pipeline.run --continue-on-error
      The status should equal 1
      The output should be present
      The error should be present
    End

    It "preserves a stage-recorded skipped status (config-skip)"
      lint_config_skip() {
        # Simulate a stage that records its own skipped status before rc=0
        # (mirrors the "BRIK_LINT_ENABLED=false" pattern used by stages.lint).
        stages.lint() {
          report.record "lint" "tech" "status" "skipped"
          return 0
        }
        pipeline.run >/dev/null 2>&1
        jq -r '.stages[] | select(.name == "lint") | .tech.status' \
          "$PIPELINE_LOG_DIR/pipeline-report.json"
      }
      When call lint_config_skip
      The output should equal "skipped"
    End

    It "still marks pipeline as failed when a later stage fails after a self-skip"
      self_skip_then_fail() {
        stages.lint() {
          report.record "lint" "tech" "status" "skipped"
          return 0
        }
        stages.test() { return 1; }
        pipeline.run --continue-on-error
      }
      When call self_skip_then_fail
      The status should equal 1
      The output should be present
      The error should be present
    End
  End

  Describe "pipeline.run flag validation"
    Before 'setup_pipeline'
    After 'cleanup_pipeline'

    It "rejects an unknown flag"
      When call pipeline.run --bogus-flag
      The status should equal 2
      The stderr should include "unknown flag"
    End
  End

  Describe "pipeline.run report integration"
    Before 'setup_pipeline'
    After 'cleanup_pipeline'

    It "stamps pipeline_id from BRIK_RUN_ID"
      pipeline_id_recorded() {
        pipeline.run >/dev/null 2>&1
        jq -r '.pipeline_id' "$PIPELINE_LOG_DIR/pipeline-report.json"
      }
      When call pipeline_id_recorded
      The output should equal "run-pipeline-test"
    End

    It "stamps started_at and finished_at"
      timestamps_recorded() {
        pipeline.run >/dev/null 2>&1
        jq -r '[.started_at, .finished_at] | map(test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T")) | all' \
          "$PIPELINE_LOG_DIR/pipeline-report.json"
      }
      When call timestamps_recorded
      The output should equal "true"
    End

    It "records duration_ms as a non-negative integer"
      durations_non_negative() {
        pipeline.run >/dev/null 2>&1
        jq -r '.stages | map(select(.tech.status == "success")) | all(.tech.duration_ms | tonumber >= 0)' \
          "$PIPELINE_LOG_DIR/pipeline-report.json"
      }
      When call durations_non_negative
      The output should equal "true"
    End
  End
End
