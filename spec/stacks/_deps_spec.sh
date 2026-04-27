Describe "stacks.install_deps"
  Include "$BRIK_PIPELINE_LIB/logging.sh"
  Include "$BRIK_HOME/lib/stacks/_deps.sh"

  setup_workspace() {
    DEPS_WS="$(mktemp -d)"
  }
  cleanup_workspace() { rm -rf "$DEPS_WS"; }
  Before 'setup_workspace'
  After 'cleanup_workspace'

  Describe "_brik._install_deps_node"
    It "returns 0 when there is no package.json (no-op skip)"
      run_no_pkg() {
        # No package.json in workspace; node_modules absent triggers install branch
        # but the install command itself is best-effort. After the broad refactor,
        # a missing package.json should still be a clean skip (rc 0), since
        # there is nothing to install.
        npm() { return 1; }  # would fail if invoked
        _brik._install_deps_node "$DEPS_WS"
      }
      When call run_no_pkg
      The status should be success
    End

    It "returns 0 when npm ci succeeds"
      run_ok() {
        printf '{"name":"t","version":"0.0.0"}\n' > "$DEPS_WS/package.json"
        printf '{"name":"t","version":"0.0.0","lockfileVersion":3,"requires":true,"packages":{"":{"name":"t","version":"0.0.0"}}}\n' > "$DEPS_WS/package-lock.json"
        npm() { return 0; }
        _brik._install_deps_node "$DEPS_WS"
      }
      When call run_ok
      The status should be success
      The stderr should include "installing node dependencies"
    End

    It "propagates BRIK_EXIT_MISSING_DEP when npm ci fails"
      run_fail() {
        printf '{"name":"t","version":"0.0.0"}\n' > "$DEPS_WS/package.json"
        printf '{"name":"t","version":"0.0.0","lockfileVersion":3,"requires":true,"packages":{"":{"name":"t","version":"0.0.0"}}}\n' > "$DEPS_WS/package-lock.json"
        npm() { return 1; }
        _brik._install_deps_node "$DEPS_WS"
      }
      When call run_fail
      The status should equal "$BRIK_EXIT_MISSING_DEP"
      The stderr should include "npm ci failed"
    End

    It "skips when node_modules already exists"
      run_skip() {
        mkdir -p "$DEPS_WS/node_modules"
        npm() { return 1; }  # would fail if invoked
        _brik._install_deps_node "$DEPS_WS"
      }
      When call run_skip
      The status should be success
    End
  End

  Describe "stacks.install_deps dispatch"
    It "returns 0 for an unknown stack"
      run_unknown() {
        export BRIK_BUILD_STACK="unknown"
        stacks.install_deps "$DEPS_WS" dev
      }
      When call run_unknown
      The status should be success
    End

    It "propagates failure from the underlying installer"
      run_propagate() {
        export BRIK_BUILD_STACK="node"
        printf '{"name":"t","version":"0.0.0"}\n' > "$DEPS_WS/package.json"
        printf '{"name":"t","version":"0.0.0","lockfileVersion":3,"requires":true,"packages":{"":{"name":"t","version":"0.0.0"}}}\n' > "$DEPS_WS/package-lock.json"
        npm() { return 1; }
        stacks.install_deps "$DEPS_WS" dev
      }
      When call run_propagate
      The status should equal "$BRIK_EXIT_MISSING_DEP"
      The stderr should include "npm ci failed"
    End
  End
End
