Describe "brik plan (CLI surface)"
  # Covers the cli.plan.run forms not exercised by plan_gate_spec.sh:
  # default compute + --out, --explain, --validate-only, and the
  # --format rejection path.

  setup_ws() {
    PLAN_WS="$(mktemp -d)"
    ( cd "$PLAN_WS" && git init -q && git config user.email t@t \
        && git config user.name t && : > marker && git add -A \
        && git commit -q -m baseline )
  }
  cleanup_ws() {
    rm -rf "$PLAN_WS"
  }
  Before 'setup_ws'
  After 'cleanup_ws'

  Describe "default compute"
    It "writes plan.json to --out and prints the path"
      When run script "$BRIK_BIN" plan --workspace "$PLAN_WS" --mode safe \
        --out "$PLAN_WS/.brik-logs/plan.json"
      The status should equal 0
      The output should include "plan:"
      The path "$PLAN_WS/.brik-logs/plan.json" should be file
    End

    It "defaults --out to .brik-logs/plan.json under the workspace"
      When run script "$BRIK_BIN" plan --workspace "$PLAN_WS" --mode safe
      The status should equal 0
      The output should include "plan:"
      The path "$PLAN_WS/.brik-logs/plan.json" should be file
    End
  End

  Describe "--explain"
    It "prints a human-readable summary without writing a file"
      When run script "$BRIK_BIN" plan --workspace "$PLAN_WS" --mode safe --explain
      The status should equal 0
      The output should include "Brik plan"
      The output should include "Stages:"
      The output should include "init"
    End
  End

  Describe "--validate-only"
    It "computes a plan, validates it against the schema, and discards it"
      if ! command -v jv >/dev/null 2>&1 && ! command -v check-jsonschema >/dev/null 2>&1; then
        Skip "no JSON Schema validator on PATH"
      fi
      When run script "$BRIK_BIN" plan --workspace "$PLAN_WS" --mode safe --validate-only
      The status should equal 0
      The output should include "valid against schema"
      The path "$PLAN_WS/.brik-logs/plan.json" should not be exist
    End
  End

  Describe "--format rejection"
    It "rejects an unknown --format value"
      When run script "$BRIK_BIN" plan --workspace "$PLAN_WS" --format xml \
        --out "$PLAN_WS/.brik-logs/plan.json"
      The status should equal 2
      The stderr should include "not a known format"
    End
  End

  Describe "unknown option"
    It "rejects an unknown flag with a usage error"
      When run script "$BRIK_BIN" plan --workspace "$PLAN_WS" --bogus
      The status should equal 2
      The stderr should be present
    End
  End

  Describe "opt-in gate flags"
    # --with-release / --with-package / --with-deploy flip the opt-in gates
    # so the matching stages decide "run" in the plan.
    It "accepts --with-release"
      When run script "$BRIK_BIN" plan --workspace "$PLAN_WS" --mode safe \
        --with-release --explain
      The status should equal 0
      The output should include "release"
    End

    It "accepts --with-package"
      When run script "$BRIK_BIN" plan --workspace "$PLAN_WS" --mode safe \
        --with-package --explain
      The status should equal 0
      The output should include "package"
    End

    It "accepts --with-deploy"
      When run script "$BRIK_BIN" plan --workspace "$PLAN_WS" --mode safe \
        --with-deploy --explain
      The status should equal 0
      The output should include "deploy"
    End
  End

  Describe "pipeline.selection.mode from brik.yml"
    # When --mode is omitted, cli.plan.run reads pipeline.selection.mode
    # from the workspace brik.yml via config.get.
    setup_cfg() {
      printf 'version: 1\nproject:\n  name: plan-cfg\n  stack: node\npipeline:\n  selection:\n    mode: balanced\n' \
        > "$PLAN_WS/brik.yml"
    }
    Before 'setup_cfg'

    It "reads the selection mode from the project brik.yml"
      When run script "$BRIK_BIN" plan --workspace "$PLAN_WS" --explain
      The status should equal 0
      The output should include "mode"
      The output should include "balanced"
    End
  End
End
