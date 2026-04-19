#!/usr/bin/env bash
# install_spec.sh - Integration tests for shim -> CLI delegation

Describe "shim integration"

  setup() {
    TMPDIR_INSTALL="$(mktemp -d)"
    TMPDIR_BIN="$(mktemp -d)"

    # Simulate an installation: copy the whole brik tree into a fake BRIK_HOME
    cp -R "${BRIK_HOME}/." "${TMPDIR_INSTALL}/"

    # Resolve to canonical path (handles macOS /var -> /private/var)
    TMPDIR_INSTALL="$(cd -P "${TMPDIR_INSTALL}" && pwd)"

    # Copy the shim into a fake bin dir
    cp "${BRIK_HOME}/bin/brik-shim" "${TMPDIR_BIN}/brik"
    chmod +x "${TMPDIR_BIN}/brik"

    # Export BRIK_HOME so run script inherits it
    export BRIK_HOME="${TMPDIR_INSTALL}"
  }

  cleanup() {
    rm -rf "${TMPDIR_INSTALL}" "${TMPDIR_BIN}"
  }

  Before "setup"
  After "cleanup"

  Describe "shim delegates to real CLI"
    It "runs brik version via the shim"
      When run script "${TMPDIR_BIN}/brik" version
      The status should eq 0
      The output should include "brik 0.2.0"
    End

    It "passes --verbose through the shim"
      When run script "${TMPDIR_BIN}/brik" version --verbose
      The status should eq 0
      The output should include "home:"
    End

    It "warns when BRIK_HOME differs from resolved path"
      # Create a symlink alias so BRIK_HOME differs from the resolved path
      # This test uses run command because it calls bin/brik directly (not shim)
      TMPDIR_ALIAS="${TMPDIR_INSTALL}-alias"
      ln -sfn "${TMPDIR_INSTALL}" "${TMPDIR_ALIAS}"
      When run command env BRIK_HOME="${TMPDIR_ALIAS}" "${TMPDIR_INSTALL}/bin/brik" version
      The status should eq 0
      The output should include "brik 0.2.0"
      The stderr should include "BRIK_HOME overridden"
    End
  End

  Describe "shim with missing runtime"
    setup_missing() {
      TMPDIR_BIN_MISS="$(mktemp -d)"
      cp "${BRIK_HOME}/bin/brik-shim" "${TMPDIR_BIN_MISS}/brik"
      chmod +x "${TMPDIR_BIN_MISS}/brik"
      export BRIK_HOME="/tmp/brik-nonexistent-$$"
    }
    cleanup_missing() {
      rm -rf "${TMPDIR_BIN_MISS}"
    }

    Before "setup_missing"
    After "cleanup_missing"

    It "exits with error when BRIK_HOME points to empty dir"
      When run script "${TMPDIR_BIN_MISS}/brik" version
      The status should eq 1
      The stderr should include "runtime not found"
    End
  End

End
