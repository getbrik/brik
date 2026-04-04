#!/usr/bin/env bash
# install_spec.sh - Integration tests for shim -> CLI delegation

Describe "shim integration"

  setup() {
    TMPDIR_INSTALL="$(mktemp -d)"
    TMPDIR_BIN="$(mktemp -d)"

    # Simulate an installation: copy the whole brik tree into a fake BRIK_HOME
    cp -R "${BRIK_HOME}/." "${TMPDIR_INSTALL}/"

    # Copy the shim into a fake bin dir
    cp "${BRIK_HOME}/bin/brik-shim" "${TMPDIR_BIN}/brik"
    chmod +x "${TMPDIR_BIN}/brik"
  }

  cleanup() {
    rm -rf "${TMPDIR_INSTALL}" "${TMPDIR_BIN}"
  }

  Before "setup"
  After "cleanup"

  Describe "shim delegates to real CLI"
    It "runs brik version via the shim"
      When run command env BRIK_HOME="${TMPDIR_INSTALL}" "${TMPDIR_BIN}/brik" version
      The status should eq 0
      The output should include "brik 0.1.0"
      The stderr should include "BRIK_HOME overridden"
    End

    It "passes --verbose through the shim"
      When run command env BRIK_HOME="${TMPDIR_INSTALL}" "${TMPDIR_BIN}/brik" version --verbose
      The status should eq 0
      The output should include "home:"
      The stderr should include "BRIK_HOME overridden"
    End
  End

  Describe "shim with missing runtime"
    It "exits with error when BRIK_HOME points to empty dir"
      When run command env BRIK_HOME="/tmp/brik-nonexistent-$$" "${TMPDIR_BIN}/brik" version
      The status should eq 1
      The stderr should include "runtime not found"
    End
  End

End
