Describe "context.sh"
  Include "$BRIK_RUNTIME_LIB/context.sh"

  Describe "context.create"
    setup() { export BRIK_LOG_DIR; BRIK_LOG_DIR="$(mktemp -d)"; }
    cleanup() { rm -rf "$BRIK_LOG_DIR"; }
    Before 'setup'
    After 'cleanup'

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
        context.get "$ctx" "BRIK_STAGE_NAME"
      }
      When call get_stage_name
      The output should equal "test"
    End

    It "populates BRIK_RUN_ID"
      has_run_id() {
        local ctx
        ctx="$(context.create "build")"
        context.exists "$ctx" "BRIK_RUN_ID"
      }
      When call has_run_id
      The status should be success
    End

    It "populates BRIK_STARTED_AT"
      has_started_at() {
        local ctx
        ctx="$(context.create "build")"
        context.exists "$ctx" "BRIK_STARTED_AT"
      }
      When call has_started_at
      The status should be success
    End
  End

  Describe "context.get"
    setup() {
      CTX_FILE="$(mktemp)"
      printf 'KEY_A=value_a\nKEY_B=hello world\n' > "$CTX_FILE"
    }
    cleanup() { rm -f "$CTX_FILE"; }
    Before 'setup'
    After 'cleanup'

    It "returns the value for an existing key"
      When call context.get "$CTX_FILE" "KEY_A"
      The status should be success
      The output should equal "value_a"
    End

    It "returns a value with spaces"
      When call context.get "$CTX_FILE" "KEY_B"
      The output should equal "hello world"
    End

    It "returns 1 for a missing key"
      When call context.get "$CTX_FILE" "MISSING"
      The status should equal 1
    End
  End

  Describe "context.set"
    setup() {
      CTX_FILE="$(mktemp)"
      printf 'EXISTING=old\n' > "$CTX_FILE"
    }
    cleanup() { rm -f "$CTX_FILE"; }
    Before 'setup'
    After 'cleanup'

    It "adds a new key"
      When call context.set "$CTX_FILE" "NEW_KEY" "new_value"
      The status should be success
      The contents of file "$CTX_FILE" should include "NEW_KEY=new_value"
    End

    It "replaces an existing key"
      When call context.set "$CTX_FILE" "EXISTING" "updated"
      The status should be success
      The contents of file "$CTX_FILE" should include "EXISTING=updated"
      The contents of file "$CTX_FILE" should not include "EXISTING=old"
    End
  End

  Describe "context.exists"
    setup() {
      CTX_FILE="$(mktemp)"
      printf 'PRESENT=yes\n' > "$CTX_FILE"
    }
    cleanup() { rm -f "$CTX_FILE"; }
    Before 'setup'
    After 'cleanup'

    It "returns 0 for an existing key"
      When call context.exists "$CTX_FILE" "PRESENT"
      The status should be success
    End

    It "returns 1 for a missing key"
      When call context.exists "$CTX_FILE" "ABSENT"
      The status should equal 1
    End
  End
End
