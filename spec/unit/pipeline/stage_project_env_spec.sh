Describe "_stage.run._project_env"
  Include "$BRIK_PIPELINE_LIB/pipeline-env.sh"
  Include "$BRIK_PIPELINE_LIB/report.sh"
  Include "$BRIK_PIPELINE_LIB/stage.sh"

  setup_workspace() {
    PROJECT_ENV_LOG_DIR="$(mktemp -d)"
    PROJECT_ENV_WORKSPACE="$(mktemp -d)"
    export BRIK_LOG_DIR="$PROJECT_ENV_LOG_DIR"
    export BRIK_WORKSPACE="$PROJECT_ENV_WORKSPACE"
    export BRIK_RUN_ID="run-fixture-project"
    pipeline.env.init >/dev/null
    report.init       >/dev/null
  }
  cleanup_workspace() {
    rm -rf "$PROJECT_ENV_LOG_DIR" "$PROJECT_ENV_WORKSPACE"
    unset BRIK_RUN_ID BRIK_PIPELINE_ENV
  }
  Before 'setup_workspace'
  After 'cleanup_workspace'

  It "is a no-op when the stage has no env section"
    no_env_section() {
      report.record "init" "tech" "status" "success" >/dev/null
      _stage.run._project_env "init" >/dev/null
      wc -c < "$BRIK_PIPELINE_ENV" | tr -d ' '
    }
    When call no_env_section
    The output should equal "0"
  End

  It "appends every recorded env key as KEY=value lines"
    project_two_keys() {
      report.record "init" "env" "FOO" "bar" >/dev/null
      report.record "init" "env" "BAZ" "qux" >/dev/null
      _stage.run._project_env "init" >/dev/null
      sort "$BRIK_PIPELINE_ENV"
    }
    When call project_two_keys
    The line 1 of output should equal "BAZ=qux"
    The line 2 of output should equal "FOO=bar"
  End

  It "round-trips through pipeline.env.load"
    project_then_load() {
      report.record "init" "env" "BRIK_PROJECTED" "hello world" >/dev/null
      _stage.run._project_env "init" >/dev/null
      pipeline.env.load
      printf '%s' "$BRIK_PROJECTED"
    }
    When call project_then_load
    The output should equal "hello world"
  End

  It "preserves an equal sign in the value"
    project_eq_value() {
      report.record "init" "env" "PAIR" "a=b" >/dev/null
      _stage.run._project_env "init" >/dev/null
      pipeline.env.load
      printf '%s' "$PAIR"
    }
    When call project_eq_value
    The output should equal "a=b"
  End

  It "preserves a multi-line value"
    project_multiline() {
      report.record "init" "env" "MULTILINE" "line1
line2" >/dev/null
      _stage.run._project_env "init" >/dev/null
      pipeline.env.load
      printf '%s' "$MULTILINE"
    }
    When call project_multiline
    The output should equal "line1
line2"
  End

  It "preserves a tab in the value"
    project_tab() {
      report.record "init" "env" "WITH_TAB" "a	b" >/dev/null
      _stage.run._project_env "init" >/dev/null
      pipeline.env.load
      printf '%s' "$WITH_TAB"
    }
    When call project_tab
    The output should equal "a	b"
  End

  It "ignores env keys recorded under a different stage"
    project_other_stage() {
      report.record "release" "env" "OTHER_STAGE" "leak" >/dev/null
      _stage.run._project_env "init" >/dev/null
      grep -c "OTHER_STAGE" "$BRIK_PIPELINE_ENV" || true
    }
    When call project_other_stage
    The output should equal "0"
  End

  It "is silent when the report backend is absent"
    project_no_backend() {
      rm -f "$BRIK_LOG_DIR/aggregate-report.json"
      _stage.run._project_env "init"
    }
    When call project_no_backend
    The status should be success
    The stderr should equal ""
  End
End
