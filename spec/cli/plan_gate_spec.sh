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
      The output should include "[SKIP] build: no changed file matched"
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

  # When an opt-in stage's flag points at a different stage
  # (container-scan opts in via --with-package), spell out the
  # dependency so users don't search for a --with-<stage_id> that
  # doesn't exist. Self-referential flags (deploy/--with-deploy etc.)
  # keep the legacy phrasing.
  Describe "opt-in-flag-missing message text"
    setup_optin_plan() {
      OPTIN_DIR="$(mktemp -d)"
      export BRIK_WORKSPACE="$OPTIN_DIR"
      export BRIK_LOG_DIR="$OPTIN_DIR/.brik-logs"
      mkdir -p "$BRIK_LOG_DIR"
      local plan_file="$BRIK_LOG_DIR/plan.json"
      cat > "$plan_file" <<'JSON'
{"schemaVersion":"v1","brikVersion":"0.6.0","context":"snapshot","mode":"safe","workspace":"/tmp","changes":{"source":"none","files":[]},"stages":[
  {"id":"deploy","decision":"skip","reason":"opt-in-flag-missing","gate":{"mode":"opt_in"},"runner_class":"deploy"},
  {"id":"package","decision":"skip","reason":"opt-in-flag-missing","gate":{"mode":"opt_in"},"runner_class":"base"},
  {"id":"container-scan","decision":"skip","reason":"opt-in-flag-missing","gate":{"mode":"opt_in"},"runner_class":"scanner"}
],"dag":{"edges":[]},"fingerprint":"0000000000000000000000000000000000000000000000000000000000000000"}
JSON
      export BRIK_PLAN_FILE="$plan_file"
    }
    cleanup_optin_plan() {
      rm -rf "$OPTIN_DIR"
      unset BRIK_PLAN_FILE BRIK_LOG_DIR BRIK_WORKSPACE
    }
    Before 'setup_optin_plan'
    After  'cleanup_optin_plan'

    It "uses legacy phrasing when the flag matches the stage id (deploy)"
      When run script "$BRIK_BIN" plan gate deploy
      The status should equal 1
      The output should include "[SKIP] deploy: the --with-deploy flag was not passed"
    End

    It "uses legacy phrasing when the flag matches the stage id (package)"
      When run script "$BRIK_BIN" plan gate package
      The status should equal 1
      The output should include "[SKIP] package: the --with-package flag was not passed"
    End

    It "names the target stage when the flag points at a dependency (container-scan)"
      When run script "$BRIK_BIN" plan gate container-scan
      The status should equal 1
      The output should include "depends on the package stage"
      The output should include "--with-package was not passed"
      The output should include "both stages activate together"
    End

    It "does NOT mislead container-scan users with a flag named after the stage"
      When run script "$BRIK_BIN" plan gate container-scan
      The status should equal 1
      The output should not include "the --with-container-scan flag"
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

    It "rejects an unknown option"
      When run script "$BRIK_BIN" plan gate --bogus
      The status should equal 2
      The stderr should include "unknown option"
    End

    It "rejects a second positional argument"
      When run script "$BRIK_BIN" plan gate init build
      The status should equal 2
      The stderr should include "unexpected argument"
    End
  End
End
