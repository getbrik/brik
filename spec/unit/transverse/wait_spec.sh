Describe "wait.sh (transverse poll-until-timeout helper)"
  Include "$BRIK_PIPELINE_LIB/logging.sh"
  Include "$BRIK_TRANSVERSE_LIB/wait.sh"

  Describe "transverse.wait.until"
    # Fixture: counter-driven check function. Succeeds once the global
    # _WAIT_CALLS counter reaches _WAIT_SUCCEED_AT.
    setup_counter() {
      _WAIT_CALLS=0
      _WAIT_SUCCEED_AT=1
    }
    _wait_spec_counter_check() {
      _WAIT_CALLS=$(( _WAIT_CALLS + 1 ))
      [[ "$_WAIT_CALLS" -ge "$_WAIT_SUCCEED_AT" ]]
    }
    _wait_spec_never_check() {
      return 1
    }

    Describe "happy path"
      Before 'setup_counter'

      It "returns 0 when check succeeds on first attempt"
        When call transverse.wait.until _wait_spec_counter_check --timeout 2 --interval 1
        The status should be success
        The variable _WAIT_CALLS should equal "1"
        The stderr should include "transverse.wait.until"
      End

      It "returns 0 when check succeeds after retries"
        succeed_on_third() {
          _WAIT_SUCCEED_AT=3
          transverse.wait.until _wait_spec_counter_check --timeout 5 --interval 1
        }
        When call succeed_on_third
        The status should be success
        The variable _WAIT_CALLS should equal "3"
        The stderr should include "pending"
      End

      It "returns BRIK_EXIT_TIMEOUT when check never succeeds"
        When call transverse.wait.until _wait_spec_never_check --timeout 2 --interval 1
        The status should equal "$BRIK_EXIT_TIMEOUT"
        The stderr should include "timeout"
      End
    End

    Describe "dry-run"
      It "returns 0 without invoking check"
        setup_counter
        When call transverse.wait.until _wait_spec_counter_check --timeout 1 --interval 1 --dry-run
        The status should be success
        The variable _WAIT_CALLS should equal "0"
        The stderr should include "[dry-run]"
      End

      It "honours BRIK_DRY_RUN=true"
        setup_counter
        BRIK_DRY_RUN=true
        When call transverse.wait.until _wait_spec_counter_check --timeout 1 --interval 1
        The status should be success
        The variable _WAIT_CALLS should equal "0"
        The stderr should include "[dry-run]"
      End
    End

    Describe "validation errors"
      It "fails when no check_fn is provided"
        When call transverse.wait.until --timeout 10
        The status should equal "$BRIK_EXIT_INVALID_INPUT"
        The stderr should include "check function"
      End

      It "fails when check_fn is not a declared function"
        When call transverse.wait.until not_a_real_function --timeout 10
        The status should equal "$BRIK_EXIT_INVALID_INPUT"
        The stderr should include "not_a_real_function"
      End

      It "fails when timeout is not numeric"
        When call transverse.wait.until _wait_spec_counter_check --timeout abc --interval 1
        The status should equal "$BRIK_EXIT_INVALID_INPUT"
        The stderr should include "timeout"
      End

      It "fails when interval is zero"
        When call transverse.wait.until _wait_spec_counter_check --timeout 10 --interval 0
        The status should equal "$BRIK_EXIT_INVALID_INPUT"
        The stderr should include "interval"
      End

      It "fails on unknown option"
        When call transverse.wait.until _wait_spec_counter_check --not-a-flag value
        The status should equal "$BRIK_EXIT_INVALID_INPUT"
        The stderr should include "unknown option"
      End
    End

    Describe "message option"
      Before 'setup_counter'

      It "includes the custom message in logs"
        When call transverse.wait.until _wait_spec_counter_check --timeout 2 --interval 1 --message "waiting for sync"
        The status should be success
        The stderr should include "waiting for sync"
      End
    End

    Describe "check_fn with embedded arguments"
      # Mirrors deploy.gitops.wait_sync behaviour: check-fn can carry args.
      _wait_spec_arg_check() {
        [[ "$1" == "expected-arg" ]]
      }

      It "invokes check_fn with provided args"
        When call transverse.wait.until "_wait_spec_arg_check expected-arg" --timeout 2 --interval 1
        The status should be success
        The stderr should include "_wait_spec_arg_check"
      End

      It "rejects an arg-carrying string whose first word is not a function"
        When call transverse.wait.until "no_such_fn expected-arg" --timeout 2 --interval 1
        The status should equal "$BRIK_EXIT_INVALID_INPUT"
        The stderr should include "no_such_fn"
      End
    End
  End
End
