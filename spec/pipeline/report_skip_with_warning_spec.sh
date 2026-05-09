Describe "stage.skip_with_warning + summary.warnings"
  Include "$BRIK_PIPELINE_LIB/stage.sh"
  Include "$BRIK_PIPELINE_LIB/report.sh"
  Include "$BRIK_HOME/spec/support/mock_helper.sh"

  setup_dirs() {
    REPORT_LOG_DIR="$(mktemp -d)"
    export BRIK_LOG_DIR="$REPORT_LOG_DIR"
    mock.workspace.setup
    REPORT_WORKSPACE="$BRIK_WORKSPACE"
    export BRIK_RUN_ID="run-skip-warning-fixture"
    unset BRIK_PLATFORM BRIK_RUNNER_IMAGE CI_JOB_URL BUILD_URL
  }
  cleanup_dirs() {
    rm -rf "$REPORT_LOG_DIR"
    mock.workspace.teardown
    unset BRIK_LOG_DIR BRIK_RUN_ID
    unset BRIK_PLATFORM BRIK_RUNNER_IMAGE CI_JOB_URL BUILD_URL
  }

  # ---------------------------------------------------------------------------
  # stage.skip_with_warning helper
  # ---------------------------------------------------------------------------
  Describe "stage.skip_with_warning"
    Before 'setup_dirs'
    After 'cleanup_dirs'

    It "returns BRIK_EXIT_INVALID_INPUT when arity is wrong"
      wrong_arity() {
        report.init >/dev/null 2>&1
        stage.skip_with_warning "lint"
      }
      When call wrong_arity
      The status should equal "$BRIK_EXIT_INVALID_INPUT"
      The stderr should include "expects 2 arguments"
    End

    It "returns BRIK_EXIT_SKIP_WITH_WARNING (99) on valid call"
      skip_lint() {
        report.init >/dev/null 2>&1
        stage.skip_with_warning "lint" "user disabled outside release"
      }
      When call skip_lint
      The status should equal 99
      The status should equal "$BRIK_EXIT_SKIP_WITH_WARNING"
      The stderr should include "skipped with warning"
    End

    It "logs a warn with the reason"
      skip_with_log() {
        report.init >/dev/null 2>&1
        stage.skip_with_warning "lint" "user disabled outside release"
      }
      When call skip_with_log
      The status should equal "$BRIK_EXIT_SKIP_WITH_WARNING"
      The stderr should include "lint"
      The stderr should include "user disabled outside release"
    End

    It "records tech.status=skipped on the backend"
      skip_record_status() {
        report.init >/dev/null 2>&1
        stage.skip_with_warning "sast" "user disabled outside release" >/dev/null 2>&1
        jq -r '.stages[] | select(.name=="sast") | .tech.status' \
            "${BRIK_LOG_DIR}/aggregate-report.json"
      }
      When call skip_record_status
      The output should equal "skipped"
    End

    It "records tech.warning=true on the backend"
      skip_record_warning() {
        report.init >/dev/null 2>&1
        stage.skip_with_warning "scan" "user disabled outside release" >/dev/null 2>&1
        jq -r '.stages[] | select(.name=="scan") | .tech.warning' \
            "${BRIK_LOG_DIR}/aggregate-report.json"
      }
      When call skip_record_warning
      The output should equal "true"
    End

    It "records tech.warning_reason with the reason text"
      skip_record_reason() {
        report.init >/dev/null 2>&1
        stage.skip_with_warning "scan" "user disabled outside release" >/dev/null 2>&1
        jq -r '.stages[] | select(.name=="scan") | .tech.warning_reason' \
            "${BRIK_LOG_DIR}/aggregate-report.json"
      }
      When call skip_record_reason
      The output should equal "user disabled outside release"
    End
  End

  # ---------------------------------------------------------------------------
  # report.aggregate_fragments compiles summary.warnings
  # ---------------------------------------------------------------------------
  Describe "summary.warnings in aggregate"
    Before 'setup_dirs'
    After 'cleanup_dirs'

    write_warning_fragment() {
      local stage="$1" reason="$2"
      local dir="${BRIK_WORKSPACE}/brik-artifacts"
      mkdir -p "$dir/${stage}"
      cat > "${dir}/${stage}/${stage}.json" <<EOF
{
  "schema_version": "1.0",
  "stage": "${stage}",
  "timestamp": "2026-05-03T10:00:00+0000",
  "rc": 99,
  "status": "skipped",
  "runner": { "platform": "test" },
  "tech": {
    "status": "skipped",
    "warning": true,
    "warning_reason": "${reason}"
  },
  "business": {}
}
EOF
    }

    write_success_fragment() {
      local stage="$1"
      local dir="${BRIK_WORKSPACE}/brik-artifacts"
      mkdir -p "$dir/${stage}"
      cat > "${dir}/${stage}/${stage}.json" <<EOF
{
  "schema_version": "1.0",
  "stage": "${stage}",
  "timestamp": "2026-05-03T10:00:00+0000",
  "rc": 0,
  "status": "success",
  "runner": { "platform": "test" },
  "tech": { "status": "success" },
  "business": {}
}
EOF
    }

    It "produces an empty summary.warnings array when no fragment carries tech.warning"
      no_warnings() {
        write_success_fragment "build"
        write_success_fragment "test"
        report.aggregate_fragments "${BRIK_WORKSPACE}/brik-artifacts" >/dev/null 2>&1
        jq -c '.summary.warnings' "${BRIK_LOG_DIR}/aggregate-report.json"
      }
      When call no_warnings
      The output should equal "[]"
    End

    It "compiles summary.warnings with one entry per warned stage"
      one_warning() {
        write_success_fragment "build"
        write_warning_fragment "lint" "user disabled outside release"
        report.aggregate_fragments "${BRIK_WORKSPACE}/brik-artifacts" >/dev/null 2>&1
        jq -c '.summary.warnings' "${BRIK_LOG_DIR}/aggregate-report.json"
      }
      When call one_warning
      The output should equal '[{"stage":"lint","reason":"user disabled outside release"}]'
    End

    It "compiles multiple warnings preserving stage order from fragments"
      multiple_warnings() {
        write_warning_fragment "lint" "lint disabled"
        write_warning_fragment "sast" "sast disabled"
        write_warning_fragment "scan" "scan disabled"
        report.aggregate_fragments "${BRIK_WORKSPACE}/brik-artifacts" >/dev/null 2>&1
        jq -r '.summary.warnings | length' "${BRIK_LOG_DIR}/aggregate-report.json"
      }
      When call multiple_warnings
      The output should equal "3"
    End

    It "ignores fragments where tech.warning is missing or false"
      mixed_fragments() {
        write_success_fragment "build"
        write_warning_fragment "lint" "lint disabled"
        local dir="${BRIK_WORKSPACE}/brik-artifacts"
        mkdir -p "${dir}/deploy"
        cat > "${dir}/deploy/deploy.json" <<'EOF'
{
  "schema_version": "1.0",
  "stage": "deploy",
  "timestamp": "2026-05-03T10:00:00+0000",
  "rc": 0,
  "status": "skipped",
  "runner": { "platform": "test" },
  "tech": { "status": "skipped" },
  "business": {}
}
EOF
        report.aggregate_fragments "${BRIK_WORKSPACE}/brik-artifacts" >/dev/null 2>&1
        jq -r '.summary.warnings | length' "${BRIK_LOG_DIR}/aggregate-report.json"
      }
      When call mixed_fragments
      The output should equal "1"
    End
  End
End
