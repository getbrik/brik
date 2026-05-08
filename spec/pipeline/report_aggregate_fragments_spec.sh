Describe "report.aggregate_fragments"
  Include "$BRIK_PIPELINE_LIB/report.sh"

  AGGREGATE_SCHEMA="${BRIK_HOME}/schemas/report/v1/aggregate.schema.json"
  jv_missing() { ! command -v jv >/dev/null 2>&1; }

  validate_aggregate_file() {
    jv \
      --map "https://brik.dev/schemas/=${BRIK_HOME}/schemas/" \
      "$AGGREGATE_SCHEMA" "$1" >/dev/null 2>&1
  }

  # Helper: write a fragment file with the given shape into FRAG_DIR.
  # Layout: per-stage subdirectory matches the production write_fragment.
  write_fragment_file() {
    local stage="$1" status="$2" rc="$3" extra_json="${4:-{\}}"
    mkdir -p "${FRAG_DIR}/${stage}"
    local path="${FRAG_DIR}/${stage}/${stage}.json"
    jq -n \
      --arg stage "$stage" \
      --arg status "$status" \
      --argjson rc "$rc" \
      --argjson extra "$extra_json" \
      '{
        schema_version: "1.0",
        stage: $stage,
        timestamp: "2026-04-21T14:00:00+0000",
        rc: $rc,
        status: $status,
        runner: { platform: "gitlab" }
      } + $extra' > "$path"
  }

  setup_dirs() {
    AGG_LOG_DIR="$(mktemp -d)"
    FRAG_DIR="$(mktemp -d)"
    export BRIK_LOG_DIR="$AGG_LOG_DIR"
    export BRIK_RUN_ID="run-fixture-99"
    unset BRIK_PLATFORM BRIK_PROJECT_NAME CI_PIPELINE_URL BRIK_STARTED_AT
  }
  cleanup_dirs() {
    rm -rf "$AGG_LOG_DIR" "$FRAG_DIR"
    unset BRIK_LOG_DIR BRIK_RUN_ID
    unset BRIK_PLATFORM BRIK_PROJECT_NAME CI_PIPELINE_URL BRIK_STARTED_AT
  }

  # ---------------------------------------------------------------------------
  # Argument validation and prerequisites
  # ---------------------------------------------------------------------------
  Describe "argument validation"
    Before 'setup_dirs'
    After 'cleanup_dirs'

    It "rejects when no directory is given"
      no_arg() { report.aggregate_fragments; }
      When call no_arg
      The status should equal "$BRIK_EXIT_INVALID_INPUT"
      The error should include "directory"
    End

    It "rejects when too many args are given"
      too_many() { report.aggregate_fragments "$FRAG_DIR" "extra"; }
      When call too_many
      The status should equal "$BRIK_EXIT_INVALID_INPUT"
      The error should include "expects 1 argument"
    End

    It "returns BRIK_EXIT_IO_FAILURE when the directory does not exist"
      no_dir() { report.aggregate_fragments "/nonexistent/brik-artifacts"; }
      When call no_dir
      The status should equal "$BRIK_EXIT_IO_FAILURE"
      The error should include "not found"
    End

    It "returns BRIK_EXIT_MISSING_DEP when jq is not on PATH"
      no_jq() {
        local saved="$PATH"
        export PATH="/nonexistent_dir_only"
        report.aggregate_fragments "$FRAG_DIR" >/dev/null 2>&1
        local rc=$?
        export PATH="$saved"
        return "$rc"
      }
      When call no_jq
      The status should equal "$BRIK_EXIT_MISSING_DEP"
    End
  End

  # ---------------------------------------------------------------------------
  # Empty directory: produces a valid empty aggregate
  # ---------------------------------------------------------------------------
  Describe "empty fragment directory"
    Before 'setup_dirs'
    After 'cleanup_dirs'

    It "succeeds with empty stages array"
      empty_run() {
        report.aggregate_fragments "$FRAG_DIR" || return 1
        jq '.stages | length' "$AGG_LOG_DIR/aggregate-report.json"
      }
      When call empty_run
      The output should equal "0"
    End

    It "produces an aggregate with summary.stages.total = 0"
      empty_summary() {
        report.aggregate_fragments "$FRAG_DIR" || return 1
        jq '.summary.stages.total' "$AGG_LOG_DIR/aggregate-report.json"
      }
      When call empty_summary
      The output should equal "0"
    End

    It "produces an aggregate with pipeline.status = success when no failures"
      empty_status() {
        report.aggregate_fragments "$FRAG_DIR" || return 1
        jq -r '.pipeline.status' "$AGG_LOG_DIR/aggregate-report.json"
      }
      When call empty_status
      The output should equal "success"
    End

    It "validates against the aggregate schema"
      Skip if "jv not installed" jv_missing
      empty_validates() {
        report.aggregate_fragments "$FRAG_DIR" || return 1
        validate_aggregate_file "$AGG_LOG_DIR/aggregate-report.json"
      }
      When call empty_validates
      The status should be success
    End
  End

  # ---------------------------------------------------------------------------
  # Happy path: multiple fragments
  # ---------------------------------------------------------------------------
  Describe "happy path with multiple fragments"
    Before 'setup_dirs'
    After 'cleanup_dirs'

    seed_three() {
      write_fragment_file "init"  "success" 0
      write_fragment_file "build" "success" 0
      write_fragment_file "test"  "success" 0
    }

    It "stages array has one entry per fragment file"
      three_count() {
        seed_three && report.aggregate_fragments "$FRAG_DIR" || return 1
        jq '.stages | length' "$AGG_LOG_DIR/aggregate-report.json"
      }
      When call three_count
      The output should equal "3"
    End

    It "summary.stages counts all-success correctly"
      three_summary() {
        seed_three && report.aggregate_fragments "$FRAG_DIR" || return 1
        jq -c '.summary.stages' "$AGG_LOG_DIR/aggregate-report.json"
      }
      When call three_summary
      The output should equal '{"total":3,"passed":3,"failed":0,"skipped":0}'
    End

    It "pipeline.status = success when no fragment failed"
      three_status() {
        seed_three && report.aggregate_fragments "$FRAG_DIR" || return 1
        jq -r '.pipeline.status' "$AGG_LOG_DIR/aggregate-report.json"
      }
      When call three_status
      The output should equal "success"
    End

    It "validates against the aggregate schema"
      Skip if "jv not installed" jv_missing
      three_validate() {
        seed_three && report.aggregate_fragments "$FRAG_DIR" || return 1
        validate_aggregate_file "$AGG_LOG_DIR/aggregate-report.json"
      }
      When call three_validate
      The status should be success
    End
  End

  # ---------------------------------------------------------------------------
  # Mixed status: success / failed / skipped
  # ---------------------------------------------------------------------------
  Describe "mixed status"
    Before 'setup_dirs'
    After 'cleanup_dirs'

    seed_mixed() {
      write_fragment_file "init"     "success" 0
      write_fragment_file "build"    "success" 0
      write_fragment_file "test"     "failed"  1
      write_fragment_file "release"  "skipped" 0
      write_fragment_file "package"  "skipped" 0
      write_fragment_file "deploy"   "skipped" 0
    }

    It "summary.stages counts each status correctly"
      mixed_summary() {
        seed_mixed && report.aggregate_fragments "$FRAG_DIR" || return 1
        jq -c '.summary.stages' "$AGG_LOG_DIR/aggregate-report.json"
      }
      When call mixed_summary
      The output should equal '{"total":6,"passed":2,"failed":1,"skipped":3}'
    End

    It "pipeline.status = failed when at least one fragment failed"
      mixed_status() {
        seed_mixed && report.aggregate_fragments "$FRAG_DIR" || return 1
        jq -r '.pipeline.status' "$AGG_LOG_DIR/aggregate-report.json"
      }
      When call mixed_status
      The output should equal "failed"
    End

    It "validates against the aggregate schema"
      Skip if "jv not installed" jv_missing
      mixed_validate() {
        seed_mixed && report.aggregate_fragments "$FRAG_DIR" || return 1
        validate_aggregate_file "$AGG_LOG_DIR/aggregate-report.json"
      }
      When call mixed_validate
      The status should be success
    End
  End

  # ---------------------------------------------------------------------------
  # schema_version mismatch: warn-and-skip (decision 7)
  # ---------------------------------------------------------------------------
  Describe "fragment with schema_version mismatch"
    Before 'setup_dirs'
    After 'cleanup_dirs'

    seed_with_v2() {
      write_fragment_file "init"  "success" 0
      write_fragment_file "build" "success" 0
      # Future-version fragment; aggregator must skip it.
      mkdir -p "${FRAG_DIR}/test"
      jq -n \
        '{ schema_version: "2.0", stage: "test",
           timestamp: "2026-04-21T14:00:00+0000",
           rc: 0, status: "success",
           runner: { platform: "gitlab" } }' \
        > "${FRAG_DIR}/test/test.json"
    }

    It "logs a warning and skips the mismatched fragment"
      warn_and_skip() {
        seed_with_v2 && report.aggregate_fragments "$FRAG_DIR" || return 1
      }
      When call warn_and_skip
      The status should be success
      The error should include "schema_version"
    End

    It "still aggregates the valid fragments"
      count_valid_only() {
        seed_with_v2 && report.aggregate_fragments "$FRAG_DIR" 2>/dev/null || return 1
        jq '.stages | length' "$AGG_LOG_DIR/aggregate-report.json"
      }
      When call count_valid_only
      The output should equal "2"
    End

    It "still produces a schema-valid aggregate"
      Skip if "jv not installed" jv_missing
      validate_aggregate() {
        seed_with_v2 && report.aggregate_fragments "$FRAG_DIR" 2>/dev/null || return 1
        validate_aggregate_file "$AGG_LOG_DIR/aggregate-report.json"
      }
      When call validate_aggregate
      The status should be success
    End
  End

  # ---------------------------------------------------------------------------
  # Non-fragment files in the directory must be ignored
  # ---------------------------------------------------------------------------
  Describe "non-fragment files in the directory"
    Before 'setup_dirs'
    After 'cleanup_dirs'

    It "ignores aggregate-report.json itself"
      ignore_aggregate() {
        write_fragment_file "init"  "success" 0
        write_fragment_file "build" "success" 0
        # Pre-existing aggregate left over from a previous run.
        jq -n '{ schema_version: "1.0", pipeline: {}, stages: [], summary: { stages: { total:0, passed:0, failed:0, skipped:0 } } }' \
          > "${FRAG_DIR}/aggregate-report.json"
        report.aggregate_fragments "$FRAG_DIR" >/dev/null 2>&1 || return 1
        jq '.stages | length' "$AGG_LOG_DIR/aggregate-report.json"
      }
      When call ignore_aggregate
      The output should equal "2"
    End

    It "ignores files that are not valid JSON"
      ignore_garbage() {
        write_fragment_file "init"  "success" 0
        printf 'not valid json\n' > "${FRAG_DIR}/notes.txt"
        printf '{ "broken' > "${FRAG_DIR}/broken.json"
        report.aggregate_fragments "$FRAG_DIR" >/dev/null 2>&1 || return 1
        jq '.stages | length' "$AGG_LOG_DIR/aggregate-report.json"
      }
      When call ignore_garbage
      The output should equal "1"
    End

    It "ignores JSON files that lack the fragment signature"
      ignore_other_json() {
        write_fragment_file "init"  "success" 0
        jq -n '{ unrelated: "data", count: 5 }' > "${FRAG_DIR}/random.json"
        report.aggregate_fragments "$FRAG_DIR" >/dev/null 2>&1 || return 1
        jq '.stages | length' "$AGG_LOG_DIR/aggregate-report.json"
      }
      When call ignore_other_json
      The output should equal "1"
    End
  End

  # ---------------------------------------------------------------------------
  # Pipeline metadata population from environment
  # ---------------------------------------------------------------------------
  Describe "pipeline metadata"
    Before 'setup_dirs'
    After 'cleanup_dirs'

    It "uses BRIK_RUN_ID for pipeline.id"
      read_id() {
        write_fragment_file "init" "success" 0
        report.aggregate_fragments "$FRAG_DIR" >/dev/null 2>&1 || return 1
        jq -r '.pipeline.id' "$AGG_LOG_DIR/aggregate-report.json"
      }
      When call read_id
      The output should equal "run-fixture-99"
    End

    It "uses BRIK_PLATFORM for pipeline.platform"
      read_platform() {
        export BRIK_PLATFORM="jenkins"
        write_fragment_file "init" "success" 0
        report.aggregate_fragments "$FRAG_DIR" >/dev/null 2>&1 || return 1
        jq -r '.pipeline.platform' "$AGG_LOG_DIR/aggregate-report.json"
      }
      When call read_platform
      The output should equal "jenkins"
    End

    It "defaults pipeline.platform to 'local' when unset"
      read_platform() {
        write_fragment_file "init" "success" 0
        report.aggregate_fragments "$FRAG_DIR" >/dev/null 2>&1 || return 1
        jq -r '.pipeline.platform' "$AGG_LOG_DIR/aggregate-report.json"
      }
      When call read_platform
      The output should equal "local"
    End

    It "uses BRIK_PROJECT_NAME for pipeline.project"
      read_project() {
        export BRIK_PROJECT_NAME="my-app"
        write_fragment_file "init" "success" 0
        report.aggregate_fragments "$FRAG_DIR" >/dev/null 2>&1 || return 1
        jq -r '.pipeline.project' "$AGG_LOG_DIR/aggregate-report.json"
      }
      When call read_project
      The output should equal "my-app"
    End

    It "stamps pipeline.finished_at as ISO-8601"
      read_finished() {
        write_fragment_file "init" "success" 0
        report.aggregate_fragments "$FRAG_DIR" >/dev/null 2>&1 || return 1
        jq -r '.pipeline.finished_at' "$AGG_LOG_DIR/aggregate-report.json"
      }
      When call read_finished
      The output should match pattern '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]*'
    End
  End

  # ---------------------------------------------------------------------------
  # Extended pipeline metadata: url, commit.*, triggered_by
  #
  # Aggregator reads BRIK_PIPELINE_URL, BRIK_COMMIT_*, BRIK_TRIGGERED_BY and
  # surfaces them under .pipeline.{url, commit, triggered_by}. Optional fields
  # are absent when their source variable is unset (no empty-string emission).
  # ---------------------------------------------------------------------------
  Describe "extended pipeline metadata"
    extended_setup() {
      AGG_LOG_DIR="$(mktemp -d)"
      FRAG_DIR="$(mktemp -d)"
      export BRIK_LOG_DIR="$AGG_LOG_DIR"
      export BRIK_RUN_ID="run-fixture-99"
      unset BRIK_PLATFORM BRIK_PROJECT_NAME CI_PIPELINE_URL BRIK_STARTED_AT
      unset BRIK_PIPELINE_ID BRIK_PIPELINE_URL
      unset BRIK_COMMIT_SHA BRIK_COMMIT_SHORT_SHA BRIK_COMMIT_REF
      unset BRIK_COMMIT_BRANCH BRIK_COMMIT_TAG
      unset BRIK_TRIGGERED_BY
    }
    extended_cleanup() {
      rm -rf "$AGG_LOG_DIR" "$FRAG_DIR"
      unset BRIK_LOG_DIR BRIK_RUN_ID
      unset BRIK_PLATFORM BRIK_PROJECT_NAME CI_PIPELINE_URL BRIK_STARTED_AT
      unset BRIK_PIPELINE_ID BRIK_PIPELINE_URL
      unset BRIK_COMMIT_SHA BRIK_COMMIT_SHORT_SHA BRIK_COMMIT_REF
      unset BRIK_COMMIT_BRANCH BRIK_COMMIT_TAG
      unset BRIK_TRIGGERED_BY
    }
    Before 'extended_setup'
    After 'extended_cleanup'

    It "prefers BRIK_PIPELINE_ID over BRIK_RUN_ID for pipeline.id"
      read_id() {
        export BRIK_PIPELINE_ID="42"
        write_fragment_file "init" "success" 0
        report.aggregate_fragments "$FRAG_DIR" >/dev/null 2>&1 || return 1
        jq -r '.pipeline.id' "$AGG_LOG_DIR/aggregate-report.json"
      }
      When call read_id
      The output should equal "42"
    End

    It "exposes BRIK_PIPELINE_URL as pipeline.url"
      read_url() {
        export BRIK_PIPELINE_URL="https://gitlab.example.com/group/project/-/pipelines/42"
        write_fragment_file "init" "success" 0
        report.aggregate_fragments "$FRAG_DIR" >/dev/null 2>&1 || return 1
        jq -r '.pipeline.url' "$AGG_LOG_DIR/aggregate-report.json"
      }
      When call read_url
      The output should equal "https://gitlab.example.com/group/project/-/pipelines/42"
    End

    It "omits pipeline.url when BRIK_PIPELINE_URL is unset"
      read_url() {
        write_fragment_file "init" "success" 0
        report.aggregate_fragments "$FRAG_DIR" >/dev/null 2>&1 || return 1
        jq '.pipeline | has("url")' "$AGG_LOG_DIR/aggregate-report.json"
      }
      When call read_url
      The output should equal "false"
    End

    It "exposes BRIK_COMMIT_SHA under pipeline.commit.sha"
      read_sha() {
        export BRIK_COMMIT_SHA="abcdef0123456789abcdef0123456789abcdef01"
        write_fragment_file "init" "success" 0
        report.aggregate_fragments "$FRAG_DIR" >/dev/null 2>&1 || return 1
        jq -r '.pipeline.commit.sha' "$AGG_LOG_DIR/aggregate-report.json"
      }
      When call read_sha
      The output should equal "abcdef0123456789abcdef0123456789abcdef01"
    End

    It "exposes BRIK_COMMIT_SHORT_SHA under pipeline.commit.short_sha"
      read_short() {
        export BRIK_COMMIT_SHORT_SHA="abcdef01"
        write_fragment_file "init" "success" 0
        report.aggregate_fragments "$FRAG_DIR" >/dev/null 2>&1 || return 1
        jq -r '.pipeline.commit.short_sha' "$AGG_LOG_DIR/aggregate-report.json"
      }
      When call read_short
      The output should equal "abcdef01"
    End

    It "exposes BRIK_COMMIT_REF under pipeline.commit.ref"
      read_ref() {
        export BRIK_COMMIT_REF="feature/x"
        write_fragment_file "init" "success" 0
        report.aggregate_fragments "$FRAG_DIR" >/dev/null 2>&1 || return 1
        jq -r '.pipeline.commit.ref' "$AGG_LOG_DIR/aggregate-report.json"
      }
      When call read_ref
      The output should equal "feature/x"
    End

    It "exposes BRIK_COMMIT_BRANCH under pipeline.commit.branch"
      read_branch() {
        export BRIK_COMMIT_BRANCH="main"
        write_fragment_file "init" "success" 0
        report.aggregate_fragments "$FRAG_DIR" >/dev/null 2>&1 || return 1
        jq -r '.pipeline.commit.branch' "$AGG_LOG_DIR/aggregate-report.json"
      }
      When call read_branch
      The output should equal "main"
    End

    It "exposes BRIK_COMMIT_TAG under pipeline.commit.tag"
      read_tag() {
        export BRIK_COMMIT_TAG="v1.2.3"
        write_fragment_file "init" "success" 0
        report.aggregate_fragments "$FRAG_DIR" >/dev/null 2>&1 || return 1
        jq -r '.pipeline.commit.tag' "$AGG_LOG_DIR/aggregate-report.json"
      }
      When call read_tag
      The output should equal "v1.2.3"
    End

    It "omits pipeline.commit when no BRIK_COMMIT_* is set"
      read_commit() {
        write_fragment_file "init" "success" 0
        report.aggregate_fragments "$FRAG_DIR" >/dev/null 2>&1 || return 1
        jq '.pipeline | has("commit")' "$AGG_LOG_DIR/aggregate-report.json"
      }
      When call read_commit
      The output should equal "false"
    End

    It "exposes BRIK_COMMIT_AUTHOR under pipeline.commit.author"
      read_author() {
        export BRIK_COMMIT_AUTHOR="Carol Tester"
        write_fragment_file "init" "success" 0
        report.aggregate_fragments "$FRAG_DIR" >/dev/null 2>&1 || return 1
        jq -r '.pipeline.commit.author' "$AGG_LOG_DIR/aggregate-report.json"
      }
      When call read_author
      The output should equal "Carol Tester"
    End

    It "exposes BRIK_COMMIT_AUTHOR_EMAIL under pipeline.commit.author_email"
      read_author_email() {
        export BRIK_COMMIT_AUTHOR_EMAIL="carol@example.com"
        write_fragment_file "init" "success" 0
        report.aggregate_fragments "$FRAG_DIR" >/dev/null 2>&1 || return 1
        jq -r '.pipeline.commit.author_email' "$AGG_LOG_DIR/aggregate-report.json"
      }
      When call read_author_email
      The output should equal "carol@example.com"
    End

    It "exposes BRIK_COMMIT_TIMESTAMP under pipeline.commit.timestamp"
      read_timestamp() {
        export BRIK_COMMIT_TIMESTAMP="2026-05-04T09:15:30+02:00"
        write_fragment_file "init" "success" 0
        report.aggregate_fragments "$FRAG_DIR" >/dev/null 2>&1 || return 1
        jq -r '.pipeline.commit.timestamp' "$AGG_LOG_DIR/aggregate-report.json"
      }
      When call read_timestamp
      The output should equal "2026-05-04T09:15:30+02:00"
    End

    It "exposes BRIK_COMMIT_MESSAGE_SUBJECT under pipeline.commit.message_subject"
      read_subject() {
        export BRIK_COMMIT_MESSAGE_SUBJECT="fix: regression in detector"
        write_fragment_file "init" "success" 0
        report.aggregate_fragments "$FRAG_DIR" >/dev/null 2>&1 || return 1
        jq -r '.pipeline.commit.message_subject' "$AGG_LOG_DIR/aggregate-report.json"
      }
      When call read_subject
      The output should equal "fix: regression in detector"
    End

    It "omits pipeline.commit.author when BRIK_COMMIT_AUTHOR is unset"
      read_omit() {
        export BRIK_COMMIT_SHA="abc"
        unset BRIK_COMMIT_AUTHOR
        write_fragment_file "init" "success" 0
        report.aggregate_fragments "$FRAG_DIR" >/dev/null 2>&1 || return 1
        jq '.pipeline.commit | has("author")' "$AGG_LOG_DIR/aggregate-report.json"
      }
      When call read_omit
      The output should equal "false"
    End

    It "exposes BRIK_TRIGGERED_BY as pipeline.triggered_by"
      read_trigger() {
        export BRIK_TRIGGERED_BY="alice"
        write_fragment_file "init" "success" 0
        report.aggregate_fragments "$FRAG_DIR" >/dev/null 2>&1 || return 1
        jq -r '.pipeline.triggered_by' "$AGG_LOG_DIR/aggregate-report.json"
      }
      When call read_trigger
      The output should equal "alice"
    End

    It "omits pipeline.triggered_by when BRIK_TRIGGERED_BY is unset"
      read_trigger() {
        write_fragment_file "init" "success" 0
        report.aggregate_fragments "$FRAG_DIR" >/dev/null 2>&1 || return 1
        jq '.pipeline | has("triggered_by")' "$AGG_LOG_DIR/aggregate-report.json"
      }
      When call read_trigger
      The output should equal "false"
    End

    It "validates against the aggregate schema with all metadata populated"
      Skip if "jv not installed" jv_missing
      validate_full() {
        export BRIK_PIPELINE_ID="42"
        export BRIK_PIPELINE_URL="https://gitlab.example.com/p/-/pipelines/42"
        export BRIK_COMMIT_SHA="abcdef0123456789abcdef0123456789abcdef01"
        export BRIK_COMMIT_SHORT_SHA="abcdef01"
        export BRIK_COMMIT_REF="feature/x"
        export BRIK_COMMIT_BRANCH="feature/x"
        export BRIK_COMMIT_TAG="v1.2.3"
        export BRIK_TRIGGERED_BY="alice"
        write_fragment_file "init" "success" 0
        report.aggregate_fragments "$FRAG_DIR" >/dev/null 2>&1 || return 1
        validate_aggregate_file "$AGG_LOG_DIR/aggregate-report.json"
      }
      When call validate_full
      The status should be success
    End
  End

  # ---------------------------------------------------------------------------
  # Markdown rendering side-effect
  # ---------------------------------------------------------------------------
  Describe "markdown side-effect"
    Before 'setup_dirs'
    After 'cleanup_dirs'

    It "renders aggregate-report.md alongside aggregate-report.json"
      check_md() {
        write_fragment_file "init"  "success" 0
        write_fragment_file "build" "success" 0
        report.aggregate_fragments "$FRAG_DIR" >/dev/null 2>&1 || return 1
        test -f "$AGG_LOG_DIR/aggregate-report.md"
      }
      When call check_md
      The status should be success
    End

    It "Markdown uses aggregate-shape selectors (.pipeline.id, .stages[].stage), not local backend selectors"
      check_md_content() {
        write_fragment_file "init"  "success" 0
        write_fragment_file "build" "success" 0
        report.aggregate_fragments "$FRAG_DIR" >/dev/null 2>&1 || return 1
        cat "$AGG_LOG_DIR/aggregate-report.md"
      }
      When call check_md_content
      The output should include "# Pipeline Report"
      The output should include "Pipeline ID:** run-fixture-99"
      The output should include "init"
      The output should include "build"
      # Regression-guard: if a future change reverts to the local-backend
      # renderer (.pipeline_id, .stages[].name, .tech.status) the ID line
      # would resolve to "null". Assert the absence.
      The output should not include "Pipeline ID:** null"
    End
  End

  # ---------------------------------------------------------------------------
  # summary.policy projection (chantier 20260508 P1.5)
  # ---------------------------------------------------------------------------
  Describe "summary.policy projection"
    Before 'setup_dirs'
    After 'cleanup_dirs'

    It "exposes summary.policy.preset from BRIK_QUALITY_FINDINGS_POLICY"
      run_with_preset() {
        export BRIK_QUALITY_FINDINGS_POLICY="strict"
        write_fragment_file "init" "success" 0
        report.aggregate_fragments "$FRAG_DIR" >/dev/null 2>&1 || return 1
        jq -r '.summary.policy.preset' "$AGG_LOG_DIR/aggregate-report.json"
      }
      When call run_with_preset
      The output should equal "strict"
    End

    It "defaults summary.policy.preset to pragmatic when the env var is unset"
      run_default_preset() {
        unset BRIK_QUALITY_FINDINGS_POLICY
        write_fragment_file "init" "success" 0
        report.aggregate_fragments "$FRAG_DIR" >/dev/null 2>&1 || return 1
        jq -r '.summary.policy.preset' "$AGG_LOG_DIR/aggregate-report.json"
      }
      When call run_default_preset
      The output should equal "pragmatic"
    End

    It "tags summary.policy.source as brik.yml in P1 (org-policy override lands in P3)"
      run_source() {
        export BRIK_QUALITY_FINDINGS_POLICY="pragmatic"
        write_fragment_file "init" "success" 0
        report.aggregate_fragments "$FRAG_DIR" >/dev/null 2>&1 || return 1
        jq -r '.summary.policy.source' "$AGG_LOG_DIR/aggregate-report.json"
      }
      When call run_source
      The output should equal "brik.yml"
    End

    It "produces a schema-valid aggregate even with summary.policy populated"
      validate_with_policy() {
        export BRIK_QUALITY_FINDINGS_POLICY="permissive"
        write_fragment_file "init" "success" 0
        report.aggregate_fragments "$FRAG_DIR" >/dev/null 2>&1 || return 1
        validate_aggregate_file "$AGG_LOG_DIR/aggregate-report.json"
      }
      Skip if "jv not installed" jv_missing
      When call validate_with_policy
      The status should be success
    End
  End
End
