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
          "$PIPELINE_LOG_DIR/aggregate-report.json"
      }
      When call default_flow_ran_stages
      The output should equal "init,build,lint,sast,scan,test"
    End

    It "marks release/package/container-scan/deploy/notify as skipped"
      default_flow_skipped_stages() {
        pipeline.run >/dev/null 2>&1
        jq -r '.stages | map(select(.tech.status == "skipped")) | map(.name) | join(",")' \
          "$PIPELINE_LOG_DIR/aggregate-report.json"
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

    It "produces both aggregate-report.md and aggregate-report.json"
      When call pipeline.run
      The status should be success
      The file "$PIPELINE_LOG_DIR/aggregate-report.md" should be exist
      The file "$PIPELINE_LOG_DIR/aggregate-report.json" should be exist
      The output should be present
      The error should be present
    End

    It "records an exit_code for each executed stage"
      exit_codes_recorded() {
        pipeline.run >/dev/null 2>&1
        jq -r '.stages | map(select(.tech.status == "success")) | all(.tech.exit_code == "0")' \
          "$PIPELINE_LOG_DIR/aggregate-report.json"
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
          "$PIPELINE_LOG_DIR/aggregate-report.json"
      }
      When call all_stages_ran
      The output should equal "init,release,build,lint,sast,scan,test,package,container-scan,deploy,notify"
    End

    It "marks zero stages as skipped with all opt-in flags"
      no_skips_with_all_flags() {
        pipeline.run --with-release --with-package --with-deploy >/dev/null 2>&1
        jq -r '.stages | map(select(.tech.status == "skipped")) | length' \
          "$PIPELINE_LOG_DIR/aggregate-report.json"
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
          "$PIPELINE_LOG_DIR/aggregate-report.json"
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
          "$PIPELINE_LOG_DIR/aggregate-report.json"
      }
      When call deploy_and_notify_ran
      The output should equal "success,success"
    End
  End

  Describe "pipeline.run failure behavior"
    Before 'setup_pipeline'
    After 'cleanup_pipeline'

    It "continues by default in snapshot context (no tag)"
      snapshot_continues_after_failure() {
        unset BRIK_COMMIT_TAG
        stages.build() { return 1; }
        pipeline.run >/dev/null 2>&1
        jq -r '.stages | map(select(.name == "lint" or .name == "sast" or .name == "scan" or .name == "test")) | map(.tech.status) | unique | join(",")' \
          "$PIPELINE_LOG_DIR/aggregate-report.json"
      }
      When call snapshot_continues_after_failure
      The output should equal "success"
    End

    It "fails fast by default in release context (BRIK_COMMIT_TAG set)"
      release_fail_fast() {
        export BRIK_COMMIT_TAG="v9.9.9"
        stages.build() { return 1; }
        pipeline.run >/dev/null 2>&1
        unset BRIK_COMMIT_TAG
        jq -r '.stages | map(select(.name == "lint" or .name == "sast" or .name == "scan" or .name == "test")) | map(.tech.status) | unique | join(",")' \
          "$PIPELINE_LOG_DIR/aggregate-report.json"
      }
      When call release_fail_fast
      The output should equal "skipped"
    End

    It "BRIK_CONTINUE_ON_ERROR=0 forces fail-fast even on snapshot"
      snapshot_env_override_fail_fast() {
        unset BRIK_COMMIT_TAG
        export BRIK_CONTINUE_ON_ERROR=0
        stages.build() { return 1; }
        pipeline.run >/dev/null 2>&1
        unset BRIK_CONTINUE_ON_ERROR
        jq -r '.stages | map(select(.name == "lint" or .name == "sast" or .name == "scan" or .name == "test")) | map(.tech.status) | unique | join(",")' \
          "$PIPELINE_LOG_DIR/aggregate-report.json"
      }
      When call snapshot_env_override_fail_fast
      The output should equal "skipped"
    End

    It "BRIK_CONTINUE_ON_ERROR=1 forces continue even on release"
      release_env_override_continue() {
        export BRIK_COMMIT_TAG="v9.9.9"
        export BRIK_CONTINUE_ON_ERROR=1
        stages.build() { return 1; }
        pipeline.run >/dev/null 2>&1
        unset BRIK_COMMIT_TAG BRIK_CONTINUE_ON_ERROR
        jq -r '.stages | map(select(.name == "lint" or .name == "sast" or .name == "scan" or .name == "test")) | map(.tech.status) | unique | join(",")' \
          "$PIPELINE_LOG_DIR/aggregate-report.json"
      }
      When call release_env_override_continue
      The output should equal "success"
    End

    It "returns BRIK_EXIT_FAILURE when a stage fails in release context"
      release_failure_rc() {
        export BRIK_COMMIT_TAG="v9.9.9"
        stages.build() { return 1; }
        pipeline.run >/dev/null 2>&1
        local rc=$?
        unset BRIK_COMMIT_TAG
        return "$rc"
      }
      When call release_failure_rc
      The status should equal 1
    End

    It "exits 0 in snapshot context when a stage fails (business=warning)"
      snapshot_failure_rc() {
        unset BRIK_COMMIT_TAG
        stages.build() { return 1; }
        pipeline.run >/dev/null 2>&1
      }
      When call snapshot_failure_rc
      The status should equal 0
    End

    It "records the failed stage status"
      failed_stage_status() {
        stages.build() { return 1; }
        pipeline.run >/dev/null 2>&1
        jq -r '.stages | map(select(.name == "build")) | map(.tech.status) | first' \
          "$PIPELINE_LOG_DIR/aggregate-report.json"
      }
      When call failed_stage_status
      The output should equal "failed"
    End

    It "with --continue-on-error runs remaining stages after a failure"
      continue_on_error_runs_rest() {
        stages.build() { return 1; }
        pipeline.run --continue-on-error >/dev/null 2>&1
        jq -r '.stages | map(select(.name == "lint" or .name == "sast" or .name == "scan" or .name == "test")) | map(.tech.status) | unique | join(",")' \
          "$PIPELINE_LOG_DIR/aggregate-report.json"
      }
      When call continue_on_error_runs_rest
      The output should equal "success"
    End

    It "with --continue-on-error still returns BRIK_EXIT_FAILURE on release failure"
      release_continue_failure_rc() {
        export BRIK_COMMIT_TAG="v9.9.9"
        stages.build() { return 1; }
        pipeline.run --continue-on-error >/dev/null 2>&1
        local rc=$?
        unset BRIK_COMMIT_TAG
        return "$rc"
      }
      When call release_continue_failure_rc
      The status should equal 1
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
          "$PIPELINE_LOG_DIR/aggregate-report.json"
      }
      When call lint_config_skip
      The output should equal "skipped"
    End

    It "marks pipeline as failed when a later stage fails after a self-skip in release context"
      self_skip_then_fail() {
        export BRIK_COMMIT_TAG="v9.9.9"
        stages.lint() {
          report.record "lint" "tech" "status" "skipped"
          return 0
        }
        stages.test() { return 1; }
        pipeline.run --continue-on-error >/dev/null 2>&1
        local rc=$?
        unset BRIK_COMMIT_TAG
        return "$rc"
      }
      When call self_skip_then_fail
      The status should equal 1
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
        jq -r '.pipeline_id' "$PIPELINE_LOG_DIR/aggregate-report.json"
      }
      When call pipeline_id_recorded
      The output should equal "run-pipeline-test"
    End

    It "stamps started_at and finished_at"
      timestamps_recorded() {
        pipeline.run >/dev/null 2>&1
        jq -r '[.started_at, .finished_at] | map(test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T")) | all' \
          "$PIPELINE_LOG_DIR/aggregate-report.json"
      }
      When call timestamps_recorded
      The output should equal "true"
    End

    It "records duration_ms as a non-negative integer"
      durations_non_negative() {
        pipeline.run >/dev/null 2>&1
        jq -r '.stages | map(select(.tech.status == "success")) | all(.tech.duration_ms | tonumber >= 0)' \
          "$PIPELINE_LOG_DIR/aggregate-report.json"
      }
      When call durations_non_negative
      The output should equal "true"
    End
  End

  Describe "pipeline.run is registry-driven"
    # Proves OCP on the stage axis: pipeline.run iterates whatever
    # registry.stage.list returns, with no hardcoded order embedded in
    # pipeline.sh. The setup overrides registry.stage.list to publish a
    # custom 2-stage sequence and asserts the run honors it verbatim.
    Before 'setup_pipeline'
    After 'cleanup_pipeline'

    It "iterates the sequence returned by registry.stage.list"
      registry_drives_order() {
        # Override the registry list to a synthetic 2-stage sequence
        # (test before init -- not the canonical fixed-flow order).
        # Both stages must be blocking (no opt-in flag) so the gate
        # does not interfere with the order check.
        registry.stage.list() {
          printf 'test\n'
          printf 'init\n'
        }
        pipeline.run >/dev/null 2>&1
        jq -r '.stages | map(select(.tech.status == "success")) | map(.name) | join(",")' \
          "$PIPELINE_LOG_DIR/aggregate-report.json"
      }
      When call registry_drives_order
      The output should equal "test,init"
    End

    It "fails fast when registry.stage.list is not loaded"
      no_registry() {
        # Hide the registry helper from this shell. pipeline.run must
        # refuse to run (no hardcoded fallback list).
        unset -f registry.stage.list 2>/dev/null || true
        pipeline.run
      }
      When call no_registry
      The status should not equal 0
      The stderr should include "registry.stage.list is not loaded"
    End

    It "fails fast when registry.stage.list returns nothing"
      empty_registry() {
        registry.stage.list() { :; }
        pipeline.run
      }
      When call empty_registry
      The status should not equal 0
      The stderr should include "returned no stages"
    End
  End
End
