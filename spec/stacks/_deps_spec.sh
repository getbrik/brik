Describe "stacks.install_deps"
  Include "$BRIK_PIPELINE_LIB/logging.sh"
  Include "$BRIK_HOME/lib/stacks/_deps.sh"
  Include "$BRIK_HOME/spec/support/mock_helper.sh"

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

    It "skips install when node_modules is in sync with package-lock.json"
      run_cache_hit() {
        printf '{"name":"t","version":"0.0.0"}\n' > "$DEPS_WS/package.json"
        printf '{"name":"t","version":"0.0.0","lockfileVersion":3}\n' > "$DEPS_WS/package-lock.json"
        mkdir -p "$DEPS_WS/node_modules/.bin"
        cp "$DEPS_WS/package-lock.json" "$DEPS_WS/node_modules/.package-lock.json"
        npm() { return 1; }  # would fail if invoked
        _brik._install_deps_node "$DEPS_WS"
      }
      When call run_cache_hit
      The status should be success
    End

    It "skips install when node_modules exists and there is no package-lock.json"
      run_legacy_skip() {
        printf '{"name":"t","version":"0.0.0"}\n' > "$DEPS_WS/package.json"
        mkdir -p "$DEPS_WS/node_modules/.bin"
        npm() { return 1; }  # would fail if invoked
        _brik._install_deps_node "$DEPS_WS"
      }
      When call run_legacy_skip
      The status should be success
    End
  End

  Describe "_brik._install_deps_python"
    It "propagates failure when test mode requirements.txt install fails"
      run_py_test_req_fail() {
        printf 'requests\n' > "$DEPS_WS/requirements.txt"
        pip() {
          if [[ "$1" == "install" && "$2" == "--help" ]]; then
            echo "usage"; return 0
          fi
          return 1
        }
        _brik._install_deps_python "$DEPS_WS" test
      }
      When call run_py_test_req_fail
      The status should equal "$BRIK_EXIT_MISSING_DEP"
      The stderr should include "pip install -r requirements.txt failed"
    End

    It "propagates failure when dev mode requirements-dev.txt install fails"
      run_py_dev_req_fail() {
        printf 'pytest\n' > "$DEPS_WS/requirements-dev.txt"
        pip() {
          if [[ "$1" == "install" && "$2" == "--help" ]]; then
            echo "usage"; return 0
          fi
          return 1
        }
        _brik._install_deps_python "$DEPS_WS" dev
      }
      When call run_py_dev_req_fail
      The status should equal "$BRIK_EXIT_MISSING_DEP"
      The stderr should include "requirements-dev.txt failed"
    End

    It "propagates failure when scan mode requirements.txt install fails"
      run_py_scan_req_fail() {
        printf 'requests\n' > "$DEPS_WS/requirements.txt"
        pip() {
          if [[ "$1" == "install" && "$2" == "--help" ]]; then
            echo "usage"; return 0
          fi
          return 1
        }
        _brik._install_deps_python "$DEPS_WS" scan
      }
      When call run_py_scan_req_fail
      The status should equal "$BRIK_EXIT_MISSING_DEP"
      The stderr should include "pip install -r requirements.txt failed"
    End

  End

  Describe "_brik._install_deps_rust"
    setup_rust_mock() {
      mock.setup
      mock.create_failing "rustup"
      # Mirror the lint_spec pattern: keep system essentials on PATH while
      # exposing only the failing rustup mock; clippy/rustfmt remain absent
      # so the missing-component branch is taken.
      export PATH="${MOCK_BIN}:/usr/bin:/bin"
    }
    cleanup_rust_mock() { mock.cleanup; }
    Before 'setup_rust_mock'
    After 'cleanup_rust_mock'

    It "propagates failure when rustup component add fails"
      When call _brik._install_deps_rust
      The status should equal "$BRIK_EXIT_MISSING_DEP"
      The stderr should include "rustup component add failed"
    End
  End

  Describe "_brik._install_deps_dotnet"
    It "propagates failure when dotnet restore fails"
      run_dotnet_fail() {
        dotnet() { return 1; }
        _brik._install_deps_dotnet "$DEPS_WS"
      }
      When call run_dotnet_fail
      The status should equal "$BRIK_EXIT_MISSING_DEP"
      The stderr should include "dotnet restore failed"
    End

    It "returns success when dotnet restore succeeds"
      run_dotnet_ok() {
        dotnet() { return 0; }
        _brik._install_deps_dotnet "$DEPS_WS"
      }
      When call run_dotnet_ok
      The status should be success
      The stderr should include "restoring dotnet dependencies"
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
