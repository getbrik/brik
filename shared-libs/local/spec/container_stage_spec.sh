Describe "container-stage.sh"

  # Control-flow harness: a fake BRIK_HOME provides a stub `brik` CLI (gate
  # behavior driven by STUB_GATE_RC) and a stub local wrapper that records
  # bootstrap and stage execution. The real script under test is copied in
  # so its BRIK_HOME-relative paths resolve against the stubs.
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

    cp "${BRIK_HOME}/shared-libs/local/scripts/container-stage.sh" \
       "${FAKE_HOME}/shared-libs/local/scripts/container-stage.sh"
    ENTRY="${FAKE_HOME}/shared-libs/local/scripts/container-stage.sh"
  }
  cleanup_entry() {
    rm -rf "$FAKE_HOME"
    unset STUB_GATE_RC STUB_SETUP_RC STUB_STAGE_RC 2>/dev/null || true
  }
  Before 'setup_entry'
  After 'cleanup_entry'

  It "requires a stage id"
    check_noarg() { BRIK_HOME="$FAKE_HOME" bash "$ENTRY"; }
    When call check_noarg
    The status should not be success
    The stderr should include "stage id required"
  End

  It "gates first, then bootstraps and runs the stage"
    check_flow() {
      BRIK_HOME="$FAKE_HOME" bash "$ENTRY" build >/dev/null 2>&1
      cat "$CALL_LOG"
    }
    When call check_flow
    The line 1 should equal "brik plan gate build"
    The line 2 should equal "setup"
    The line 3 should equal "run_stage build"
  End

  It "exits 0 on a plan skip without bootstrapping"
    check_skip() {
      STUB_GATE_RC=1 BRIK_HOME="$FAKE_HOME" bash "$ENTRY" release
      local rc=$?
      local bootstrapped="no"
      grep -q "setup" "$CALL_LOG" && bootstrapped="yes"
      echo "rc=$rc bootstrapped=$bootstrapped"
    }
    When call check_skip
    The output should include "[SKIP] release: per plan"
    The output should include "rc=0 bootstrapped=no"
  End

  It "fails the job on a plan gate error"
    check_gate_error() {
      STUB_GATE_RC=7 BRIK_HOME="$FAKE_HOME" bash "$ENTRY" build 2>/dev/null
      echo "rc=$?"
    }
    When call check_gate_error
    The output should include "rc=7"
  End

  It "propagates a bootstrap failure"
    check_setup_fail() {
      STUB_SETUP_RC=4 BRIK_HOME="$FAKE_HOME" bash "$ENTRY" build >/dev/null 2>&1
      echo "rc=$?"
    }
    When call check_setup_fail
    The output should equal "rc=4"
  End

  It "propagates the stage exit code"
    check_stage_fail() {
      STUB_STAGE_RC=1 BRIK_HOME="$FAKE_HOME" bash "$ENTRY" build >/dev/null 2>&1
      echo "rc=$?"
    }
    When call check_stage_fail
    The output should equal "rc=1"
  End
End
