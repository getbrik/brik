Describe "context.sh"
  Include "$BRIK_PIPELINE_LIB/context.sh"

  Describe "context.create"
    It "creates a context file and prints its path"
      When call context.create "build"
      The status should be success
      The output should be present
    End

    It "creates a file that exists on disk"
      check_file_exists() {
        local ctx
        ctx="$(context.create "build")"
        [[ -f "$ctx" ]]
      }
      When call check_file_exists
      The status should be success
    End

    It "populates BRIK_STAGE_NAME"
      get_stage_name() {
        local ctx
        ctx="$(context.create "test")"
        _context._get "$ctx" "BRIK_STAGE_NAME"
      }
      When call get_stage_name
      The output should equal "test"
    End

    It "populates BRIK_RUN_ID"
      has_run_id() {
        local ctx
        ctx="$(context.create "build")"
        _context._exists "$ctx" "BRIK_RUN_ID"
      }
      When call has_run_id
      The status should be success
    End

    It "populates BRIK_STARTED_AT"
      has_started_at() {
        local ctx
        ctx="$(context.create "build")"
        _context._exists "$ctx" "BRIK_STARTED_AT"
      }
      When call has_started_at
      The status should be success
    End
  End

  Describe "_context._get"
    setup() {
      CTX_FILE="$(mktemp)"
      printf 'KEY_A=value_a\nKEY_B=hello world\n' > "$CTX_FILE"
    }
    cleanup() { rm -f "$CTX_FILE"; }
    Before 'setup'
    After 'cleanup'

    It "returns the value for an existing key"
      When call _context._get "$CTX_FILE" "KEY_A"
      The status should be success
      The output should equal "value_a"
    End

    It "returns a value with spaces"
      When call _context._get "$CTX_FILE" "KEY_B"
      The output should equal "hello world"
    End

    It "returns 1 for a missing key"
      When call _context._get "$CTX_FILE" "MISSING"
      The status should equal 1
    End
  End

  Describe "_context._set"
    setup() {
      CTX_FILE="$(mktemp)"
      printf 'EXISTING=old\n' > "$CTX_FILE"
    }
    cleanup() { rm -f "$CTX_FILE"; }
    Before 'setup'
    After 'cleanup'

    It "adds a new key"
      When call _context._set "$CTX_FILE" "NEW_KEY" "new_value"
      The status should be success
      The contents of file "$CTX_FILE" should include "NEW_KEY=new_value"
    End

    It "replaces an existing key"
      When call _context._set "$CTX_FILE" "EXISTING" "updated"
      The status should be success
      The contents of file "$CTX_FILE" should include "EXISTING=updated"
      The contents of file "$CTX_FILE" should not include "EXISTING=old"
    End
  End

  Describe "_context._exists"
    setup() {
      CTX_FILE="$(mktemp)"
      printf 'PRESENT=yes\n' > "$CTX_FILE"
    }
    cleanup() { rm -f "$CTX_FILE"; }
    Before 'setup'
    After 'cleanup'

    It "returns 0 for an existing key"
      When call _context._exists "$CTX_FILE" "PRESENT"
      The status should be success
    End

    It "returns 1 for a missing key"
      When call _context._exists "$CTX_FILE" "ABSENT"
      The status should equal 1
    End
  End

  Describe "_context._set_result"
    setup_result() {
      CTX_FILE="$(mktemp)"
      printf '' > "$CTX_FILE"
    }
    cleanup_result() { rm -f "$CTX_FILE"; }
    Before 'setup_result'
    After 'cleanup_result'

    It "writes 'success' when exit code is 0"
      When call _context._set_result "$CTX_FILE" "RESULT" 0
      The status should be success
      The contents of file "$CTX_FILE" should include "RESULT=success"
    End

    It "writes 'failed' when exit code is non-zero"
      When call _context._set_result "$CTX_FILE" "RESULT" 42
      The status should be success
      The contents of file "$CTX_FILE" should include "RESULT=failed"
    End

    It "writes 'failed' when exit code is 1"
      When call _context._set_result "$CTX_FILE" "RESULT" 1
      The status should be success
      The contents of file "$CTX_FILE" should include "RESULT=failed"
    End
  End

  Describe "context.create IO failures"
    setup_bad_dir() {
      BAD_LOG_DIR="$(mktemp -d)"
      chmod 000 "$BAD_LOG_DIR"
      export BRIK_LOG_DIR="${BAD_LOG_DIR}/nested"
    }
    cleanup_bad_dir() {
      chmod 755 "$BAD_LOG_DIR" 2>/dev/null
      rm -rf "$BAD_LOG_DIR"
      unset BRIK_LOG_DIR
    }
    Before 'setup_bad_dir'
    After 'cleanup_bad_dir'

    It "returns BRIK_EXIT_IO_FAILURE when log dir cannot be created"
      When call context.create "badstage"
      The status should equal "$BRIK_EXIT_IO_FAILURE"
      The stderr should include "cannot create log directory"
    End
  End
End
