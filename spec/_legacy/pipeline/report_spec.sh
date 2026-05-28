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

    It "creates aggregate-report.json in BRIK_LOG_DIR"
      When call report.init
      The status should be success
      The file "$REPORT_LOG_DIR/aggregate-report.json" should be exist
    End

    It "records pipeline_id from BRIK_RUN_ID"
      check_pipeline_id() {
        report.init || return 1
        jq -r '.pipeline_id' "$REPORT_LOG_DIR/aggregate-report.json"
      }
      When call check_pipeline_id
      The output should equal "run-fixture-42"
    End

    It "records started_at as an ISO-8601 timestamp"
      check_started_at() {
        report.init || return 1
        jq -r '.started_at' "$REPORT_LOG_DIR/aggregate-report.json"
      }
      When call check_started_at
      The output should match pattern '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]*'
    End

    It "initializes stages as an empty array"
      check_stages_empty() {
        report.init || return 1
        jq '.stages | length' "$REPORT_LOG_DIR/aggregate-report.json"
      }
      When call check_stages_empty
      The output should equal "0"
    End

    It "overwrites any previous report on re-init"
      reinit_sequence() {
        report.init || return 1
        report.record "build" "tech" "exit_code" "0" || return 1
        report.init || return 1
        jq '.stages | length' "$REPORT_LOG_DIR/aggregate-report.json"
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
        jq -r '.stages[0].stage' "$REPORT_LOG_DIR/aggregate-report.json"
      }
      When call record_and_read
      The output should equal "build"
    End

    It "records a tech key under stages[].tech"
      record_tech() {
        report.init || return 1
        report.record "build" "tech" "exit_code" "0" || return 1
        jq -r '.stages[0].tech.exit_code' "$REPORT_LOG_DIR/aggregate-report.json"
      }
      When call record_tech
      The output should equal "0"
    End

    It "records a business key under stages[].business"
      record_business() {
        report.init || return 1
        report.record "package" "business" "image_full_name" "ghcr.io/org/app:1.2.0" || return 1
        jq -r '.stages[0].business.image_full_name' "$REPORT_LOG_DIR/aggregate-report.json"
      }
      When call record_business
      The output should equal "ghcr.io/org/app:1.2.0"
    End

    It "preserves multiple keys in the same category for the same stage"
      record_multi_keys() {
        report.init || return 1
        report.record "build" "tech" "exit_code" "0" || return 1
        report.record "build" "tech" "duration_ms" "1234" || return 1
        jq -r '.stages[0].tech | "\(.exit_code)|\(.duration_ms)"' "$REPORT_LOG_DIR/aggregate-report.json"
      }
      When call record_multi_keys
      The output should equal "0|1234"
    End

    It "upserts the same (stage, category, key)"
      upsert_same_key() {
        report.init || return 1
        report.record "build" "tech" "exit_code" "0" || return 1
        report.record "build" "tech" "exit_code" "1" || return 1
        jq -r '.stages[0].tech.exit_code' "$REPORT_LOG_DIR/aggregate-report.json"
      }
      When call upsert_same_key
      The output should equal "1"
    End

    It "keeps a single stage entry across multiple records for that stage"
      multi_record_single_stage() {
        report.init || return 1
        report.record "build" "tech" "exit_code" "0" || return 1
        report.record "build" "business" "image_full_name" "ghcr.io/org/app:1.0.0" || return 1
        jq '.stages | length' "$REPORT_LOG_DIR/aggregate-report.json"
      }
      When call multi_record_single_stage
      The output should equal "1"
    End

    It "creates separate entries for different stages in insertion order"
      two_stages_order() {
        report.init || return 1
        report.record "build" "tech" "exit_code" "0" || return 1
        report.record "test" "tech" "exit_code" "0" || return 1
        jq -r '.stages | map(.stage) | join(",")' "$REPORT_LOG_DIR/aggregate-report.json"
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
        jq -r '.stages[0].business.note' "$REPORT_LOG_DIR/aggregate-report.json"
      }
      When call record_ws_value
      The output should equal "hello world with spaces"
    End
  End

  # ---------------------------------------------------------------------------
  # report.record_object - record a JSON object/array under tech|business
  #
  # Companion to report.record for nested structures (commit, changelog, tag,
  # ...). Stores via jq --argjson so nesting is preserved instead of being
  # collapsed into a JSON-encoded string.
  # ---------------------------------------------------------------------------
  Describe "report.record_object"
    Before 'setup_report_dir'
    After 'cleanup_report_dir'

    It "records a nested object preserving its structure"
      record_object_nested() {
        report.init || return 1
        report.record_object "init" "business" "commit" '{"sha":"abc","short_sha":"abc12345"}' || return 1
        jq -r '.stages[0].business.commit.sha' "$REPORT_LOG_DIR/aggregate-report.json"
      }
      When call record_object_nested
      The output should equal "abc"
    End

    It "preserves all keys of the nested object"
      record_object_keys() {
        report.init || return 1
        report.record_object "init" "business" "commit" '{"sha":"abc","ref":"main","tag":null}' || return 1
        jq -c '.stages[0].business.commit | keys' "$REPORT_LOG_DIR/aggregate-report.json"
      }
      When call record_object_keys
      The output should equal '["ref","sha","tag"]'
    End

    It "records an array value"
      record_object_array() {
        report.init || return 1
        report.record_object "test" "business" "flaky" '["foo","bar"]' || return 1
        jq -c '.stages[0].business.flaky' "$REPORT_LOG_DIR/aggregate-report.json"
      }
      When call record_object_array
      The output should equal '["foo","bar"]'
    End

    It "records a JSON boolean"
      record_object_bool() {
        report.init || return 1
        report.record_object "init" "tech" "config_valid" 'true' || return 1
        jq -c '.stages[0].tech.config_valid' "$REPORT_LOG_DIR/aggregate-report.json"
      }
      When call record_object_bool
      The output should equal "true"
    End

    It "coexists with report.record on the same stage"
      record_mixed() {
        report.init || return 1
        report.record "init" "business" "project_name" "myapp" || return 1
        report.record_object "init" "business" "commit" '{"sha":"abc"}' || return 1
        jq -c '.stages[0].business' "$REPORT_LOG_DIR/aggregate-report.json"
      }
      When call record_mixed
      The output should equal '{"project_name":"myapp","commit":{"sha":"abc"}}'
    End

    It "rejects malformed JSON"
      When call report.record_object "init" "business" "commit" '{not json}'
      The status should equal "$BRIK_EXIT_INVALID_INPUT"
      The error should be present
    End

    It "rejects an invalid category"
      When call report.record_object "init" "invalid" "key" '{}'
      The status should equal "$BRIK_EXIT_INVALID_INPUT"
      The error should be present
    End

    It "rejects a missing value argument"
      When call report.record_object "init" "business" "commit"
      The status should equal "$BRIK_EXIT_INVALID_INPUT"
      The error should be present
    End
  End

  # ---------------------------------------------------------------------------
  # report.record env - cross-stage env variables (chantier env-channels)
  #
  # Stages publish KEY=VALUE pairs through the new "env" category. The
  # post-stage projection hook (_stage.run._project_env) reads them from the
  # backend and appends to BRIK_PIPELINE_ENV so downstream stages see them.
  # ---------------------------------------------------------------------------
  Describe "report.record env"
    Before 'setup_report_dir'
    After 'cleanup_report_dir'

    It "accepts the env category alongside tech and business"
      record_env_key() {
        report.init || return 1
        report.record "init" "env" "BRIK_APP_VERSION" "1.2.3" || return 1
        jq -r '.stages[0].env.BRIK_APP_VERSION' "$REPORT_LOG_DIR/aggregate-report.json"
      }
      When call record_env_key
      The output should equal "1.2.3"
    End

    It "preserves the env section across multiple records on the same stage"
      record_env_multi() {
        report.init || return 1
        report.record "init" "env" "FOO" "alpha" || return 1
        report.record "init" "env" "BAR" "beta"  || return 1
        jq -c '.stages[0].env' "$REPORT_LOG_DIR/aggregate-report.json"
      }
      When call record_env_multi
      The output should equal '{"FOO":"alpha","BAR":"beta"}'
    End

    It "coexists with tech and business records on the same stage"
      record_env_mixed() {
        report.init || return 1
        report.record "init" "tech"     "status"          "success" || return 1
        report.record "init" "business" "project_name"    "myapp"   || return 1
        report.record "init" "env"      "BRIK_BUILD_STACK" "node"   || return 1
        jq -r '.stages[0] | "\(.tech.status)|\(.business.project_name)|\(.env.BRIK_BUILD_STACK)"' \
          "$REPORT_LOG_DIR/aggregate-report.json"
      }
      When call record_env_mixed
      The output should equal "success|myapp|node"
    End

    It "still rejects an unknown category"
      When call report.record "init" "runtime" "FOO" "bar"
      The status should equal "$BRIK_EXIT_INVALID_INPUT"
      The error should be present
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
      The file "$REPORT_LOG_DIR/aggregate-report.md" should be exist
      The file "$REPORT_LOG_DIR/aggregate-report.json" should be exist
    End

    It "stamps finished_at on the json"
      render_stamps_finished_at() {
        seed_report
        report.render >/dev/null
        jq -r '.finished_at' "$REPORT_LOG_DIR/aggregate-report.json"
      }
      When call render_stamps_finished_at
      The output should match pattern '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]*'
    End

    It "with --format md produces only the md file"
      render_md_only() {
        seed_report
        rm -f "$REPORT_LOG_DIR/aggregate-report.md"
        report.render --format md
      }
      When call render_md_only
      The status should be success
      The file "$REPORT_LOG_DIR/aggregate-report.md" should be exist
    End

    It "with --format json does not truncate the json"
      render_json_only_keeps_stages() {
        seed_report
        report.render --format json >/dev/null
        jq '.stages | length' "$REPORT_LOG_DIR/aggregate-report.json"
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
        cat "$REPORT_LOG_DIR/aggregate-report.md"
      }
      When call render_md_stages
      The output should include "build"
      The output should include "test"
    End

    It "includes the business section in the md"
      render_md_business() {
        seed_report
        report.render --format md >/dev/null
        cat "$REPORT_LOG_DIR/aggregate-report.md"
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

    It "rejects an empty --output value"
      When call report.render --output ""
      The status should equal 2
      The error should be present
    End

    It "rejects an unknown positional argument"
      When call report.render bogus
      The status should equal 2
      The error should be present
    End

    It "fails when report is not initialized"
      render_uninit() {
        report.render --format md
      }
      When call render_uninit
      The status should equal "$BRIK_EXIT_IO_FAILURE"
      The stderr should include "report not initialized"
    End

    It "writes json to the custom output path when --output is given with --format json"
      render_json_custom() {
        seed_report
        local out="$REPORT_LOG_DIR/custom.json"
        report.render --format json --output "$out" >/dev/null
        [[ -f "$out" ]] && jq -r '.stages | length' "$out"
      }
      When call render_json_custom
      The status should be success
      The output should equal "2"
    End
  End

  Describe "report.record error paths"
    Before 'setup_report_dir'
    After 'cleanup_report_dir'

    It "rejects wrong number of arguments"
      When call report.record "build" "tech" "key"
      The status should equal 2
      The error should be present
    End

    It "rejects invalid category"
      record_bad_cat() {
        report.init || return 2
        report.record "build" "bogus" "key" "value"
      }
      When call record_bad_cat
      The status should equal 2
      The error should be present
    End

    It "fails when report is not initialized"
      When call report.record "build" "tech" "key" "value"
      The status should equal "$BRIK_EXIT_IO_FAILURE"
      The stderr should include "report not initialized"
    End
  End

  Describe "report.has_status argument validation"
    Before 'setup_report_dir'
    After 'cleanup_report_dir'

    It "rejects empty stage argument"
      When call report.has_status ""
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

  Describe "IO error paths"
    Before 'setup_report_dir'
    After 'cleanup_report_dir'

    It "_report._require_jq returns BRIK_EXIT_MISSING_DEP when jq is absent"
      require_jq_no_path() {
        # Shadow PATH with a tempdir that has no jq.
        local empty_path
        empty_path="$(mktemp -d)"
        local orig_path="$PATH"
        export PATH="$empty_path"
        _report._require_jq
        local rc=$?
        export PATH="$orig_path"
        rm -rf "$empty_path"
        return "$rc"
      }
      When call require_jq_no_path
      The status should equal "$BRIK_EXIT_MISSING_DEP"
      The stderr should include "jq is required"
    End

    It "report.init returns BRIK_EXIT_IO_FAILURE when log dir is unwritable"
      init_bad_dir() {
        local bad_root
        bad_root="$(mktemp -d)"
        chmod 000 "$bad_root"
        export BRIK_LOG_DIR="${bad_root}/nested"
        report.init
        local rc=$?
        chmod 755 "$bad_root" 2>/dev/null
        rm -rf "$bad_root"
        return "$rc"
      }
      When call init_bad_dir
      The status should equal "$BRIK_EXIT_IO_FAILURE"
      The stderr should include "cannot create log directory"
    End

    It "report.render returns BRIK_EXIT_IO_FAILURE when md output is unwritable"
      render_bad_output() {
        report.init >/dev/null || return 2
        report.record "build" "tech" "status" "success" >/dev/null || return 2
        local bad_root
        bad_root="$(mktemp -d)"
        chmod 000 "$bad_root"
        report.render --format md --output "${bad_root}/nested/report.md"
        local rc=$?
        chmod 755 "$bad_root" 2>/dev/null
        rm -rf "$bad_root"
        return "$rc"
      }
      When call render_bad_output
      The status should equal "$BRIK_EXIT_IO_FAILURE"
      The stderr should include "cannot write md report"
    End

    It "report.render returns BRIK_EXIT_IO_FAILURE when json output destination is unwritable"
      render_bad_json() {
        report.init >/dev/null || return 2
        report.record "build" "tech" "status" "success" >/dev/null || return 2
        local bad_root
        bad_root="$(mktemp -d)"
        chmod 000 "$bad_root"
        report.render --format json --output "${bad_root}/nested/report.json"
        local rc=$?
        chmod 755 "$bad_root" 2>/dev/null
        rm -rf "$bad_root"
        return "$rc"
      }
      When call render_bad_json
      The status should equal "$BRIK_EXIT_IO_FAILURE"
      The stderr should include "cannot copy json report"
    End
  End
End
