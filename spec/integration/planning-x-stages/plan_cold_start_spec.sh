Describe "brik plan cold-start safety net"
  # The chantier promise: when `changes.source=none` (no diff basis
  # available -- fresh clone, brand-new branch with no upstream, or a
  # workspace that isn't a git repo at all), the planner must mark
  # every BLOCKING stage as run. Skipping critical verification on a
  # cold start would be a silent loss of safety.
  #
  # This is asserted at the unit level by spec/planning/plan_spec.sh
  # (plan.decide returns reason=no-diff). This spec covers the CLI
  # boundary: `brik plan --mode balanced` against a workspace with no
  # git history must still produce a plan where every blocking stage
  # has decision=run.

  Include "$BRIK_HOME/spec/support/mock_helper.sh"

  setup_cold() {
    mock.infra.setup
    COLD_DIR="$(mktemp -d)"
    # Intentionally no `git init` here -- the planner must survive a
    # workspace that isn't a git repo at all (e.g. an archive extract).
    : > "$COLD_DIR/dummy.txt"
    # Clear every CI env so the changes.sh resolver falls through to
    # the local branch, which doesn't exist -> source=none.
    unset CI_COMMIT_SHA CI_COMMIT_BEFORE_SHA CI_MERGE_REQUEST_DIFF_BASE_SHA
    unset GIT_COMMIT GIT_PREVIOUS_COMMIT GIT_PREVIOUS_SUCCESSFUL_COMMIT
    unset BRIK_CHANGES_FROM BRIK_CHANGES_TO
  }
  cleanup_cold() {
    mock.infra.teardown
    rm -rf "$COLD_DIR"
  }
  Before 'setup_cold'
  After 'cleanup_cold'

  Describe "no git history, balanced mode"
    It "marks changes.source as none"
      "$BRIK_BIN" plan --workspace "$COLD_DIR" --mode balanced \
        --out "$COLD_DIR/plan.json" >/dev/null 2>&1
      When call jq -r '.changes.source' "$COLD_DIR/plan.json"
      The output should equal "none"
    End

    It "runs every blocking stage with reason=no-diff"
      "$BRIK_BIN" plan --workspace "$COLD_DIR" --mode balanced \
        --out "$COLD_DIR/plan.json" >/dev/null 2>&1
      blocking_decisions() {
        # Every blocking stage must be run on a cold start. We list
        # the blocking stages directly rather than reading gate.mode
        # because the registry IDs the blocking set: init/release/
        # build/lint/sast/scan/test.
        jq -r '
          .stages[]
          | select(.gate.mode == "blocking")
          | "\(.id):\(.decision):\(.reason)"
        ' "$COLD_DIR/plan.json"
      }
      When call blocking_decisions
      The output should include "init:run:no-diff"
      The output should include "build:run:no-diff"
      The output should include "lint:run:no-diff"
      The output should include "sast:run:no-diff"
      The output should include "scan:run:no-diff"
      The output should include "test:run:no-diff"
    End

    It "still skips release on snapshot context (cold start does not bypass gate.contexts)"
      "$BRIK_BIN" plan --workspace "$COLD_DIR" --mode balanced \
        --out "$COLD_DIR/plan.json" >/dev/null 2>&1
      # Release has gate.contexts=[release]; cold-start runs every
      # blocking stage applicable to the active context, but the
      # context filter still applies first.
      When call jq -r '.stages[] | select(.id == "release") | "\(.decision):\(.reason)"' \
                  "$COLD_DIR/plan.json"
      The output should equal "skip:context-mismatch"
    End
  End

  Describe "no git history, safe mode"
    It "agrees with balanced on the blocking run set"
      "$BRIK_BIN" plan --workspace "$COLD_DIR" --mode safe \
        --out "$COLD_DIR/plan.json" >/dev/null 2>&1
      # Safe mode never reads the impact filter; the run set on a
      # cold start is the same as balanced minus the no-diff reason.
      safe_blocking() {
        jq -r '
          .stages[]
          | select(.gate.mode == "blocking" and .decision == "run")
          | .id
        ' "$COLD_DIR/plan.json" | LC_ALL=C sort | tr '\n' ','
      }
      When call safe_blocking
      The output should equal "build,init,lint,notify,sast,scan,test,"
    End

    It "labels safe-mode runs as context-match (not no-diff)"
      # The reason distinguishes safe (context-match) from balanced
      # (no-diff). Both decide "run", but the audit trail differs and
      # an adapter that filters by reason must see the right code.
      "$BRIK_BIN" plan --workspace "$COLD_DIR" --mode safe \
        --out "$COLD_DIR/plan.json" >/dev/null 2>&1
      When call jq -r '.stages[] | select(.id == "lint") | .reason' \
                  "$COLD_DIR/plan.json"
      The output should equal "context-match"
    End
  End

  Describe "schema validation on cold start"
    It "still produces a v1-valid plan when changes.source=none"
      "$BRIK_BIN" plan --workspace "$COLD_DIR" --mode balanced \
        --out "$COLD_DIR/plan.json" >/dev/null 2>&1
      if ! command -v jv >/dev/null 2>&1; then
        Skip "jv not installed"
      fi
      When call jv "$BRIK_HOME/schemas/plan/v1/plan.schema.json" "$COLD_DIR/plan.json"
      The status should equal 0
      The output should include "ok"
    End
  End
End
