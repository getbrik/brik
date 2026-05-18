Describe "brik plan gate (D.5b)"

  setup_gate() {
    GATE_DIR="$(mktemp -d)"
    export BRIK_WORKSPACE="$GATE_DIR"
    export BRIK_LOG_DIR="$GATE_DIR/.brik-logs"
    mkdir -p "$BRIK_LOG_DIR"
    PLAN_FILE="$BRIK_LOG_DIR/plan.json"
    cat > "$PLAN_FILE" <<'JSON'
{"schemaVersion":"v1","brikVersion":"0.5.0","context":"snapshot","mode":"balanced","workspace":"/tmp","changes":{"source":"none","files":[]},"stages":[
  {"id":"init","decision":"run","reason":"context-match","gate":{"mode":"blocking"},"runner_class":"base"},
  {"id":"build","decision":"skip","reason":"no-impact","gate":{"mode":"blocking"},"runner_class":"stack"}
],"dag":{"edges":[]},"fingerprint":"0000000000000000000000000000000000000000000000000000000000000000"}
JSON
    export BRIK_PLAN_FILE="$PLAN_FILE"
  }
  cleanup_gate() {
    rm -rf "$GATE_DIR"
    unset BRIK_PLAN_FILE BRIK_LOG_DIR BRIK_WORKSPACE
  }
  Before 'setup_gate'
  After 'cleanup_gate'

  Describe "run decision"
    It "returns 0 when the plan decides run"
      When run script "$BRIK_BIN" plan gate init
      The status should equal 0
    End
  End

  Describe "skip decision"
    It "returns 1 when the plan decides skip"
      When run script "$BRIK_BIN" plan gate build
      The status should equal 1
      The output should include "build: skipped (reason=no-impact)"
    End

    It "writes a stage fragment with status=skipped + kind=not-applicable + reason"
      run_and_dump() {
        "$BRIK_BIN" plan gate build >/dev/null 2>&1 || true
        cat "$GATE_DIR/brik-artifacts/build/build.json"
      }
      When call run_and_dump
      The output should include '"status": "skipped"'
      The output should include '"kind": "not-applicable"'
      The output should include '"reason": "no-impact"'
    End
  End

  Describe "no plan file"
    It "defaults to run when BRIK_PLAN_FILE is unset"
      unset BRIK_PLAN_FILE
      rm -f "$PLAN_FILE"
      When run script "$BRIK_BIN" plan gate init
      The status should equal 0
    End

    It "errors with --strict when no plan file exists"
      unset BRIK_PLAN_FILE
      rm -f "$PLAN_FILE"
      When run script "$BRIK_BIN" plan gate init --strict
      The status should equal 2
      The stderr should include "plan file not found"
    End
  End

  Describe "usage errors"
    It "errors when no stage id is provided"
      When run script "$BRIK_BIN" plan gate
      The status should equal 2
      The stderr should include "requires a stage id"
    End
  End
End
