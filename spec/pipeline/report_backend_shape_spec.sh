#shellcheck shell=bash
# Contract for the in-memory backend shape produced by report.record /
# report.record_object / report.write_fragment.
#
# Validates the Definition of Done of Lot 2 of
# docs/chantiers/20260526_pipeline-invariants-centralization.md:
#   I7 - report.* writers use .stage (not .name) as stage-identifier field
#        in the backend aggregate-report.json. write_fragment reads the same
#        .stage key to locate the entry it serializes. Eliminates the
#        "{name: 'notify', stage: null}" orphan row observed on GitLab
#        pipeline #3715 caused by the schema mismatch.
#   I10 - notify writes its own fragment (tech.status=success, kind=in-flight)
#         BEFORE invoking report.aggregate_fragments, so the aggregate
#         contains a proper notify entry instead of a "RUNNING" placeholder.

Describe "report backend shape (I7 + I10)"
  Include "$BRIK_HOME/lib/pipeline/error.sh"
  Include "$BRIK_HOME/lib/pipeline/logging.sh"
  Include "$BRIK_HOME/lib/pipeline/report.sh"

  setup_report_dir() {
    REPORT_LOG_DIR="$(mktemp -d)"
    export BRIK_LOG_DIR="$REPORT_LOG_DIR"
    export BRIK_WORKSPACE="$REPORT_LOG_DIR"
    export BRIK_RUN_ID="run-fixture-shape"
  }
  cleanup_report_dir() {
    rm -rf "$REPORT_LOG_DIR"
    unset BRIK_RUN_ID BRIK_LOG_DIR BRIK_WORKSPACE
  }

  Describe "I7 - report.record writes .stage, not .name"
    Before 'setup_report_dir'
    After 'cleanup_report_dir'

    It "appends a new stage entry keyed by .stage"
      record_and_inspect() {
        report.init || return 1
        report.record "build" "tech" "status" "success" || return 1
        jq -r '.stages[0].stage' "$REPORT_LOG_DIR/aggregate-report.json"
      }
      When call record_and_inspect
      The status should be success
      The output should equal "build"
    End

    It "does not emit a .name field on the entry"
      record_and_check() {
        report.init || return 1
        report.record "build" "tech" "status" "success" || return 1
        jq -r '.stages[0] | has("name")' "$REPORT_LOG_DIR/aggregate-report.json"
      }
      When call record_and_check
      The output should equal "false"
    End

    It "matches existing entries by .stage on subsequent records"
      single_entry_after_two_records() {
        report.init || return 1
        report.record "build" "tech" "status" "success" || return 1
        report.record "build" "tech" "exit_code" "0" || return 1
        jq -r '.stages | length' "$REPORT_LOG_DIR/aggregate-report.json"
      }
      When call single_entry_after_two_records
      The output should equal "1"
    End

    It "preserves insertion order across multiple stages"
      record_three() {
        report.init || return 1
        report.record "build" "tech" "status" "success" || return 1
        report.record "test"  "tech" "status" "failed"  || return 1
        report.record "lint"  "tech" "status" "success" || return 1
        jq -r '.stages | map(.stage) | join(",")' "$REPORT_LOG_DIR/aggregate-report.json"
      }
      When call record_three
      The output should equal "build,test,lint"
    End
  End

  Describe "I7 - report.record_object writes .stage, not .name"
    Before 'setup_report_dir'
    After 'cleanup_report_dir'

    It "appends a new stage entry keyed by .stage for nested values"
      record_obj_and_inspect() {
        report.init || return 1
        report.record_object "scan" "business" "items" '[1,2,3]' || return 1
        jq -r '.stages[0].stage' "$REPORT_LOG_DIR/aggregate-report.json"
      }
      When call record_obj_and_inspect
      The status should be success
      The output should equal "scan"
    End

    It "does not emit a .name field on nested-object entries"
      record_obj_no_name() {
        report.init || return 1
        report.record_object "scan" "business" "items" '[1,2,3]' || return 1
        jq -r '.stages[0] | has("name")' "$REPORT_LOG_DIR/aggregate-report.json"
      }
      When call record_obj_no_name
      The output should equal "false"
    End
  End

  Describe "I7 - report.write_fragment reads by .stage"
    Before 'setup_report_dir'
    After 'cleanup_report_dir'

    It "extracts the entry by matching .stage and emits a fragment with .stage"
      write_and_inspect() {
        report.init || return 1
        report.record "build" "tech" "status" "success" || return 1
        report.write_fragment "build" || return 1
        jq -r '.stage' "$REPORT_LOG_DIR/brik-artifacts/build/build.json"
      }
      When call write_and_inspect
      The status should be success
      The output should equal "build"
    End

    It "carries the recorded tech.status into the fragment"
      fragment_status() {
        report.init || return 1
        report.record "build" "tech" "status" "success" || return 1
        report.write_fragment "build" || return 1
        jq -r '.tech.status' "$REPORT_LOG_DIR/brik-artifacts/build/build.json"
      }
      When call fragment_status
      The output should equal "success"
    End
  End

  Describe "I10 - notify-ordering contract"
    # The three lines added to stages.notify (before report.aggregate_fragments)
    # must produce a notify fragment with tech.status=success and
    # tech.kind=in-flight. This test exercises that exact 3-call sequence in
    # isolation; the integration check (stages.notify end-to-end) lives in
    # the existing notify/report aggregate suites.
    Before 'setup_report_dir'
    After 'cleanup_report_dir'

    It "report.record + write_fragment for 'notify' produce stage=notify with success status"
      simulate_notify_preamble() {
        report.init || return 1
        report.record "notify" "tech" "status" "success" || return 1
        report.record "notify" "tech" "kind"   "in-flight" || return 1
        report.write_fragment "notify" || return 1
        jq -r '[.stage, .tech.status, .tech.kind] | join("|")' \
          "$REPORT_LOG_DIR/brik-artifacts/notify/notify.json"
      }
      When call simulate_notify_preamble
      The status should be success
      The output should equal "notify|success|in-flight"
    End

    It "notify fragment exists on disk after the preamble (callable by aggregate_fragments)"
      preamble_then_check_fragment() {
        report.init || return 1
        report.record "notify" "tech" "status" "success" || return 1
        report.write_fragment "notify" || return 1
        [[ -f "$REPORT_LOG_DIR/brik-artifacts/notify/notify.json" ]] && echo "found" || echo "missing"
      }
      When call preamble_then_check_fragment
      The output should equal "found"
    End
  End
End
