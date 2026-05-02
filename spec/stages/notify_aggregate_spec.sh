Describe "stages.notify - CI mode fragment aggregation"
  Include "$BRIK_HOME/lib/pipeline/stage.sh"
  Include "$BRIK_HOME/lib/pipeline/loader.sh"
  Include "$BRIK_HOME/lib/transverse/config.sh"
  Include "$BRIK_HOME/lib/stages/notify.sh"

  # Helper: write a fragment file with the given shape into the workspace
  # brik-artifacts/ directory.
  write_fragment_file() {
    local dir="$1" stage="$2" status="$3" rc="$4"
    mkdir -p "$dir"
    jq -n \
      --arg stage "$stage" \
      --arg status "$status" \
      --argjson rc "$rc" \
      '{
        schema_version: "1.0",
        stage: $stage,
        timestamp: "2026-04-21T14:00:00+0000",
        rc: $rc,
        status: $status,
        runner: { platform: "gitlab" }
      }' > "${dir}/${stage}.json"
  }

  setup_env() {
    NOTIFY_LOG_DIR="$(mktemp -d)"
    NOTIFY_WORKSPACE="$(mktemp -d)"
    NOTIFY_CONFIG="$(mktemp)"
    printf 'version: 1\nproject:\n  name: test-project\n  stack: node\n' > "$NOTIFY_CONFIG"
    export BRIK_CONFIG_FILE="$NOTIFY_CONFIG"
    export BRIK_LOG_DIR="$NOTIFY_LOG_DIR"
    export BRIK_WORKSPACE="$NOTIFY_WORKSPACE"
    export BRIK_PROJECT_DIR="$NOTIFY_WORKSPACE"
    export BRIK_PLATFORM="gitlab"
    export BRIK_RUN_ID="run-fixture-notify"
    config.read "$BRIK_CONFIG_FILE" >/dev/null 2>&1 || true
  }
  cleanup_env() {
    rm -f "$NOTIFY_CONFIG"
    rm -rf "$NOTIFY_LOG_DIR" "$NOTIFY_WORKSPACE"
    unset BRIK_CONFIG_FILE BRIK_LOG_DIR BRIK_WORKSPACE
    unset BRIK_PROJECT_DIR BRIK_PLATFORM BRIK_RUN_ID
    unset BRIK_NOTIFY_SLACK_CHANNEL BRIK_NOTIFY_EMAIL_TO BRIK_NOTIFY_WEBHOOK_URL
  }
  Before 'setup_env'
  After 'cleanup_env'

  # ---------------------------------------------------------------------------
  # CI mode detection: presence of valid fragment files
  # ---------------------------------------------------------------------------
  Describe "CI mode (fragments present)"
    seed_ci_fragments() {
      write_fragment_file "$NOTIFY_WORKSPACE/brik-artifacts" "init"  "success" 0
      write_fragment_file "$NOTIFY_WORKSPACE/brik-artifacts" "build" "success" 0
      write_fragment_file "$NOTIFY_WORKSPACE/brik-artifacts" "test"  "success" 0
    }

    It "calls report.aggregate_fragments when fragments are present"
      do_notify() {
        seed_ci_fragments
        stages.notify "$NOTIFY_CONFIG" >/dev/null 2>&1
        test -f "$NOTIFY_LOG_DIR/pipeline-report.json"
      }
      When call do_notify
      The status should be success
    End

    It "the aggregate has all 3 fragments in stages[]"
      do_notify_count() {
        seed_ci_fragments
        stages.notify "$NOTIFY_CONFIG" >/dev/null 2>&1
        jq '.stages | length' "$NOTIFY_LOG_DIR/pipeline-report.json"
      }
      When call do_notify_count
      The output should equal "3"
    End

    It "the aggregate is also exposed under brik-artifacts/ for CI archival"
      do_notify_artifact() {
        seed_ci_fragments
        stages.notify "$NOTIFY_CONFIG" >/dev/null 2>&1
        test -f "$NOTIFY_WORKSPACE/brik-artifacts/pipeline-report.json"
      }
      When call do_notify_artifact
      The status should be success
    End
  End

  # ---------------------------------------------------------------------------
  # Local mode: existing aggregate present, no fragments — must not re-aggregate
  # ---------------------------------------------------------------------------
  Describe "local mode (no fragments, only pre-built aggregate)"
    seed_local_aggregate() {
      mkdir -p "$NOTIFY_WORKSPACE/brik-artifacts"
      jq -n '{ schema_version: "1.0",
               pipeline: { id: "local-1", platform: "local",
                           project: "p", started_at: "2026-04-21T14:00:00+0000",
                           finished_at: "2026-04-21T14:01:00+0000",
                           status: "success" },
               stages: [],
               summary: { stages: { total:0, passed:0, failed:0, skipped:0 } } }' \
        > "$NOTIFY_LOG_DIR/pipeline-report.json"
      printf '# Pipeline Report\n' > "$NOTIFY_LOG_DIR/pipeline-report.md"
    }

    It "leaves pipeline-report.json untouched (no re-aggregation)"
      check_unchanged() {
        seed_local_aggregate
        local before
        before="$(jq -r '.pipeline.id' "$NOTIFY_LOG_DIR/pipeline-report.json")"
        stages.notify "$NOTIFY_CONFIG" >/dev/null 2>&1
        local after
        after="$(jq -r '.pipeline.id' "$NOTIFY_LOG_DIR/pipeline-report.json")"
        [[ "$before" == "local-1" && "$after" == "local-1" ]]
      }
      When call check_unchanged
      The status should be success
    End
  End

  # ---------------------------------------------------------------------------
  # Empty workspace: no brik-artifacts/ at all
  # ---------------------------------------------------------------------------
  Describe "empty workspace (no brik-artifacts)"
    It "does not create an aggregate when nothing to aggregate"
      do_notify_empty() {
        stages.notify "$NOTIFY_CONFIG" >/dev/null 2>&1
        ! test -f "$NOTIFY_LOG_DIR/pipeline-report.json"
      }
      When call do_notify_empty
      The status should be success
    End

    It "still completes successfully (notify is best-effort)"
      do_notify_empty() {
        stages.notify "$NOTIFY_CONFIG" >/dev/null 2>&1
      }
      When call do_notify_empty
      The status should be success
    End
  End

  # ---------------------------------------------------------------------------
  # Mixed status fragments: pipeline.status reflects the worst outcome
  # ---------------------------------------------------------------------------
  Describe "mixed status fragments"
    seed_failed_test() {
      write_fragment_file "$NOTIFY_WORKSPACE/brik-artifacts" "init"  "success" 0
      write_fragment_file "$NOTIFY_WORKSPACE/brik-artifacts" "test"  "failed"  1
    }

    It "produces aggregate with pipeline.status=failed when any fragment failed"
      do_notify_failed() {
        seed_failed_test
        stages.notify "$NOTIFY_CONFIG" >/dev/null 2>&1
        jq -r '.pipeline.status' "$NOTIFY_LOG_DIR/pipeline-report.json"
      }
      When call do_notify_failed
      The output should equal "failed"
    End
  End
End
