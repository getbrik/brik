Describe "summary.sh"
  Include "$BRIK_RUNTIME_LIB/summary.sh"
  Include "$BRIK_HOME/runtime/bash/spec/support/mock_helper.sh"

  Describe "summary.build"
    setup() {
      CTX_FILE="$(mktemp)"
      printf 'BRIK_STAGE_NAME=build\nBRIK_STARTED_AT=%s\n' "$(date +"%Y-%m-%dT%H:%M:%S%z")" > "$CTX_FILE"
      LOG_FILE="$(mktemp "${BRIK_LOG_DIR}/build-XXXXXX.log")"
    }
    cleanup() { rm -rf "$CTX_FILE"; }
    Before 'setup'
    After 'cleanup'

    It "creates a summary JSON file on success"
      verify_summary() {
        summary.build "build" "$CTX_FILE" "$LOG_FILE" 0
        local summary_path="${BRIK_LOG_DIR}/build-summary.json"
        [[ -f "$summary_path" ]] || return 1
        jq -e '.status == "SUCCESS"' "$summary_path" >/dev/null
      }
      When call verify_summary
      The status should be success
    End

    It "marks status as FAILED when exit_code is non-zero"
      verify_failed() {
        summary.build "build" "$CTX_FILE" "$LOG_FILE" 5
        local summary_path="${BRIK_LOG_DIR}/build-summary.json"
        jq -e '.status == "FAILED"' "$summary_path" >/dev/null
      }
      When call verify_failed
      The status should be success
    End

    It "includes the exit_code in the summary"
      verify_exit_code() {
        summary.build "test" "$CTX_FILE" "$LOG_FILE" 10
        local summary_path="${BRIK_LOG_DIR}/test-summary.json"
        jq -e '.exit_code == 10' "$summary_path" >/dev/null
      }
      When call verify_exit_code
      The status should be success
    End

    It "includes stage_name in the summary"
      verify_stage() {
        summary.build "deploy" "$CTX_FILE" "$LOG_FILE" 0
        local summary_path="${BRIK_LOG_DIR}/deploy-summary.json"
        jq -e '.stage_name == "deploy"' "$summary_path" >/dev/null
      }
      When call verify_stage
      The status should be success
    End

    It "returns 0 even on failure scenarios"
      When call summary.build "build" "$CTX_FILE" "$LOG_FILE" 5
      The status should be success
    End

    It "includes duration_ms field"
      verify_duration() {
        summary.build "build" "$CTX_FILE" "$LOG_FILE" 0
        local summary_path="${BRIK_LOG_DIR}/build-summary.json"
        jq -e 'has("duration_ms")' "$summary_path" >/dev/null
      }
      When call verify_duration
      The status should be success
    End

    It "includes finished_at field"
      verify_finished() {
        summary.build "build" "$CTX_FILE" "$LOG_FILE" 0
        local summary_path="${BRIK_LOG_DIR}/build-summary.json"
        jq -e '.finished_at | length > 0' "$summary_path" >/dev/null
      }
      When call verify_finished
      The status should be success
    End

    It "collects errors from log file"
      verify_errors() {
        printf '[ERROR] [build] something went wrong\n' > "$LOG_FILE"
        summary.build "build" "$CTX_FILE" "$LOG_FILE" 1
        local summary_path="${BRIK_LOG_DIR}/build-summary.json"
        jq -e '.errors | length > 0' "$summary_path" >/dev/null
      }
      When call verify_errors
      The status should be success
    End

    It "handles empty started_at gracefully"
      verify_no_start() {
        local empty_ctx
        empty_ctx="$(mktemp)"
        printf 'BRIK_STAGE_NAME=build\n' > "$empty_ctx"
        summary.build "build" "$empty_ctx" "$LOG_FILE" 0
        local summary_path="${BRIK_LOG_DIR}/build-summary.json"
        [[ -f "$summary_path" ]]
        local result=$?
        rm -f "$empty_ctx"
        return $result
      }
      When call verify_no_start
      The status should be success
    End

    It "writes text fallback when jq is hidden via PATH"
      verify_text_fallback() {
        mock.setup
        mock.preserve_cmds
        ln -sf "$(command -v bash)" "${MOCK_BIN}/bash"
        mock.isolate

        summary.build "nojq" "$CTX_FILE" "$LOG_FILE" 0 2>/dev/null
        mock.cleanup

        local summary_path="${BRIK_LOG_DIR}/nojq-summary.json"
        [[ -f "$summary_path" ]] && grep -q 'stage_name=nojq' "$summary_path"
      }
      When call verify_text_fallback
      The status should be success
    End
  End

  Describe "summary.write_json"
    setup() { SUMMARY_DIR="$(mktemp -d)"; }
    cleanup() { rm -rf "$SUMMARY_DIR"; }
    Before 'setup'
    After 'cleanup'

    It "writes data to a file"
      When call summary.write_json '{"test": true}' "${SUMMARY_DIR}/out.json"
      The status should be success
      The contents of file "${SUMMARY_DIR}/out.json" should include '"test"'
    End

    It "returns 6 when directory does not exist"
      When call summary.write_json '{"test": true}' "/nonexistent/dir/out.json"
      The status should equal 6
      The stderr should include "cannot write summary"
    End
  End

  Describe "summary.print_human"
    setup() {
      SUMMARY_DIR="$(mktemp -d)"
      printf '{"stage_name":"build","status":"SUCCESS","exit_code":0,"duration_ms":1234}\n' > "${SUMMARY_DIR}/summary.json"
    }
    cleanup() { rm -rf "$SUMMARY_DIR"; }
    Before 'setup'
    After 'cleanup'

    It "prints to stderr"
      When call summary.print_human "${SUMMARY_DIR}/summary.json"
      The status should be success
      The stderr should include "Stage:"
      The stderr should include "SUCCESS"
    End

    It "prints duration"
      When call summary.print_human "${SUMMARY_DIR}/summary.json"
      The stderr should include "1234"
    End

    It "prints exit code"
      When call summary.print_human "${SUMMARY_DIR}/summary.json"
      The stderr should include "Exit code:"
    End

    It "returns 0 for missing summary file"
      When call summary.print_human "/nonexistent/summary.json"
      The status should be success
      The stderr should include "summary file not found"
    End

    It "prints stage summary header"
      When call summary.print_human "${SUMMARY_DIR}/summary.json"
      The stderr should include "--- Stage Summary ---"
    End

    It "uses cat fallback when jq is hidden via PATH"
      verify_cat_fallback() {
        mock.setup
        mock.preserve_cmds
        ln -sf "$(command -v bash)" "${MOCK_BIN}/bash"
        mock.isolate

        summary.print_human "${SUMMARY_DIR}/summary.json" 2>/dev/null
        local result=$?
        mock.cleanup
        return $result
      }
      When call verify_cat_fallback
      The status should be success
    End
  End
End
