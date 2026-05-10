Describe "aggregate emitted by the runtime validates against v1.1"
  Include "$BRIK_PIPELINE_LIB/report.sh"

  AGGREGATE_V11_SCHEMA="${BRIK_HOME}/schemas/report/v1.1/aggregate.schema.json"
  jv_missing() { ! command -v jv >/dev/null 2>&1; }

  validate_aggregate_v11() {
    jv \
      --map "https://brik.dev/schemas/=${BRIK_HOME}/schemas/" \
      "$AGGREGATE_V11_SCHEMA" "$1" >/dev/null 2>&1
  }

  setup_dirs() {
    AE_LOG_DIR="$(mktemp -d)"
    AE_FRAG_DIR="$(mktemp -d)"
    export BRIK_LOG_DIR="$AE_LOG_DIR"
    export BRIK_RUN_ID="run-fixture-aggregate-emit11"
    export BRIK_PROJECT_NAME="demo"
    export BRIK_PLATFORM="local"
    unset BRIK_COMMIT_TAG
  }
  cleanup_dirs() {
    rm -rf "$AE_LOG_DIR" "$AE_FRAG_DIR"
    unset BRIK_LOG_DIR BRIK_RUN_ID BRIK_PROJECT_NAME BRIK_PLATFORM
    unset BRIK_COMMIT_TAG
  }

  Before 'setup_dirs'
  After 'cleanup_dirs'

  # Helper: write a v1.1 fragment fixture (the aggregator filters by
  # schema_version, so fixtures must already be on the new line).
  write_v11_fragment() {
    local stage="$1" status="$2" rc="$3" biz_status="$4" biz_reason="${5:-}"
    mkdir -p "${AE_FRAG_DIR}/${stage}"
    jq -n \
      --arg stage "$stage" \
      --arg status "$status" \
      --argjson rc "$rc" \
      --arg biz_status "$biz_status" \
      --arg biz_reason "$biz_reason" \
      '{
        schema_version: "1.1",
        stage: $stage,
        timestamp: "2026-05-10T10:00:00+0000",
        rc: $rc,
        status: $status,
        runner: { platform: "local" },
        tech: { status: $status, kind: (if $status == "success" then "ok" else "failure" end) },
        business: { status: $biz_status, reason: $biz_reason }
      }' > "${AE_FRAG_DIR}/${stage}/${stage}.json"
  }

  It "schema_version is 1.1 on the produced aggregate"
    do_run() {
      write_v11_fragment "build" "success" 0 "success"
      report.aggregate_fragments "$AE_FRAG_DIR" >/dev/null 2>&1
      jq -r '.schema_version' "${AE_LOG_DIR}/aggregate-report.json"
    }
    When call do_run
    The output should equal "1.1"
  End

  It "validates against v1.1 strict for a snapshot, all-success run"
    Skip if "jv not installed" jv_missing
    do_validate() {
      write_v11_fragment "build" "success" 0 "success"
      write_v11_fragment "test"  "success" 0 "success"
      report.aggregate_fragments "$AE_FRAG_DIR" >/dev/null 2>&1
      validate_aggregate_v11 "${AE_LOG_DIR}/aggregate-report.json"
    }
    When call do_validate
    The status should be success
  End

  It "validates against v1.1 strict with a warning stage"
    Skip if "jv not installed" jv_missing
    do_validate() {
      write_v11_fragment "build" "success" 0 "success"
      write_v11_fragment "lint"  "success" 0 "warning" "1 findings ignored by policy"
      report.aggregate_fragments "$AE_FRAG_DIR" >/dev/null 2>&1
      validate_aggregate_v11 "${AE_LOG_DIR}/aggregate-report.json"
    }
    When call do_validate
    The status should be success
  End

  It "validates against v1.1 strict with an error stage in release context"
    Skip if "jv not installed" jv_missing
    do_validate() {
      export BRIK_COMMIT_TAG="v9.9.9"
      write_v11_fragment "build" "failed" 1 "error" "failed in release context (failure)"
      report.aggregate_fragments "$AE_FRAG_DIR" >/dev/null 2>&1
      validate_aggregate_v11 "${AE_LOG_DIR}/aggregate-report.json"
    }
    When call do_validate
    The status should be success
  End

  It "carries no summary.warnings array"
    do_check() {
      write_v11_fragment "build" "success" 0 "success"
      report.aggregate_fragments "$AE_FRAG_DIR" >/dev/null 2>&1
      jq -r '.summary.warnings // "absent"' "${AE_LOG_DIR}/aggregate-report.json"
    }
    When call do_check
    The output should equal "absent"
  End
End
