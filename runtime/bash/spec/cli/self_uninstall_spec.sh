#!/usr/bin/env bash
# self_uninstall_spec.sh - ShellSpec tests for `brik self-uninstall`

Describe "brik self-uninstall"

  Describe "option parsing"
    It "rejects unknown options"
      When run script "${BRIK_BIN}" self-uninstall --badopt
      The status should eq 2
      The stderr should include "unknown option"
    End
  End

  Describe "--force with fake BRIK_HOME"
    setup_fake_home() {
      FAKE_HOME="$(mktemp -d)"
      FAKE_HOME="$(cd -P "${FAKE_HOME}" && pwd)"
      mkdir -p "${FAKE_HOME}/bin"
      # Copy the real brik CLI so it can execute
      cp "${BRIK_HOME}/bin/brik" "${FAKE_HOME}/bin/brik"
      chmod +x "${FAKE_HOME}/bin/brik"
      # Copy runtime so brik can load its libs
      cp -R "${BRIK_HOME}/runtime" "${FAKE_HOME}/runtime" 2>/dev/null || true
      cp -R "${BRIK_HOME}/schemas" "${FAKE_HOME}/schemas" 2>/dev/null || true
      export BRIK_HOME="${FAKE_HOME}"
    }
    cleanup_fake_home() { rm -rf "${FAKE_HOME}"; }
    Before 'setup_fake_home'
    After 'cleanup_fake_home'

    It "removes the BRIK_HOME directory with --force"
      When run script "${FAKE_HOME}/bin/brik" self-uninstall --force
      The status should eq 0
      The output should include "removing runtime"
      The output should include "brik has been removed"
    End
  End

  Describe "path safety - missing bin/brik in target"
    setup_no_bin() {
      # Create a working brik copy (source of the script)
      SCRIPT_HOME="$(mktemp -d)"
      SCRIPT_HOME="$(cd -P "${SCRIPT_HOME}" && pwd)"
      mkdir -p "${SCRIPT_HOME}/bin"
      cp "${BRIK_HOME}/bin/brik" "${SCRIPT_HOME}/bin/brik"
      chmod +x "${SCRIPT_HOME}/bin/brik"
      cp -R "${BRIK_HOME}/runtime" "${SCRIPT_HOME}/runtime" 2>/dev/null || true
      cp -R "${BRIK_HOME}/schemas" "${SCRIPT_HOME}/schemas" 2>/dev/null || true
      # Point BRIK_HOME to a dir without bin/brik but with runtime libs
      TARGET_HOME="$(mktemp -d)"
      TARGET_HOME="$(cd -P "${TARGET_HOME}" && pwd)"
      cp -R "${BRIK_HOME}/runtime" "${TARGET_HOME}/runtime" 2>/dev/null || true
      export BRIK_HOME="${TARGET_HOME}"
    }
    cleanup_no_bin() { rm -rf "${SCRIPT_HOME}" "${TARGET_HOME}"; }
    Before 'setup_no_bin'
    After 'cleanup_no_bin'

    It "refuses when bin/brik missing from target"
      When run script "${SCRIPT_HOME}/bin/brik" self-uninstall --force
      The status should eq 2
      The stderr should include "does not look like a brik installation"
    End
  End

  Describe "cancellation"
    It "cancels when user declines"
      Data "n"
      When run script "${BRIK_BIN}" self-uninstall
      The status should eq 0
      The output should include "cancelled"
    End
  End

End
