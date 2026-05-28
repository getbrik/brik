Describe "_stage._finalize_fragment writes business.{status,reason}"
  Include "$BRIK_PIPELINE_LIB/stage.sh"
  Include "$BRIK_HOME/spec/support/mock_helper.sh"

  setup_dirs() {
    SR_LOG_DIR="$(mktemp -d)"
    export BRIK_LOG_DIR="$SR_LOG_DIR"
    mock.workspace.setup
    SR_WORKSPACE="$BRIK_WORKSPACE"
    export BRIK_RUN_ID="run-fixture-finalize"
    export BRIK_PROJECT_DIR="/nonexistent"
    unset BRIK_DISABLE_REPORT_FRAGMENTS BRIK_PLATFORM
    unset BRIK_COMMIT_TAG
    report.init >/dev/null 2>&1
  }
  cleanup_dirs() {
    rm -rf "$SR_LOG_DIR"
    mock.workspace.teardown
    unset BRIK_LOG_DIR BRIK_RUN_ID BRIK_PROJECT_DIR
    unset BRIK_DISABLE_REPORT_FRAGMENTS BRIK_PLATFORM
    unset BRIK_COMMIT_TAG
  }

  read_business_status() {
    jq -r '.business.status // empty' "$SR_WORKSPACE/brik-artifacts/$1/$1.json"
  }
  read_business_reason() {
    jq -r '.business.reason // empty' "$SR_WORKSPACE/brik-artifacts/$1/$1.json"
  }

  Describe "snapshot context"
    Before 'setup_dirs'
    After 'cleanup_dirs'

    success_logic() { return 0; }
    fail_logic() { return 1; }
    success_with_ignored_logic() {
      report.record_object "lint" "business" "findings" '{"ignored":{"total":3}}'
      return 0
    }
    self_skip_not_applicable_logic() {
      report.record "lint" "tech" "status" "skipped"
      report.record "lint" "tech" "kind"   "not-applicable"
      return 0
    }

    It "success without findings: business.status=success"
      do_run() {
        stage.run "build" "success_logic" >/dev/null 2>&1
        read_business_status "build"
      }
      When call do_run
      The output should equal "success"
    End

    It "success without findings: business.reason is empty"
      do_run() {
        stage.run "build" "success_logic" >/dev/null 2>&1
        read_business_reason "build"
      }
      When call do_run
      The output should equal ""
    End

    It "success with side-band findings.ignored.total=3: business.status=warning"
      do_run() {
        stage.run "lint" "success_with_ignored_logic" >/dev/null 2>&1
        read_business_status "lint"
      }
      When call do_run
      The output should equal "warning"
    End

    It "success with side-band findings.ignored.total=3: business.reason mentions 'accepted by policy'"
      do_run() {
        stage.run "lint" "success_with_ignored_logic" >/dev/null 2>&1
        read_business_reason "lint"
      }
      When call do_run
      The output should include "accepted by policy"
    End

    It "failed: business.status=warning (snapshot lets it through)"
      do_run() {
        stage.run "build" "fail_logic" >/dev/null 2>&1 || true
        read_business_status "build"
      }
      When call do_run
      The output should equal "warning"
    End

    It "failed: business.reason mentions 'fix available' (default conservative classification)"
      do_run() {
        stage.run "build" "fail_logic" >/dev/null 2>&1 || true
        read_business_reason "build"
      }
      When call do_run
      The output should include "fix available"
    End

    It "self-skipped (not-applicable): business.status=success"
      do_run() {
        stage.run "lint" "self_skip_not_applicable_logic" >/dev/null 2>&1
        read_business_status "lint"
      }
      When call do_run
      The output should equal "success"
    End

    It "self-skipped: business.reason is 'not applicable'"
      do_run() {
        stage.run "lint" "self_skip_not_applicable_logic" >/dev/null 2>&1
        read_business_reason "lint"
      }
      When call do_run
      The output should equal "not applicable"
    End
  End

  Describe "release context"
    Before 'setup_dirs'
    After 'cleanup_dirs'

    fail_logic() { return 1; }

    It "failed: business.status=error"
      do_run() {
        export BRIK_COMMIT_TAG="v9.9.9"
        stage.run "build" "fail_logic" >/dev/null 2>&1 || true
        read_business_status "build"
      }
      When call do_run
      The output should equal "error"
    End

    It "failed: business.reason mentions 'not applied' (release-strict default)"
      do_run() {
        export BRIK_COMMIT_TAG="v9.9.9"
        stage.run "build" "fail_logic" >/dev/null 2>&1 || true
        read_business_reason "build"
      }
      When call do_run
      The output should include "not applied"
    End
  End

  Describe "fix_classification axis (SC16 acceptance)"
    Before 'setup_dirs'
    After 'cleanup_dirs'

    # Logic helpers that pre-populate business.findings.failing with the
    # fix-class shape used by SC1 schema v1.1 before signalling tech.failed.

    # Each helper pre-populates business.findings.failing with the v1.1
    # shape, then returns 1 to make the stage tech.status=failed (the
    # branch where business.evaluate consumes fix_class).

    fail_with_has_fix_logic() {
      report.record_object "scan" "business" "findings" \
        '{"failing":{"total":1,"has_fix":1,"no_fix":0}}'
      return 1
    }
    fail_with_no_fix_logic() {
      report.record_object "scan" "business" "findings" \
        '{"failing":{"total":1,"has_fix":0,"no_fix":1}}'
      return 1
    }
    fail_with_unknown_logic() {
      report.record_object "scan" "business" "findings" \
        '{"failing":{"total":1,"has_fix":0,"no_fix":0}}'
      return 1
    }

    It "snapshot + has_fix: business.status=warning"
      do_run() {
        stage.run "scan" "fail_with_has_fix_logic" >/dev/null 2>&1 || true
        read_business_status "scan"
      }
      When call do_run
      The output should equal "warning"
    End

    It "snapshot + has_fix: business.reason mentions 'fix available'"
      do_run() {
        stage.run "scan" "fail_with_has_fix_logic" >/dev/null 2>&1 || true
        read_business_reason "scan"
      }
      When call do_run
      The output should include "fix available"
    End

    It "snapshot + no_fix only: business.status=warning"
      do_run() {
        stage.run "scan" "fail_with_no_fix_logic" >/dev/null 2>&1 || true
        read_business_status "scan"
      }
      When call do_run
      The output should equal "warning"
    End

    It "snapshot + no_fix only: business.reason mentions 'no fix available'"
      do_run() {
        stage.run "scan" "fail_with_no_fix_logic" >/dev/null 2>&1 || true
        read_business_reason "scan"
      }
      When call do_run
      The output should include "no fix available"
    End

    It "release + has_fix: business.status=error"
      do_run() {
        export BRIK_COMMIT_TAG="v9.9.9"
        stage.run "scan" "fail_with_has_fix_logic" >/dev/null 2>&1 || true
        read_business_status "scan"
      }
      When call do_run
      The output should equal "error"
    End

    It "release + has_fix: business.reason mentions 'fix available' AND 'not applied'"
      do_run() {
        export BRIK_COMMIT_TAG="v9.9.9"
        stage.run "scan" "fail_with_has_fix_logic" >/dev/null 2>&1 || true
        read_business_reason "scan"
      }
      When call do_run
      The output should include "fix available"
      The output should include "not applied"
    End

    It "release + no_fix only: business.status=warning (no upstream fix to apply)"
      do_run() {
        export BRIK_COMMIT_TAG="v9.9.9"
        stage.run "scan" "fail_with_no_fix_logic" >/dev/null 2>&1 || true
        read_business_status "scan"
      }
      When call do_run
      The output should equal "warning"
    End

    It "release + unknown remainder behaves like has_fix (conservative default)"
      do_run() {
        export BRIK_COMMIT_TAG="v9.9.9"
        stage.run "scan" "fail_with_unknown_logic" >/dev/null 2>&1 || true
        read_business_status "scan"
      }
      When call do_run
      # The matrix prefers has_fix when failing_unknown > 0 and
      # failing_has_fix == 0: priority chain in business.sh
      # has_fix > unknown > no_fix.
      The output should equal "error"
    End
  End

  Describe "tech.* preservation (no regression)"
    Before 'setup_dirs'
    After 'cleanup_dirs'

    success_logic() { return 0; }

    It "tech.status is still recorded alongside business"
      do_run() {
        stage.run "build" "success_logic" >/dev/null 2>&1
        jq -r '.tech.status' "$SR_WORKSPACE/brik-artifacts/build/build.json"
      }
      When call do_run
      The output should equal "success"
    End

    It "tech.exit_code is still recorded alongside business"
      do_run() {
        stage.run "build" "success_logic" >/dev/null 2>&1
        jq -r '.tech.exit_code' "$SR_WORKSPACE/brik-artifacts/build/build.json"
      }
      When call do_run
      The output should equal "0"
    End
  End
End
