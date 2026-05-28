Describe "pipeline-env.sh"
  Include "$BRIK_PIPELINE_LIB/pipeline-env.sh"

  setup() {
    TEST_LOG_DIR="$(mktemp -d)"
    export BRIK_LOG_DIR="$TEST_LOG_DIR"
    unset BRIK_PIPELINE_ENV
  }
  cleanup() {
    rm -rf "$TEST_LOG_DIR"
    unset BRIK_PIPELINE_ENV
  }
  Before 'setup'
  After 'cleanup'

  Describe "pipeline.env.init"
    It "creates the pipeline env file"
      When call pipeline.env.init
      The status should be success
      The file "$BRIK_PIPELINE_ENV" should be exist
    End

    It "exports BRIK_PIPELINE_ENV"
      check_exported() {
        pipeline.env.init
        env | grep -q "^BRIK_PIPELINE_ENV="
      }
      When call check_exported
      The status should be success
    End

    It "does not destroy an existing file"
      preserve_content() {
        pipeline.env.init
        printf 'EXISTING=keep\n' >> "$BRIK_PIPELINE_ENV"
        pipeline.env.init
        grep -q "EXISTING=keep" "$BRIK_PIPELINE_ENV"
      }
      When call preserve_content
      The status should be success
    End
  End

  Describe "_pipeline.env.append"
    It "appends a variable to the file"
      set_and_check() {
        pipeline.env.init
        _pipeline.env.append "MY_KEY" "my_value"
        grep -q "MY_KEY=my_value" "$BRIK_PIPELINE_ENV"
      }
      When call set_and_check
      The status should be success
    End

    It "fails without prior init"
      When call _pipeline.env.append "KEY" "value"
      The status should equal "$BRIK_EXIT_IO_FAILURE"
      The stderr should be present
    End
  End

  Describe "pipeline.env.load"
    It "exports variables into the shell"
      set_and_load() {
        pipeline.env.init
        _pipeline.env.append "MY_VAR" "hello"
        pipeline.env.load
        printf '%s' "$MY_VAR"
      }
      When call set_and_load
      The output should equal "hello"
    End

    It "last write wins for duplicate keys"
      set_twice_and_load() {
        pipeline.env.init
        _pipeline.env.append "K" "v1"
        _pipeline.env.append "K" "v2"
        pipeline.env.load
        printf '%s' "$K"
      }
      When call set_twice_and_load
      The output should equal "v2"
    End

    It "is a silent no-op when file does not exist"
      When call pipeline.env.load
      The status should be success
      The stderr should equal ""
    End
  End

  # API surface lock-down (chantier env-channels-unification Phase 4).
  # Stages must publish through report.record env; the projection hook is
  # the only writer of the env file. Keeping pipeline.env.set as a public
  # callable would invite drift back to the dual-channel design.
  Describe "API surface"
    It "no longer exposes pipeline.env.set as a public function"
      check_pipeline_env_set_absent() {
        type pipeline.env.set >/dev/null 2>&1
      }
      When call check_pipeline_env_set_absent
      The status should be failure
    End
  End
End
