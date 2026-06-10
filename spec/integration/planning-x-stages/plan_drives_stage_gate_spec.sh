# L2 edge: Planning -> Stages (graph edge #10)
#
# The plan.json produced by the planning notion must actually drive each
# stage's SKIP/EXECUTE decision: `brik plan gate <stage>` returns 0 when the
# plan says run and 1 when it says skip. This pins the full chain
# (plan generation -> plan.json -> gate consumption) end to end, which the
# per-function unit specs do not assert as one integrated flow.

Describe "L2 planning -> stages: plan.json drives the stage gate"
  Include "$BRIK_HOME/spec/support/mock_helper.sh"

  setup_ws() {
    mock.infra.setup
    WS="$(mktemp -d)"
    export BRIK_WORKSPACE="$WS"
    export BRIK_LOG_DIR="$WS/.brik-logs"
    mkdir -p "$BRIK_LOG_DIR"
    (
      cd "$WS" || exit 1
      git init -q -b main
      git config user.email "test@brik.dev"
      git config user.name "test"
      printf '{"name":"pg","version":"1.0.0"}\n' > package.json
      printf 'project:\n  name: pg\n  stack: node\n' > brik.yml
      git add -A
      git commit -q -m "baseline"
    )
    # Generate the real plan at the default location the gate reads.
    "$BRIK_BIN" plan --workspace "$WS" --mode safe \
      --out "$BRIK_LOG_DIR/plan.json" >/dev/null 2>&1
  }
  cleanup_ws() {
    mock.infra.teardown
    rm -rf "$WS"
    unset BRIK_WORKSPACE BRIK_LOG_DIR
  }
  Before 'setup_ws'
  After 'cleanup_ws'

  # In safe/snapshot context: blocking stages run (exit 0, no output);
  # opt-in stages without their flag skip (exit 1, [SKIP] message).
  Describe "run decisions gate open"
    Parameters
      "init"
      "build"
      "lint"
    End

    It "gates $1 with exit 0"
      When run script "$BRIK_BIN" plan gate "$1"
      The status should equal 0
    End
  End

  Describe "skip decisions gate closed"
    Parameters
      "deploy"
      "package"
    End

    It "gates $1 with exit 1 and a [SKIP] message"
      When run script "$BRIK_BIN" plan gate "$1"
      The status should equal 1
      The output should include "[SKIP]"
    End
  End

  Describe "planner mode validation"
    It "rejects an unimplemented planner mode"
      When run script "$BRIK_BIN" plan --workspace "$WS" --mode aggressive
      The status should equal 2
      The error should include "aggressive"
    End
  End
End
