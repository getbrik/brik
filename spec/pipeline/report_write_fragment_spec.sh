Describe "report.write_fragment"
  Include "$BRIK_PIPELINE_LIB/report.sh"
  Include "$BRIK_HOME/spec/support/mock_helper.sh"

  FRAGMENT_SCHEMA="${BRIK_HOME}/schemas/report/v1/fragment.schema.json"
  jv_missing() { ! command -v jv >/dev/null 2>&1; }

  # Validates a fragment file against the v1 fragment schema using jv.
  # Stdout/stderr are redirected so ShellSpec only sees the rc.
  validate_fragment_file() {
    jv "$FRAGMENT_SCHEMA" "$1" >/dev/null 2>&1
  }

  setup_dirs() {
    REPORT_LOG_DIR="$(mktemp -d)"
    export BRIK_LOG_DIR="$REPORT_LOG_DIR"
    mock.workspace.setup
    REPORT_WORKSPACE="$BRIK_WORKSPACE"
    export BRIK_RUN_ID="run-fixture-42"
    # Clear runner provenance so individual examples opt-in explicitly.
    unset BRIK_PLATFORM BRIK_RUNNER_IMAGE CI_JOB_URL BUILD_URL
  }
  cleanup_dirs() {
    rm -rf "$REPORT_LOG_DIR"
    mock.workspace.teardown
    unset BRIK_LOG_DIR BRIK_RUN_ID
    unset BRIK_PLATFORM BRIK_RUNNER_IMAGE CI_JOB_URL BUILD_URL
  }

  # ---------------------------------------------------------------------------
  # Argument validation
  # ---------------------------------------------------------------------------
  Describe "argument validation"
    Before 'setup_dirs'
    After 'cleanup_dirs'

    It "returns BRIK_EXIT_INVALID_INPUT when no stage is given"
      no_arg() {
        report.init >/dev/null 2>&1
        report.write_fragment
      }
      When call no_arg
      The status should equal "$BRIK_EXIT_INVALID_INPUT"
      The error should include "stage"
    End

    It "returns BRIK_EXIT_INVALID_INPUT when too many args are given"
      too_many() {
        report.init >/dev/null 2>&1
        report.write_fragment "build" "extra"
      }
      When call too_many
      The status should equal "$BRIK_EXIT_INVALID_INPUT"
      The error should include "expects 1 argument"
    End
  End

  # ---------------------------------------------------------------------------
  # Backend prerequisites
  # ---------------------------------------------------------------------------
  Describe "missing prerequisites"
    Before 'setup_dirs'
    After 'cleanup_dirs'

    It "returns BRIK_EXIT_IO_FAILURE when the backend aggregate-report.json is absent"
      no_backend() {
        report.write_fragment "build"
      }
      When call no_backend
      The status should equal "$BRIK_EXIT_IO_FAILURE"
      The error should include "report"
    End

    It "returns BRIK_EXIT_MISSING_DEP when jq is not on PATH"
      no_jq() {
        report.init >/dev/null 2>&1
        local saved_path="$PATH"
        export PATH="/nonexistent_dir_only"
        # When PATH is sterilised, even date/tr that the logger uses are
        # missing, so stderr noise from the logger is unavoidable. We only
        # care about the return code.
        report.write_fragment "build" >/dev/null 2>&1
        local rc=$?
        export PATH="$saved_path"
        return "$rc"
      }
      When call no_jq
      The status should equal "$BRIK_EXIT_MISSING_DEP"
    End
  End

  # ---------------------------------------------------------------------------
  # Happy path: stage with full backend entry
  # ---------------------------------------------------------------------------
  Describe "happy path: stage with full backend entry"
    Before 'setup_dirs'
    After 'cleanup_dirs'

    seed_full_build() {
      report.init >/dev/null 2>&1 || return 1
      report.record "build" "tech" "status" "success" || return 1
      report.record "build" "tech" "duration_ms" "1234" || return 1
      report.record "build" "tech" "exit_code" "0" || return 1
      report.record "build" "business" "stack" "java" || return 1
    }

    It "creates brik-artifacts/<stage>.json under BRIK_WORKSPACE"
      do_write() {
        seed_full_build || return 1
        report.write_fragment "build"
      }
      When call do_write
      The status should be success
      The file "$REPORT_WORKSPACE/brik-artifacts/build/build.json" should be exist
    End

    It "writes a fragment with schema_version 1.0"
      read_schema_version() {
        seed_full_build && report.write_fragment "build" || return 1
        jq -r '.schema_version' "$REPORT_WORKSPACE/brik-artifacts/build/build.json"
      }
      When call read_schema_version
      The output should equal "1.0"
    End

    It "writes a fragment with the requested stage name"
      read_stage_name() {
        seed_full_build && report.write_fragment "build" || return 1
        jq -r '.stage' "$REPORT_WORKSPACE/brik-artifacts/build/build.json"
      }
      When call read_stage_name
      The output should equal "build"
    End

    It "carries the recorded tech.status as fragment.status"
      read_status() {
        seed_full_build && report.write_fragment "build" || return 1
        jq -r '.status' "$REPORT_WORKSPACE/brik-artifacts/build/build.json"
      }
      When call read_status
      The output should equal "success"
    End

    It "carries the recorded tech.exit_code as fragment.rc (numeric)"
      read_rc() {
        seed_full_build && report.write_fragment "build" || return 1
        jq '.rc' "$REPORT_WORKSPACE/brik-artifacts/build/build.json"
      }
      When call read_rc
      The output should equal "0"
    End

    It "carries the recorded tech.duration_ms as fragment.duration_ms (numeric)"
      read_duration() {
        seed_full_build && report.write_fragment "build" || return 1
        jq '.duration_ms' "$REPORT_WORKSPACE/brik-artifacts/build/build.json"
      }
      When call read_duration
      The output should equal "1234"
    End

    It "preserves the full tech subtree from the backend"
      read_tech_status() {
        seed_full_build && report.write_fragment "build" || return 1
        jq -r '.tech.status' "$REPORT_WORKSPACE/brik-artifacts/build/build.json"
      }
      When call read_tech_status
      The output should equal "success"
    End

    It "preserves the full business subtree from the backend"
      read_business_stack() {
        seed_full_build && report.write_fragment "build" || return 1
        jq -r '.business.stack' "$REPORT_WORKSPACE/brik-artifacts/build/build.json"
      }
      When call read_business_stack
      The output should equal "java"
    End

    It "stamps an ISO-8601 timestamp with timezone offset"
      read_timestamp() {
        seed_full_build && report.write_fragment "build" || return 1
        jq -r '.timestamp' "$REPORT_WORKSPACE/brik-artifacts/build/build.json"
      }
      When call read_timestamp
      The output should match pattern '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]*'
    End

    It "produces a fragment that validates against fragment.schema.json"
      Skip if "jv not installed" jv_missing
      do_write_then_validate() {
        seed_full_build && report.write_fragment "build" || return 1
        validate_fragment_file "$REPORT_WORKSPACE/brik-artifacts/build/build.json"
      }
      When call do_write_then_validate
      The status should be success
    End
  End

  # ---------------------------------------------------------------------------
  # Runner provenance envelope
  # ---------------------------------------------------------------------------
  Describe "runner envelope"
    Before 'setup_dirs'
    After 'cleanup_dirs'

    seed_minimal() {
      report.init >/dev/null 2>&1 || return 1
      report.record "init" "tech" "status" "success" || return 1
      report.record "init" "tech" "exit_code" "0" || return 1
    }

    It "defaults runner.platform to 'local' when BRIK_PLATFORM is unset"
      read_platform() {
        seed_minimal && report.write_fragment "init" || return 1
        jq -r '.runner.platform' "$REPORT_WORKSPACE/brik-artifacts/init/init.json"
      }
      When call read_platform
      The output should equal "local"
    End

    It "uses BRIK_PLATFORM as runner.platform when set"
      read_platform() {
        export BRIK_PLATFORM="gitlab"
        seed_minimal && report.write_fragment "init" || return 1
        jq -r '.runner.platform' "$REPORT_WORKSPACE/brik-artifacts/init/init.json"
      }
      When call read_platform
      The output should equal "gitlab"
    End

    It "carries BRIK_RUNNER_IMAGE as runner.image when set"
      read_image() {
        export BRIK_PLATFORM="gitlab"
        export BRIK_RUNNER_IMAGE="ghcr.io/getbrik/brik-runner-java:21"
        seed_minimal && report.write_fragment "init" || return 1
        jq -r '.runner.image' "$REPORT_WORKSPACE/brik-artifacts/init/init.json"
      }
      When call read_image
      The output should equal "ghcr.io/getbrik/brik-runner-java:21"
    End

    It "carries CI_JOB_URL as runner.job_url on GitLab"
      read_job_url() {
        export BRIK_PLATFORM="gitlab"
        export CI_JOB_URL="https://gitlab.example.com/jobs/123"
        seed_minimal && report.write_fragment "init" || return 1
        jq -r '.runner.job_url' "$REPORT_WORKSPACE/brik-artifacts/init/init.json"
      }
      When call read_job_url
      The output should equal "https://gitlab.example.com/jobs/123"
    End

    It "falls back to BUILD_URL as runner.job_url on Jenkins"
      read_job_url() {
        export BRIK_PLATFORM="jenkins"
        export BUILD_URL="https://jenkins.example.com/job/my-app/42/"
        seed_minimal && report.write_fragment "init" || return 1
        jq -r '.runner.job_url' "$REPORT_WORKSPACE/brik-artifacts/init/init.json"
      }
      When call read_job_url
      The output should equal "https://jenkins.example.com/job/my-app/42/"
    End

    It "omits runner.image when BRIK_RUNNER_IMAGE is unset"
      check_no_image() {
        seed_minimal && report.write_fragment "init" || return 1
        jq 'has("runner") and (.runner | has("image") | not)' \
          "$REPORT_WORKSPACE/brik-artifacts/init/init.json"
      }
      When call check_no_image
      The output should equal "true"
    End
  End

  # ---------------------------------------------------------------------------
  # Stub fragment when stage has no backend entry yet
  # ---------------------------------------------------------------------------
  Describe "stage absent from backend"
    Before 'setup_dirs'
    After 'cleanup_dirs'

    It "writes a stub fragment with status=skipped and rc=0"
      stub_status() {
        report.init >/dev/null 2>&1 || return 1
        report.write_fragment "release" || return 1
        jq -r '.status' "$REPORT_WORKSPACE/brik-artifacts/release/release.json"
      }
      When call stub_status
      The output should equal "skipped"
    End

    It "stub fragment has rc=0 when stage absent from backend"
      stub_rc() {
        report.init >/dev/null 2>&1 || return 1
        report.write_fragment "release" || return 1
        jq '.rc' "$REPORT_WORKSPACE/brik-artifacts/release/release.json"
      }
      When call stub_rc
      The output should equal "0"
    End

    It "stub fragment validates against fragment.schema.json"
      Skip if "jv not installed" jv_missing
      stub_validates() {
        report.init >/dev/null 2>&1 || return 1
        report.write_fragment "release" || return 1
        validate_fragment_file "$REPORT_WORKSPACE/brik-artifacts/release/release.json"
      }
      When call stub_validates
      The status should be success
    End
  End

  # ---------------------------------------------------------------------------
  # Failed status mapping
  # ---------------------------------------------------------------------------
  Describe "failed stage"
    Before 'setup_dirs'
    After 'cleanup_dirs'

    seed_failed_test() {
      report.init >/dev/null 2>&1 || return 1
      report.record "test" "tech" "status" "failed" || return 1
      report.record "test" "tech" "exit_code" "1" || return 1
    }

    It "fragment.status is failed"
      read_status() {
        seed_failed_test && report.write_fragment "test" || return 1
        jq -r '.status' "$REPORT_WORKSPACE/brik-artifacts/test/test.json"
      }
      When call read_status
      The output should equal "failed"
    End

    It "fragment.rc is 1"
      read_rc() {
        seed_failed_test && report.write_fragment "test" || return 1
        jq '.rc' "$REPORT_WORKSPACE/brik-artifacts/test/test.json"
      }
      When call read_rc
      The output should equal "1"
    End

    It "produces a fragment that validates against fragment.schema.json"
      Skip if "jv not installed" jv_missing
      validates_failed() {
        seed_failed_test && report.write_fragment "test" || return 1
        validate_fragment_file "$REPORT_WORKSPACE/brik-artifacts/test/test.json"
      }
      When call validates_failed
      The status should be success
    End
  End

  # ---------------------------------------------------------------------------
  # Status fallback when only business entry exists (no tech.status set)
  # ---------------------------------------------------------------------------
  Describe "stage with business entry only"
    Before 'setup_dirs'
    After 'cleanup_dirs'

    It "fragment.status defaults to skipped when tech.status is absent"
      do_write() {
        report.init >/dev/null 2>&1 || return 1
        report.record "init" "business" "stack" "node" || return 1
        report.write_fragment "init" || return 1
        jq -r '.status' "$REPORT_WORKSPACE/brik-artifacts/init/init.json"
      }
      When call do_write
      The output should equal "skipped"
    End
  End

  # ---------------------------------------------------------------------------
  # Workspace fallback for local mode
  # ---------------------------------------------------------------------------
  Describe "BRIK_WORKSPACE fallback to BRIK_LOG_DIR"
    setup_no_workspace() {
      REPORT_LOG_DIR="$(mktemp -d)"
      export BRIK_LOG_DIR="$REPORT_LOG_DIR"
      export BRIK_RUN_ID="run-fixture-43"
      unset BRIK_WORKSPACE BRIK_PLATFORM BRIK_RUNNER_IMAGE CI_JOB_URL BUILD_URL
    }
    cleanup_no_workspace() {
      rm -rf "$REPORT_LOG_DIR"
      unset BRIK_LOG_DIR BRIK_RUN_ID
    }
    Before 'setup_no_workspace'
    After 'cleanup_no_workspace'

    It "writes the fragment under BRIK_LOG_DIR/brik-artifacts/<stage>.json when BRIK_WORKSPACE is unset"
      fallback_path() {
        report.init >/dev/null 2>&1 || return 1
        report.record "build" "tech" "status" "success" || return 1
        report.write_fragment "build" || return 1
        test -f "$REPORT_LOG_DIR/brik-artifacts/build/build.json"
      }
      When call fallback_path
      The status should be success
    End
  End

  # ---------------------------------------------------------------------------
  # Atomic write
  # ---------------------------------------------------------------------------
  Describe "atomic write"
    Before 'setup_dirs'
    After 'cleanup_dirs'

    It "leaves no partial fragment if the function is interrupted"
      atomic_check() {
        report.init >/dev/null 2>&1 || return 1
        report.record "build" "tech" "status" "success" || return 1
        report.write_fragment "build" || return 1
        # No .tmp / .XXXXXX leftover next to the final file
        ls -1 "$REPORT_WORKSPACE/brik-artifacts/build/" | grep -cE '^build\.json' || true
      }
      When call atomic_check
      The output should equal "1"
    End
  End
End
