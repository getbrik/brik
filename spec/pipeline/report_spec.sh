Describe "report.sh"
  Include "$BRIK_PIPELINE_LIB/report.sh"

  setup_report_dir() {
    REPORT_LOG_DIR="$(mktemp -d)"
    export BRIK_LOG_DIR="$REPORT_LOG_DIR"
    export BRIK_RUN_ID="run-fixture-42"
  }
  cleanup_report_dir() {
    rm -rf "$REPORT_LOG_DIR"
    unset BRIK_RUN_ID
  }

  Describe "report.init"
    Before 'setup_report_dir'
    After 'cleanup_report_dir'

    It "creates pipeline-report.json in BRIK_LOG_DIR"
      When call report.init
      The status should be success
      The file "$REPORT_LOG_DIR/pipeline-report.json" should be exist
    End

    It "records pipeline_id from BRIK_RUN_ID"
      check_pipeline_id() {
        report.init || return 1
        jq -r '.pipeline_id' "$REPORT_LOG_DIR/pipeline-report.json"
      }
      When call check_pipeline_id
      The output should equal "run-fixture-42"
    End

    It "records started_at as an ISO-8601 timestamp"
      check_started_at() {
        report.init || return 1
        jq -r '.started_at' "$REPORT_LOG_DIR/pipeline-report.json"
      }
      When call check_started_at
      The output should match pattern '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]*'
    End

    It "initializes stages as an empty array"
      check_stages_empty() {
        report.init || return 1
        jq '.stages | length' "$REPORT_LOG_DIR/pipeline-report.json"
      }
      When call check_stages_empty
      The output should equal "0"
    End

    It "overwrites any previous report on re-init"
      reinit_sequence() {
        report.init || return 1
        report.record "build" "tech" "exit_code" "0" || return 1
        report.init || return 1
        jq '.stages | length' "$REPORT_LOG_DIR/pipeline-report.json"
      }
      When call reinit_sequence
      The output should equal "0"
    End
  End

  Describe "report.record"
    Before 'setup_report_dir'
    After 'cleanup_report_dir'

    It "creates a new stage entry on first record"
      record_and_read() {
        report.init || return 1
        report.record "build" "tech" "duration_ms" "1234" || return 1
        jq -r '.stages[0].name' "$REPORT_LOG_DIR/pipeline-report.json"
      }
      When call record_and_read
      The output should equal "build"
    End

    It "records a tech key under stages[].tech"
      record_tech() {
        report.init || return 1
        report.record "build" "tech" "exit_code" "0" || return 1
        jq -r '.stages[0].tech.exit_code' "$REPORT_LOG_DIR/pipeline-report.json"
      }
      When call record_tech
      The output should equal "0"
    End

    It "records a business key under stages[].business"
      record_business() {
        report.init || return 1
        report.record "package" "business" "image_full_name" "ghcr.io/org/app:1.2.0" || return 1
        jq -r '.stages[0].business.image_full_name' "$REPORT_LOG_DIR/pipeline-report.json"
      }
      When call record_business
      The output should equal "ghcr.io/org/app:1.2.0"
    End

    It "preserves multiple keys in the same category for the same stage"
      record_multi_keys() {
        report.init || return 1
        report.record "build" "tech" "exit_code" "0" || return 1
        report.record "build" "tech" "duration_ms" "1234" || return 1
        jq -r '.stages[0].tech | "\(.exit_code)|\(.duration_ms)"' "$REPORT_LOG_DIR/pipeline-report.json"
      }
      When call record_multi_keys
      The output should equal "0|1234"
    End

    It "upserts the same (stage, category, key)"
      upsert_same_key() {
        report.init || return 1
        report.record "build" "tech" "exit_code" "0" || return 1
        report.record "build" "tech" "exit_code" "1" || return 1
        jq -r '.stages[0].tech.exit_code' "$REPORT_LOG_DIR/pipeline-report.json"
      }
      When call upsert_same_key
      The output should equal "1"
    End

    It "keeps a single stage entry across multiple records for that stage"
      multi_record_single_stage() {
        report.init || return 1
        report.record "build" "tech" "exit_code" "0" || return 1
        report.record "build" "business" "image_full_name" "ghcr.io/org/app:1.0.0" || return 1
        jq '.stages | length' "$REPORT_LOG_DIR/pipeline-report.json"
      }
      When call multi_record_single_stage
      The output should equal "1"
    End

    It "creates separate entries for different stages in insertion order"
      two_stages_order() {
        report.init || return 1
        report.record "build" "tech" "exit_code" "0" || return 1
        report.record "test" "tech" "exit_code" "0" || return 1
        jq -r '.stages | map(.name) | join(",")' "$REPORT_LOG_DIR/pipeline-report.json"
      }
      When call two_stages_order
      The output should equal "build,test"
    End

    It "rejects an invalid category"
      When call report.record "build" "invalid" "key" "value"
      The status should equal 2
      The error should be present
    End

    It "rejects a missing value argument"
      When call report.record "build" "tech" "key"
      The status should equal 2
      The error should be present
    End

    It "preserves whitespace in a value"
      record_ws_value() {
        report.init || return 1
        report.record "build" "business" "note" "hello world with spaces" || return 1
        jq -r '.stages[0].business.note' "$REPORT_LOG_DIR/pipeline-report.json"
      }
      When call record_ws_value
      The output should equal "hello world with spaces"
    End
  End

  Describe "report.render"
    Before 'setup_report_dir'
    After 'cleanup_report_dir'

    seed_report() {
      report.init
      report.record "build" "tech" "exit_code" "0"
      report.record "build" "tech" "duration_ms" "12340"
      report.record "build" "business" "image_full_name" "ghcr.io/org/app:1.2.0"
      report.record "test" "tech" "exit_code" "0"
    }

    It "produces both md and json by default"
      render_default() {
        seed_report
        report.render
      }
      When call render_default
      The status should be success
      The file "$REPORT_LOG_DIR/pipeline-report.md" should be exist
      The file "$REPORT_LOG_DIR/pipeline-report.json" should be exist
    End

    It "stamps finished_at on the json"
      render_stamps_finished_at() {
        seed_report
        report.render >/dev/null
        jq -r '.finished_at' "$REPORT_LOG_DIR/pipeline-report.json"
      }
      When call render_stamps_finished_at
      The output should match pattern '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]*'
    End

    It "with --format md produces only the md file"
      render_md_only() {
        seed_report
        rm -f "$REPORT_LOG_DIR/pipeline-report.md"
        report.render --format md
      }
      When call render_md_only
      The status should be success
      The file "$REPORT_LOG_DIR/pipeline-report.md" should be exist
    End

    It "with --format json does not truncate the json"
      render_json_only_keeps_stages() {
        seed_report
        report.render --format json >/dev/null
        jq '.stages | length' "$REPORT_LOG_DIR/pipeline-report.json"
      }
      When call render_json_only_keeps_stages
      The output should equal "2"
    End

    It "with --output writes to the custom path"
      render_custom_output() {
        local out
        out="$REPORT_LOG_DIR/custom.md"
        seed_report
        report.render --format md --output "$out" >/dev/null
        [[ -f "$out" ]]
      }
      When call render_custom_output
      The status should be success
    End

    It "includes every stage name in the md table"
      render_md_stages() {
        seed_report
        report.render --format md >/dev/null
        cat "$REPORT_LOG_DIR/pipeline-report.md"
      }
      When call render_md_stages
      The output should include "build"
      The output should include "test"
    End

    It "includes the business section in the md"
      render_md_business() {
        seed_report
        report.render --format md >/dev/null
        cat "$REPORT_LOG_DIR/pipeline-report.md"
      }
      When call render_md_business
      The output should include "image_full_name"
      The output should include "ghcr.io/org/app:1.2.0"
    End

    It "rejects an unknown --format value"
      When call report.render --format xml
      The status should equal 2
      The error should be present
    End
  End

  Describe "report.has_status"
    Before 'setup_report_dir'
    After 'cleanup_report_dir'

    It "returns 1 when no report has been initialized"
      When call report.has_status "build"
      The status should equal 1
    End

    It "returns 1 when the stage has no entry in the report"
      no_entry_for_stage() {
        report.init || return 2
        report.has_status "build"
      }
      When call no_entry_for_stage
      The status should equal 1
    End

    It "returns 1 when the stage entry has no tech.status"
      stage_without_status() {
        report.init || return 2
        report.record "build" "tech" "duration_ms" "1234" || return 2
        report.has_status "build"
      }
      When call stage_without_status
      The status should equal 1
    End

    It "returns 0 when tech.status is success"
      status_success() {
        report.init || return 2
        report.record "build" "tech" "status" "success" || return 2
        report.has_status "build"
      }
      When call status_success
      The status should be success
    End

    It "returns 0 when tech.status is failed"
      status_failed() {
        report.init || return 2
        report.record "build" "tech" "status" "failed" || return 2
        report.has_status "build"
      }
      When call status_failed
      The status should be success
    End

    It "returns 0 when tech.status is skipped"
      status_skipped() {
        report.init || return 2
        report.record "lint" "tech" "status" "skipped" || return 2
        report.has_status "lint"
      }
      When call status_skipped
      The status should be success
    End

    It "rejects a missing stage argument"
      When call report.has_status
      The status should equal 2
      The error should be present
    End
  End
End
