Describe "stage.run wires report.write_fragment"
  Include "$BRIK_PIPELINE_LIB/stage.sh"

  FRAGMENT_SCHEMA="${BRIK_HOME}/schemas/report/v1/fragment.schema.json"
  jv_missing() { ! command -v jv >/dev/null 2>&1; }

  validate_fragment_file() {
    jv "$FRAGMENT_SCHEMA" "$1" >/dev/null 2>&1
  }

  setup_dirs() {
    SR_LOG_DIR="$(mktemp -d)"
    SR_WORKSPACE="$(mktemp -d)"
    export BRIK_LOG_DIR="$SR_LOG_DIR"
    export BRIK_WORKSPACE="$SR_WORKSPACE"
    export BRIK_RUN_ID="run-fixture-stage"
    export BRIK_PROJECT_DIR="/nonexistent"
    unset BRIK_DISABLE_REPORT_FRAGMENTS BRIK_PLATFORM
    report.init >/dev/null 2>&1
  }
  cleanup_dirs() {
    rm -rf "$SR_LOG_DIR" "$SR_WORKSPACE"
    unset BRIK_LOG_DIR BRIK_WORKSPACE BRIK_RUN_ID BRIK_PROJECT_DIR
    unset BRIK_DISABLE_REPORT_FRAGMENTS BRIK_PLATFORM
  }

  success_logic() { return 0; }
  failure_logic() { return 5; }

  # ---------------------------------------------------------------------------
  # Successful stage emits a fragment
  # ---------------------------------------------------------------------------
  Describe "successful stage"
    Before 'setup_dirs'
    After 'cleanup_dirs'

    It "writes brik-artifacts/<stage>.json under BRIK_WORKSPACE"
      do_run() {
        stage.run "build" "success_logic" >/dev/null 2>&1
        test -f "$SR_WORKSPACE/brik-artifacts/build/build.json"
      }
      When call do_run
      The status should be success
    End

    It "fragment.status is success when stage returned 0"
      read_status() {
        stage.run "build" "success_logic" >/dev/null 2>&1
        jq -r '.status' "$SR_WORKSPACE/brik-artifacts/build/build.json"
      }
      When call read_status
      The output should equal "success"
    End

    It "fragment.rc is 0"
      read_rc() {
        stage.run "build" "success_logic" >/dev/null 2>&1
        jq '.rc' "$SR_WORKSPACE/brik-artifacts/build/build.json"
      }
      When call read_rc
      The output should equal "0"
    End

    It "fragment validates against the schema"
      Skip if "jv not installed" jv_missing
      do_validate() {
        stage.run "build" "success_logic" >/dev/null 2>&1
        validate_fragment_file "$SR_WORKSPACE/brik-artifacts/build/build.json"
      }
      When call do_validate
      The status should be success
    End

    It "preserves the stage exit code (does not let fragment emission override)"
      run_and_check() {
        stage.run "build" "success_logic" >/dev/null 2>&1
        return $?
      }
      When call run_and_check
      The status should be success
    End
  End

  # ---------------------------------------------------------------------------
  # Failed stage still emits a fragment with status=failed
  # ---------------------------------------------------------------------------
  Describe "failed stage"
    Before 'setup_dirs'
    After 'cleanup_dirs'

    It "writes a fragment even when the stage returns non-zero"
      do_run() {
        stage.run "build" "failure_logic" >/dev/null 2>&1 || true
        test -f "$SR_WORKSPACE/brik-artifacts/build/build.json"
      }
      When call do_run
      The status should be success
    End

    It "fragment.status is failed"
      read_status() {
        stage.run "build" "failure_logic" >/dev/null 2>&1 || true
        jq -r '.status' "$SR_WORKSPACE/brik-artifacts/build/build.json"
      }
      When call read_status
      The output should equal "failed"
    End

    It "fragment.rc captures the stage's non-zero rc"
      read_rc() {
        stage.run "build" "failure_logic" >/dev/null 2>&1 || true
        jq '.rc' "$SR_WORKSPACE/brik-artifacts/build/build.json"
      }
      When call read_rc
      The output should equal "5"
    End

    It "the original stage exit code is propagated to stage.run's caller"
      do_run() { stage.run "build" "failure_logic" >/dev/null 2>&1; return $?; }
      When call do_run
      The status should equal 5
    End
  End

  # ---------------------------------------------------------------------------
  # Escape hatch: BRIK_DISABLE_REPORT_FRAGMENTS=1 disables fragment emission
  # ---------------------------------------------------------------------------
  Describe "BRIK_DISABLE_REPORT_FRAGMENTS=1 escape hatch"
    Before 'setup_dirs'
    After 'cleanup_dirs'

    It "does not write a fragment when disabled"
      do_run() {
        export BRIK_DISABLE_REPORT_FRAGMENTS=1
        stage.run "build" "success_logic" >/dev/null 2>&1
        ! test -f "$SR_WORKSPACE/brik-artifacts/build/build.json"
      }
      When call do_run
      The status should be success
    End

    It "still propagates the stage exit code"
      do_run() {
        export BRIK_DISABLE_REPORT_FRAGMENTS=1
        stage.run "build" "success_logic" >/dev/null 2>&1
        return $?
      }
      When call do_run
      The status should be success
    End
  End

  # ---------------------------------------------------------------------------
  # Sub-second duration_ms precision
  #
  # Proves _stage._finalize_fragment uses a millisecond clock source. With
  # the previous second-precision implementation (date +%s), durations were
  # always multiples of 1000; with millisecond precision the recorded value
  # exposes a non-thousand component. The assertion stays tolerant of slow
  # CI by checking `duration_ms > 0 AND duration_ms % 1000 != 0` rather than
  # an arbitrary wall-clock upper bound.
  # ---------------------------------------------------------------------------
  Describe "sub-second duration_ms"
    Before 'setup_dirs'
    After 'cleanup_dirs'

    sleep_logic() { sleep 0.4; return 0; }

    It "records duration_ms as a non-multiple of 1000 for a sub-second stage"
      measure() {
        stage.run "build" "sleep_logic" >/dev/null 2>&1
        local d
        d="$(jq '.duration_ms' "$SR_WORKSPACE/brik-artifacts/build/build.json")"
        [[ "$d" -gt 0 && $((d % 1000)) -ne 0 ]]
      }
      When call measure
      The status should be success
    End
  End

  # ---------------------------------------------------------------------------
  # Pre-stage hook abort path also emits a fragment
  # ---------------------------------------------------------------------------
  Describe "pre-stage hook abort path"
    setup_with_hook() {
      SR_LOG_DIR="$(mktemp -d)"
      SR_WORKSPACE="$(mktemp -d)"
      HOOK_DIR="$(mktemp -d)"
      mkdir -p "${HOOK_DIR}/.brik/hooks"
      cat > "${HOOK_DIR}/.brik/hooks/pre_stage.sh" << 'HOOKEOF'
pre_stage() { return 7; }
HOOKEOF
      export BRIK_LOG_DIR="$SR_LOG_DIR"
      export BRIK_WORKSPACE="$SR_WORKSPACE"
      export BRIK_RUN_ID="run-fixture-prehook"
      export BRIK_PROJECT_DIR="$HOOK_DIR"
      unset BRIK_DISABLE_REPORT_FRAGMENTS BRIK_PLATFORM
      report.init >/dev/null 2>&1
    }
    cleanup_with_hook() {
      rm -rf "$SR_LOG_DIR" "$SR_WORKSPACE" "$HOOK_DIR"
      unset BRIK_LOG_DIR BRIK_WORKSPACE BRIK_RUN_ID BRIK_PROJECT_DIR
    }
    Before 'setup_with_hook'
    After 'cleanup_with_hook'

    It "writes a fragment when the pre_stage hook aborts"
      do_run() {
        stage.run "build" "success_logic" >/dev/null 2>&1 || true
        test -f "$SR_WORKSPACE/brik-artifacts/build/build.json"
      }
      When call do_run
      The status should be success
    End
  End
End
