Describe "stage.sh"
  Include "$BRIK_RUNTIME_LIB/stage.sh"

  setup() {
    export BRIK_LOG_DIR
    BRIK_LOG_DIR="$(mktemp -d)"
    export BRIK_PROJECT_DIR="/nonexistent"
  }
  cleanup() { rm -rf "$BRIK_LOG_DIR"; }
  Before 'setup'
  After 'cleanup'

  Describe "stage.run"
    Describe "successful execution"
      success_logic() {
        log.info "running business logic"
        return 0
      }

      It "returns 0 on success and logs lifecycle"
        When call stage.run "build" "success_logic"
        The status should be success
        The stderr should include "starting stage: build"
        The stdout should include "running business logic"
      End

      It "creates a summary JSON"
        verify_summary() {
          stage.run "build" "success_logic" >/dev/null 2>&1
          [[ -f "${BRIK_LOG_DIR}/build-summary.json" ]]
        }
        When call verify_summary
        The status should be success
      End

      It "writes SUCCESS in summary"
        verify_success() {
          stage.run "build" "success_logic" >/dev/null 2>&1
          jq -e '.status == "SUCCESS"' "${BRIK_LOG_DIR}/build-summary.json" >/dev/null
        }
        When call verify_success
        The status should be success
      End
    End

    Describe "failed execution"
      failure_logic() {
        log.error "build broke"
        return 5
      }

      It "propagates the exit code"
        When call stage.run "build" "failure_logic"
        The status should equal 5
        The stderr should include "stage build failed"
        The stdout should include "build broke"
      End

      It "still generates a summary on failure"
        verify_failed_summary() {
          stage.run "build" "failure_logic" >/dev/null 2>&1 || true
          [[ -f "${BRIK_LOG_DIR}/build-summary.json" ]]
        }
        When call verify_failed_summary
        The status should be success
      End

      It "marks summary as FAILED"
        verify_failed_status() {
          stage.run "build" "failure_logic" >/dev/null 2>&1 || true
          jq -e '.status == "FAILED"' "${BRIK_LOG_DIR}/build-summary.json" >/dev/null
        }
        When call verify_failed_status
        The status should be success
      End

      It "records the correct exit code in summary"
        verify_exit_code() {
          stage.run "build" "failure_logic" >/dev/null 2>&1 || true
          jq -e '.exit_code == 5' "${BRIK_LOG_DIR}/build-summary.json" >/dev/null
        }
        When call verify_exit_code
        The status should be success
      End
    End

    Describe "missing logic function"
      It "returns 2 when logic function is not defined"
        When call stage.run "build" "__nonexistent_function__"
        The status should equal 2
        The stderr should include "starting stage: build"
        The stdout should include "logic function not defined"
      End
    End

    Describe "pre-stage hook failure"
      Describe "with failing pre_stage hook"
        setup_failing_hook() {
          export BRIK_LOG_DIR
          BRIK_LOG_DIR="$(mktemp -d)"
          HOOK_DIR="$(mktemp -d)"
          mkdir -p "${HOOK_DIR}/.brik/hooks"
          cat > "${HOOK_DIR}/.brik/hooks/pre_stage.sh" << 'HOOKEOF'
pre_stage() { return 7; }
HOOKEOF
          export BRIK_PROJECT_DIR="$HOOK_DIR"
        }
        cleanup_failing_hook() { rm -rf "$BRIK_LOG_DIR" "$HOOK_DIR"; }
        Before 'setup_failing_hook'
        After 'cleanup_failing_hook'

        my_logic() { return 0; }

        It "aborts and returns the hook's exit code"
          When call stage.run "build" "my_logic"
          The status should equal 7
          The stderr should include "pre-stage hook failed"
        End

        It "does not execute the logic function"
          verify_not_executed() {
            __tracking_logic__() {
              printf 'EXECUTED' > "${BRIK_LOG_DIR}/tracking"
              return 0
            }
            stage.run "build" "__tracking_logic__" 2>/dev/null || true
            [[ ! -f "${BRIK_LOG_DIR}/tracking" ]]
          }
          When call verify_not_executed
          The status should be success
        End
      End
    End

    Describe "log file creation"
      noop_logic() { return 0; }

      It "creates a log file for the stage"
        verify_log() {
          stage.run "build" "noop_logic" >/dev/null 2>&1
          local count
          count="$(find "$BRIK_LOG_DIR" -name 'build-*.log' | wc -l)"
          [[ "$count" -gt 0 ]]
        }
        When call verify_log
        The status should be success
      End
    End

    Describe "context file"
      ctx_logic() {
        local ctx="$1"
        local stage_name
        stage_name="$(context.get "$ctx" "BRIK_STAGE_NAME")"
        [[ "$stage_name" == "build" ]] || return 1
        return 0
      }

      It "passes a context file with BRIK_STAGE_NAME to the logic function"
        When call stage.run "build" "ctx_logic"
        The status should be success
        The stderr should include "starting stage: build"
      End
    End
  End

  Describe "stage.create_log_file"
    It "creates a log file and prints its path"
      When call stage.create_log_file "test"
      The status should be success
      The output should include "/test-"
    End
  End

  Describe "stage.execute"
    It "returns 2 for undefined function"
      When call stage.execute "build" "__undefined__" "/tmp/ctx"
      The status should equal 2
      The stderr should include "logic function not defined"
    End
  End
End
