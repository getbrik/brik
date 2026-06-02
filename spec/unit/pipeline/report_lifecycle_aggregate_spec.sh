#shellcheck shell=bash
# Integration contract: report.aggregate_fragments stamps stages[].lifecycle
# and synthesizes entries for planned-run stages that never produced a
# fragment (blocked by an upstream failure).
#
# Scenario mirrors the node-full-cve report (#3961): build + the parallel
# verify quartet ran, scan failed on a CVE, and the downstream stages
# (package, container-scan, promote, deploy) never started -> no fragment.
# The aggregate must classify them not_run, not "running", while the quartet
# peers stay success (a sibling failure does not block a peer), and notify
# (the in-flight aggregating stage) is running.

Describe "report.aggregate_fragments lifecycle stamping"
  Include "$BRIK_PIPELINE_LIB/report.sh"

  AGGREGATE_SCHEMA="${BRIK_HOME}/schemas/report/v1.1/aggregate.schema.json"
  jv_missing() { ! command -v jv >/dev/null 2>&1; }

  write_fragment_file() {
    local stage="$1" status="$2" rc="${3:-0}"
    mkdir -p "${FRAG_DIR}/${stage}"
    local biz_status biz_reason tech_kind
    case "$status" in
        success) biz_status="success"; biz_reason=""; tech_kind="ok" ;;
        failed)  biz_status="error";   biz_reason="failed (failure)"; tech_kind="check-failed" ;;
        *)       biz_status="success"; biz_reason=""; tech_kind="ok" ;;
    esac
    jq -n --arg stage "$stage" --arg status "$status" --argjson rc "$rc" \
          --arg biz_status "$biz_status" --arg biz_reason "$biz_reason" --arg tech_kind "$tech_kind" '{
        schema_version: "1.1", stage: $stage, timestamp: "2026-06-02T14:00:00+0000",
        rc: $rc, status: $status, runner: { platform: "gitlab" },
        tech: { kind: $tech_kind, status: $status },
        business: { status: $biz_status, reason: $biz_reason }
      }' > "${FRAG_DIR}/${stage}/${stage}.json"
  }

  write_plan_all_run() {
    local ids='["init","release","build","lint","sast","scan","test","package","container-scan","promote","deploy","notify"]'
    jq -n --argjson ids "$ids" \
      '{ schema_version: "v1", stages: ($ids | map({ id: ., decision: "run", reason: "" })) }' \
      > "${AGG_LOG_DIR}/plan.json"
  }

  setup_dirs() {
    AGG_LOG_DIR="$(mktemp -d)"
    FRAG_DIR="$(mktemp -d)"
    export BRIK_LOG_DIR="$AGG_LOG_DIR"
    export BRIK_RUN_ID="run-lifecycle-99"
    export BRIK_STAGE_NAME="notify"
    unset BRIK_PLATFORM BRIK_PROJECT_NAME
  }
  cleanup_dirs() {
    rm -rf "$AGG_LOG_DIR" "$FRAG_DIR"
    unset BRIK_LOG_DIR BRIK_RUN_ID BRIK_STAGE_NAME
  }

  Describe "scan failed, downstream stages never ran"
    Before 'setup_dirs'
    After 'cleanup_dirs'

    build_scenario() {
      write_fragment_file init    success
      write_fragment_file release success
      write_fragment_file build   success
      write_fragment_file lint    success
      write_fragment_file sast    success
      write_fragment_file scan    failed 10
      write_fragment_file test    success
      write_plan_all_run
      report.aggregate_fragments "$FRAG_DIR" >/dev/null 2>&1
    }

    lc() { jq -r --arg s "$1" '.stages[] | select(.stage==$s) | .lifecycle' "${AGG_LOG_DIR}/aggregate-report.json"; }

    It "marks the failed scan stage as failed"
      build_scenario
      When call lc scan
      The output should equal "failed"
    End

    It "keeps parallel quartet peers (lint/sast/test) as success, not not_run"
      build_scenario
      check_peers() { printf '%s|%s|%s\n' "$(lc lint)" "$(lc sast)" "$(lc test)"; }
      When call check_peers
      The output should equal "success|success|success"
    End

    It "synthesizes package as not_run (blocked by the upstream scan failure)"
      build_scenario
      When call lc package
      The output should equal "not_run"
    End

    It "synthesizes the deeper downstream stages as not_run"
      build_scenario
      check_down() { printf '%s|%s|%s\n' "$(lc container-scan)" "$(lc promote)" "$(lc deploy)"; }
      When call check_down
      The output should equal "not_run|not_run|not_run"
    End

    It "leaves the in-flight stage absent from stages[] (preserves the renderer RUNNING detection)"
      build_scenario
      notify_present() { jq -r 'any(.stages[]; .stage=="notify") | tostring' "${AGG_LOG_DIR}/aggregate-report.json"; }
      When call notify_present
      The output should equal "false"
    End

    It "stamps a lifecycle_reason on the upstream-blocked package stage"
      build_scenario
      reason() { jq -r '.stages[] | select(.stage=="package") | .lifecycle_reason' "${AGG_LOG_DIR}/aggregate-report.json"; }
      When call reason
      The output should equal "blocked by upstream failure"
    End

    It "keeps the aggregate valid against the v1.1 schema after synthesis"
      Skip if "jv not installed" jv_missing
      build_scenario
      validate() { jv --map "https://brik.dev/schemas/=${BRIK_HOME}/schemas/" "$AGGREGATE_SCHEMA" "${AGG_LOG_DIR}/aggregate-report.json" >/dev/null 2>&1; }
      When call validate
      The status should be success
    End
  End

  Describe "edge cases"
    Before 'setup_dirs'
    After 'cleanup_dirs'

    lc() { jq -r --arg s "$1" '.stages[] | select(.stage==$s) | .lifecycle' "${AGG_LOG_DIR}/aggregate-report.json"; }

    It "stamps recorded stages and synthesizes nothing when no plan.json exists"
      no_plan() {
        write_fragment_file build success
        write_fragment_file test  success
        report.aggregate_fragments "$FRAG_DIR" >/dev/null 2>&1
        printf '%s|%s|%s\n' "$(lc build)" "$(lc test)" \
          "$(jq '.stages | length' "${AGG_LOG_DIR}/aggregate-report.json")"
      }
      When call no_plan
      The output should equal "success|success|2"
    End

    It "stamps a recorded stage that is absent from the plan"
      partial_plan() {
        write_fragment_file build success
        write_fragment_file test  success
        # plan lists build only; test is recorded but not planned.
        jq -n '{ schema_version: "v1", stages: [ { id: "build", decision: "run", reason: "" } ] }' \
          > "${AGG_LOG_DIR}/plan.json"
        report.aggregate_fragments "$FRAG_DIR" >/dev/null 2>&1
        lc test
      }
      When call partial_plan
      The output should equal "success"
    End

    It "is idempotent: re-stamping keeps not_run instead of degrading to skipped"
      idempotent() {
        write_fragment_file build success
        write_fragment_file scan  failed 10
        write_plan_all_run
        report.aggregate_fragments "$FRAG_DIR" >/dev/null 2>&1
        # Re-stamp the already-stamped aggregate directly.
        _report._stamp_lifecycle "${AGG_LOG_DIR}/aggregate-report.json"
        lc package
      }
      When call idempotent
      The output should equal "not_run"
    End

    It "keeps summary.stages.total consistent with stages[] after synthesis"
      summary_consistent() {
        write_fragment_file build success
        write_fragment_file scan  failed 10
        write_plan_all_run
        report.aggregate_fragments "$FRAG_DIR" >/dev/null 2>&1
        jq -r 'if .summary.stages.total == (.stages | length) then "consistent" else "DESYNC" end' \
          "${AGG_LOG_DIR}/aggregate-report.json"
      }
      When call summary_consistent
      The output should equal "consistent"
    End
  End
End
