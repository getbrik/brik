Describe "pipeline.context persistence"
  Include "$BRIK_PIPELINE_LIB/pipeline.sh"
  Include "$BRIK_PIPELINE_LIB/report.sh"

  setup_dirs() {
    CTX_LOG_DIR="$(mktemp -d)"
    CTX_FRAG_DIR="$(mktemp -d)"
    export BRIK_LOG_DIR="$CTX_LOG_DIR"
    export BRIK_WORKSPACE="$CTX_LOG_DIR"
    export BRIK_CONFIG_FILE="$CTX_LOG_DIR/brik.yml"
    : > "$BRIK_CONFIG_FILE"
    export BRIK_RUN_ID="run-context-test"
    stages.init()            { return 0; }
    stages.release()         { return 0; }
    stages.build()           { return 0; }
    stages.lint()            { return 0; }
    stages.sast()            { return 0; }
    stages.scan()            { return 0; }
    stages.test()            { return 0; }
    stages.package()         { return 0; }
    stages.container_scan()  { return 0; }
    stages.deploy()          { return 0; }
    stages.notify()          { return 0; }
  }
  cleanup_dirs() {
    rm -rf "$CTX_LOG_DIR" "$CTX_FRAG_DIR"
    unset BRIK_LOG_DIR BRIK_WORKSPACE BRIK_CONFIG_FILE BRIK_RUN_ID
    unset BRIK_COMMIT_TAG BRIK_CONTINUE_ON_ERROR BRIK_PIPELINE_SOURCE
  }

  Describe "pipeline.run (local mode)"
    Before 'setup_dirs'
    After 'cleanup_dirs'

    It "writes pipeline.context=snapshot when no tag is set"
      snapshot_recorded() {
        unset BRIK_COMMIT_TAG
        pipeline.run >/dev/null 2>&1
        jq -r '.pipeline.context' "$CTX_LOG_DIR/aggregate-report.json"
      }
      When call snapshot_recorded
      The output should equal "snapshot"
    End

    It "writes pipeline.context=release when BRIK_COMMIT_TAG is set"
      release_recorded() {
        BRIK_COMMIT_TAG="v1.0.0" pipeline.run >/dev/null 2>&1
        jq -r '.pipeline.context' "$CTX_LOG_DIR/aggregate-report.json"
      }
      When call release_recorded
      The output should equal "release"
    End
  End

  Describe "report.aggregate_fragments (CI mode)"
    Before 'setup_dirs'
    After 'cleanup_dirs'

    write_one_fragment() {
      mkdir -p "$CTX_FRAG_DIR/build"
      jq -n '{
        schema_version: "1.0",
        stage: "build",
        timestamp: "2026-04-21T14:00:00+0000",
        rc: 0,
        status: "success",
        runner: { platform: "gitlab" }
      }' > "$CTX_FRAG_DIR/build/build.json"
    }

    It "stamps pipeline.context=snapshot when no tag is set"
      ci_snapshot() {
        unset BRIK_COMMIT_TAG
        write_one_fragment
        report.aggregate_fragments "$CTX_FRAG_DIR" >/dev/null 2>&1
        jq -r '.pipeline.context' "$CTX_LOG_DIR/aggregate-report.json"
      }
      When call ci_snapshot
      The output should equal "snapshot"
    End

    It "stamps pipeline.context=release when BRIK_COMMIT_TAG is set"
      ci_release() {
        export BRIK_COMMIT_TAG="v2.0.0"
        write_one_fragment
        report.aggregate_fragments "$CTX_FRAG_DIR" >/dev/null 2>&1
        jq -r '.pipeline.context' "$CTX_LOG_DIR/aggregate-report.json"
      }
      When call ci_release
      The output should equal "release"
    End
  End

  # pipeline.pipeline_source records the trigger provenance surfaced by the
  # platform wrapper (BRIK_PIPELINE_SOURCE). It is NOT derivable from
  # pipeline.context: a branch push and a merge/pull request both yield
  # context=snapshot, yet differ by source (push vs merge_request_event).
  # Recording it makes the trigger an auditable business outcome that E2E
  # parity assertions can read from the report instead of job colors.
  Describe "pipeline.pipeline_source persistence"
    Before 'setup_dirs'
    After 'cleanup_dirs'

    It "records pipeline.pipeline_source=merge_request_event for an MR build"
      mr_source_recorded() {
        export BRIK_PIPELINE_SOURCE="merge_request_event"
        pipeline.run >/dev/null 2>&1
        jq -r '.pipeline.pipeline_source' "$CTX_LOG_DIR/aggregate-report.json"
      }
      When call mr_source_recorded
      The output should equal "merge_request_event"
    End

    It "records pipeline.pipeline_source=push for a branch/tag push build"
      push_source_recorded() {
        export BRIK_PIPELINE_SOURCE="push"
        pipeline.run >/dev/null 2>&1
        jq -r '.pipeline.pipeline_source' "$CTX_LOG_DIR/aggregate-report.json"
      }
      When call push_source_recorded
      The output should equal "push"
    End

    It "omits pipeline.pipeline_source when BRIK_PIPELINE_SOURCE is unset"
      # Local runs without a platform wrapper carry no trigger source; the
      # field must be absent (optional in the schema) rather than empty.
      absent_when_unset() {
        unset BRIK_PIPELINE_SOURCE
        pipeline.run >/dev/null 2>&1
        jq -r '.pipeline | has("pipeline_source")' "$CTX_LOG_DIR/aggregate-report.json"
      }
      When call absent_when_unset
      The output should equal "false"
    End
  End
End
