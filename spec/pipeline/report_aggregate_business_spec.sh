Describe "report.aggregate_fragments emits summary.business + pipeline.business.status"
  Include "$BRIK_PIPELINE_LIB/report.sh"

  setup_dirs() {
    AB_LOG_DIR="$(mktemp -d)"
    AB_FRAG_DIR="$(mktemp -d)"
    export BRIK_LOG_DIR="$AB_LOG_DIR"
    export BRIK_RUN_ID="run-fixture-aggbus"
    unset BRIK_PLATFORM BRIK_PROJECT_NAME BRIK_COMMIT_TAG
  }
  cleanup_dirs() {
    rm -rf "$AB_LOG_DIR" "$AB_FRAG_DIR"
    unset BRIK_LOG_DIR BRIK_RUN_ID
    unset BRIK_PLATFORM BRIK_PROJECT_NAME BRIK_COMMIT_TAG
  }

  # Helper: write a fragment with explicit business fields.
  write_business_fragment() {
    local stage="$1" status="$2" rc="$3" biz_status="$4" biz_reason="${5:-}"
    mkdir -p "${AB_FRAG_DIR}/${stage}"
    jq -n \
      --arg stage "$stage" \
      --arg status "$status" \
      --argjson rc "$rc" \
      --arg biz_status "$biz_status" \
      --arg biz_reason "$biz_reason" \
      '{
        schema_version: "1.0",
        stage: $stage,
        timestamp: "2026-04-21T14:00:00+0000",
        rc: $rc,
        status: $status,
        runner: { platform: "gitlab" },
        tech: { status: $status, exit_code: ($rc | tostring) },
        business: { status: $biz_status, reason: $biz_reason }
      }' > "${AB_FRAG_DIR}/${stage}/${stage}.json"
  }

  Describe "all-success aggregate"
    Before 'setup_dirs'
    After 'cleanup_dirs'

    setup_three_success() {
      write_business_fragment "build" "success" 0 "success"
      write_business_fragment "lint"  "success" 0 "success"
      write_business_fragment "test"  "success" 0 "success"
      report.aggregate_fragments "$AB_FRAG_DIR" >/dev/null 2>&1
    }

    It "summary.business.success_count is 3"
      do_run() {
        setup_three_success
        jq -r '.summary.business.success_count' "$AB_LOG_DIR/aggregate-report.json"
      }
      When call do_run
      The output should equal "3"
    End

    It "summary.business.warning_count is 0"
      do_run() {
        setup_three_success
        jq -r '.summary.business.warning_count' "$AB_LOG_DIR/aggregate-report.json"
      }
      When call do_run
      The output should equal "0"
    End

    It "summary.business.error_count is 0"
      do_run() {
        setup_three_success
        jq -r '.summary.business.error_count' "$AB_LOG_DIR/aggregate-report.json"
      }
      When call do_run
      The output should equal "0"
    End

    It "pipeline.business.status is success"
      do_run() {
        setup_three_success
        jq -r '.pipeline.business.status' "$AB_LOG_DIR/aggregate-report.json"
      }
      When call do_run
      The output should equal "success"
    End
  End

  Describe "warning aggregate (worst-of warning)"
    Before 'setup_dirs'
    After 'cleanup_dirs'

    setup_one_warning() {
      write_business_fragment "build" "success" 0 "success"
      write_business_fragment "lint"  "success" 0 "warning" "12 findings ignored by policy"
      write_business_fragment "test"  "success" 0 "success"
      report.aggregate_fragments "$AB_FRAG_DIR" >/dev/null 2>&1
    }

    It "counts (success=2, warning=1, error=0)"
      do_run() {
        setup_one_warning
        jq -r '"\(.summary.business.success_count),\(.summary.business.warning_count),\(.summary.business.error_count)"' \
          "$AB_LOG_DIR/aggregate-report.json"
      }
      When call do_run
      The output should equal "2,1,0"
    End

    It "pipeline.business.status is warning"
      do_run() {
        setup_one_warning
        jq -r '.pipeline.business.status' "$AB_LOG_DIR/aggregate-report.json"
      }
      When call do_run
      The output should equal "warning"
    End
  End

  Describe "error aggregate (worst-of error)"
    Before 'setup_dirs'
    After 'cleanup_dirs'

    setup_one_error() {
      write_business_fragment "build" "success" 0 "success"
      write_business_fragment "lint"  "success" 0 "warning" "ignored"
      write_business_fragment "test"  "failed"  1 "error" "failed in release context (failure)"
      report.aggregate_fragments "$AB_FRAG_DIR" >/dev/null 2>&1
    }

    It "counts (success=1, warning=1, error=1)"
      do_run() {
        setup_one_error
        jq -r '"\(.summary.business.success_count),\(.summary.business.warning_count),\(.summary.business.error_count)"' \
          "$AB_LOG_DIR/aggregate-report.json"
      }
      When call do_run
      The output should equal "1,1,1"
    End

    It "pipeline.business.status is error"
      do_run() {
        setup_one_error
        jq -r '.pipeline.business.status' "$AB_LOG_DIR/aggregate-report.json"
      }
      When call do_run
      The output should equal "error"
    End
  End

  Describe "rendering surface"
    Before 'setup_dirs'
    After 'cleanup_dirs'

    It "aggregate-report.md contains a Business outcome section"
      do_run() {
        write_business_fragment "build" "success" 0 "success"
        write_business_fragment "lint"  "success" 0 "warning" "ignored"
        report.aggregate_fragments "$AB_FRAG_DIR" >/dev/null 2>&1
        cat "$AB_LOG_DIR/aggregate-report.md"
      }
      When call do_run
      The output should include "Business outcome"
    End
  End
End
