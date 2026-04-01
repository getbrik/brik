Describe "env.sh"
  Include "$BRIK_RUNTIME_LIB/logging.sh"
  Include "$BRIK_RUNTIME_LIB/tools.sh"
  Include "$BRIK_CORE_LIB/env.sh"

  Describe "env.load"
    It "returns 2 for unknown option"
      When call env.load "staging" --badopt foo
      The status should equal 2
      The stderr should include "unknown option"
    End

    Describe "with missing env file"
      setup_missing() {
        TEST_DIR="$(mktemp -d)"
        export BRIK_PROJECT_DIR="$TEST_DIR"
      }
      cleanup_missing() {
        unset BRIK_PROJECT_DIR
        rm -rf "$TEST_DIR"
      }
      Before 'setup_missing'
      After 'cleanup_missing'

      It "warns when env file not found"
        When call env.load "staging"
        The status should be success
        The stderr should include "environment file not found"
      End
    End

    Describe "with valid env file"
      setup_env() {
        TEST_DIR="$(mktemp -d)"
        mkdir -p "${TEST_DIR}/.brik/env"
        printf 'export TEST_VAR_FOR_SPEC="hello_brik"\n' > "${TEST_DIR}/.brik/env/staging.env"
        export BRIK_PROJECT_DIR="$TEST_DIR"
      }
      cleanup_env() {
        unset BRIK_PROJECT_DIR TEST_VAR_FOR_SPEC
        rm -rf "$TEST_DIR"
      }
      Before 'setup_env'
      After 'cleanup_env'

      It "sources the env file and sets variable"
        invoke_source_check() {
          env.load "staging" 2>/dev/null || return 1
          [[ "$TEST_VAR_FOR_SPEC" == "hello_brik" ]]
        }
        When call invoke_source_check
        The status should be success
      End

      It "reports loading environment"
        When call env.load "staging"
        The status should be success
        The stderr should include "loading environment: staging"
      End
    End

    Describe "with custom config dir"
      setup_custom() {
        TEST_DIR="$(mktemp -d)"
        mkdir -p "${TEST_DIR}/custom"
        printf 'export CUSTOM_VAR_SPEC="custom_val"\n' > "${TEST_DIR}/custom/prod.env"
      }
      cleanup_custom() {
        unset CUSTOM_VAR_SPEC
        rm -rf "$TEST_DIR"
      }
      Before 'setup_custom'
      After 'cleanup_custom'

      It "uses custom config dir"
        invoke_custom_check() {
          env.load "prod" --config-dir "${TEST_DIR}/custom" 2>/dev/null || return 1
          [[ "$CUSTOM_VAR_SPEC" == "custom_val" ]]
        }
        When call invoke_custom_check
        The status should be success
      End
    End

    Describe "with malformed env file"
      setup_malformed() {
        TEST_DIR="$(mktemp -d)"
        mkdir -p "${TEST_DIR}/.brik/env"
        # Create a non-sourceable file (binary-like content)
        printf '\x00\x01\x02' > "${TEST_DIR}/.brik/env/bad.env"
        chmod -r "${TEST_DIR}/.brik/env/bad.env"
        export BRIK_PROJECT_DIR="$TEST_DIR"
      }
      cleanup_malformed() {
        unset BRIK_PROJECT_DIR
        chmod +r "${TEST_DIR}/.brik/env/bad.env" 2>/dev/null
        rm -rf "$TEST_DIR"
      }
      Before 'setup_malformed'
      After 'cleanup_malformed'

      It "returns 5 when env file fails to source"
        When call env.load "bad"
        The status should equal 5
        The stderr should include "failed to source"
      End
    End
  End

  Describe "env.require"
    Describe "with set variables"
      setup_vars() {
        export BRIK_TEST_A="a"
        export BRIK_TEST_B="b"
      }
      cleanup_vars() {
        unset BRIK_TEST_A BRIK_TEST_B
      }
      Before 'setup_vars'
      After 'cleanup_vars'

      It "succeeds when all variables are set"
        When call env.require BRIK_TEST_A BRIK_TEST_B
        The status should be success
      End
    End

    It "returns 4 when a variable is missing"
      When call env.require BRIK_NONEXISTENT_VAR_SPEC
      The status should equal 4
      The stderr should include "required environment variable not set"
    End

    It "reports which variable is missing"
      When call env.require BRIK_NONEXISTENT_VAR_SPEC
      The status should equal 4
      The stderr should include "BRIK_NONEXISTENT_VAR_SPEC"
    End

    Describe "with empty variable"
      setup_empty() {
        export BRIK_EMPTY_VAR_SPEC=""
      }
      cleanup_empty() {
        unset BRIK_EMPTY_VAR_SPEC
      }
      Before 'setup_empty'
      After 'cleanup_empty'

      It "returns 4 when variable is empty"
        When call env.require BRIK_EMPTY_VAR_SPEC
        The status should equal 4
        The stderr should include "required environment variable not set"
      End
    End

    Describe "multi-variable where second is missing"
      setup_partial() {
        export BRIK_FIRST_VAR="exists"
      }
      cleanup_partial() {
        unset BRIK_FIRST_VAR
      }
      Before 'setup_partial'
      After 'cleanup_partial'

      It "returns 4 and reports the missing variable"
        When call env.require BRIK_FIRST_VAR BRIK_SECOND_VAR_MISSING
        The status should equal 4
        The stderr should include "BRIK_SECOND_VAR_MISSING"
      End
    End
  End
End
