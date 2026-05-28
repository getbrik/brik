Describe "fragments emitted by the runtime validate against v1.1"
  Include "$BRIK_PIPELINE_LIB/stage.sh"
  Include "$BRIK_HOME/spec/support/mock_helper.sh"

  FRAGMENT_V11_SCHEMA="${BRIK_HOME}/schemas/report/v1.1/fragment.schema.json"
  jv_missing() { ! command -v jv >/dev/null 2>&1; }

  setup_dirs() {
    SE_LOG_DIR="$(mktemp -d)"
    export BRIK_LOG_DIR="$SE_LOG_DIR"
    mock.workspace.setup
    SE_WORKSPACE="$BRIK_WORKSPACE"
    export BRIK_RUN_ID="run-fixture-emit11"
    export BRIK_PROJECT_DIR="/nonexistent"
    export BRIK_PLATFORM="local"
    unset BRIK_DISABLE_REPORT_FRAGMENTS BRIK_COMMIT_TAG
    report.init >/dev/null 2>&1
  }
  cleanup_dirs() {
    rm -rf "$SE_LOG_DIR"
    mock.workspace.teardown
    unset BRIK_LOG_DIR BRIK_RUN_ID BRIK_PROJECT_DIR BRIK_PLATFORM
    unset BRIK_DISABLE_REPORT_FRAGMENTS BRIK_COMMIT_TAG
  }

  Before 'setup_dirs'
  After 'cleanup_dirs'

  success_logic() { return 0; }
  fail_logic() { return 1; }

  It "schema_version is 1.1 on a successful stage fragment"
    do_run() {
      stage.run "build" "success_logic" >/dev/null 2>&1
      jq -r '.schema_version' "${SE_WORKSPACE}/brik-artifacts/build/build.json"
    }
    When call do_run
    The output should equal "1.1"
  End

  It "validates against v1.1 strict on a successful stage"
    Skip if "jv not installed" jv_missing
    do_validate() {
      stage.run "build" "success_logic" >/dev/null 2>&1
      jv "$FRAGMENT_V11_SCHEMA" \
         "${SE_WORKSPACE}/brik-artifacts/build/build.json" >/dev/null 2>&1
    }
    When call do_validate
    The status should be success
  End

  It "validates against v1.1 strict on a failing stage (snapshot context)"
    Skip if "jv not installed" jv_missing
    do_validate() {
      stage.run "build" "fail_logic" >/dev/null 2>&1 || true
      jv "$FRAGMENT_V11_SCHEMA" \
         "${SE_WORKSPACE}/brik-artifacts/build/build.json" >/dev/null 2>&1
    }
    When call do_validate
    The status should be success
  End

  It "validates against v1.1 strict on a failing stage (release context)"
    Skip if "jv not installed" jv_missing
    do_validate() {
      export BRIK_COMMIT_TAG="v9.9.9"
      stage.run "build" "fail_logic" >/dev/null 2>&1 || true
      jv "$FRAGMENT_V11_SCHEMA" \
         "${SE_WORKSPACE}/brik-artifacts/build/build.json" >/dev/null 2>&1
    }
    When call do_validate
    The status should be success
  End

  It "carries no tech.warning field"
    do_check() {
      stage.run "build" "fail_logic" >/dev/null 2>&1 || true
      jq -r '.tech.warning // "absent"' \
         "${SE_WORKSPACE}/brik-artifacts/build/build.json"
    }
    When call do_check
    The output should equal "absent"
  End

  It "carries no tech.warning_reason field"
    do_check() {
      stage.run "build" "fail_logic" >/dev/null 2>&1 || true
      jq -r '.tech.warning_reason // "absent"' \
         "${SE_WORKSPACE}/brik-artifacts/build/build.json"
    }
    When call do_check
    The output should equal "absent"
  End
End
