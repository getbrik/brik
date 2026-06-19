Describe "container-stage.sh (in-process)"
  # container-stage.sh is a flat top-level entrypoint (no functions): its body
  # runs at source time. The sibling shared-libs/local/spec/container_stage_spec.sh
  # exercises it via `bash "$ENTRY"` (a subprocess), which kcov cannot trace --
  # leaving the file at 0% line coverage. This spec instead drives it with
  # `When run source`, so ShellSpec evaluates the script body in the kcov-traced
  # shell while still containing its top-level `exit` statements.
  #
  # Harness: a fake BRIK_HOME provides a stub `bin/brik` (the plan-gate CLI;
  # gate rc driven by STUB_GATE_RC) and a stub local-wrapper.sh exposing
  # brik.local.setup (STUB_SETUP_RC) and brik.local.run_stage (STUB_STAGE_RC),
  # each appending to a call log so dispatch order/args are asserted.

  setup_entry() {
    FAKE_HOME="$(mktemp -d)"
    CALL_LOG="${FAKE_HOME}/calls.log"
    : > "$CALL_LOG"

    mkdir -p "${FAKE_HOME}/bin" "${FAKE_HOME}/shared-libs/local/scripts"

    cat > "${FAKE_HOME}/bin/brik" << STUB
#!/usr/bin/env bash
echo "brik \$*" >> "${CALL_LOG}"
exit "\${STUB_GATE_RC:-0}"
STUB
    chmod +x "${FAKE_HOME}/bin/brik"

    cat > "${FAKE_HOME}/shared-libs/local/scripts/local-wrapper.sh" << STUB
brik.local.setup() { echo "setup" >> "${CALL_LOG}"; return "\${STUB_SETUP_RC:-0}"; }
brik.local.run_stage() { echo "run_stage \$1" >> "${CALL_LOG}"; return "\${STUB_STAGE_RC:-0}"; }
STUB

    # The real script under test, sourced from the canonical repo path so kcov
    # instruments it; its BRIK_HOME-relative lookups resolve to the stubs.
    export BRIK_HOME="$FAKE_HOME"
    TARGET="${SHELLSPEC_PROJECT_ROOT}/shared-libs/local/scripts/container-stage.sh"
  }
  cleanup_entry() {
    rm -rf "$FAKE_HOME"
    unset STUB_GATE_RC STUB_SETUP_RC STUB_STAGE_RC 2>/dev/null || true
  }
  Before 'setup_entry'
  After 'cleanup_entry'

  It "requires a stage id (line 16 :? guard)"
    When run source "$TARGET"
    The status should not be success
    The stderr should include "stage id required"
  End

  It "gates first, then bootstraps and runs the stage (runs path)"
    # gate rc 0 -> "runs (per plan)" branch, then sourcing the wrapper and
    # dispatching setup + run_stage <id> in order.
    When run source "$TARGET" build
    The status should be success
    The output should include "[brik] build: runs (per plan)"
    # Dispatch order: gate, then bootstrap, then stage execution.
    The contents of file "$CALL_LOG" should equal "$(printf 'brik plan gate build\nsetup\nrun_stage build')"
  End

  It "exits 0 on a plan skip without bootstrapping (rc==1 branch)"
    export STUB_GATE_RC=1
    When run source "$TARGET" release
    The status should be success
    The output should include "[brik] [SKIP] release: per plan"
    # The bootstrap stubs were never reached: only the gate call is logged.
    The contents of file "$CALL_LOG" should not include "setup"
  End

  It "fails the job on a plan gate error (rc>1 branch, propagates rc)"
    export STUB_GATE_RC=7
    When run source "$TARGET" build
    The status should equal 7
    The stderr should include "plan gate error (rc=7)"
  End

  It "propagates a bootstrap failure (setup || exit \$?)"
    export STUB_SETUP_RC=4
    When run source "$TARGET" build
    The status should equal 4
    The output should include "[brik] build: runs (per plan)"
  End

  It "propagates the stage exit code (final dispatch return)"
    export STUB_STAGE_RC=3
    When run source "$TARGET" build
    The status should equal 3
    The output should include "[brik] build: runs (per plan)"
    The contents of file "$CALL_LOG" should include "run_stage build"
  End
End
