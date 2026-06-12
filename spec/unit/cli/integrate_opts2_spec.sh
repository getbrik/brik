Describe "brik integrate optional flags (deploy, continue-on-error)"
  Include "$BRIK_HOME/spec/support/mock_helper.sh"

    setup() {

      # Pin the in-process (in-container) execution path: these examples

      # exercise the verb business logic, not the containerized engine.

      export BRIK_LOCAL_CONTAINER=1
      mock.setup
      mock.create_script "npm" 'echo "mock npm: $*"'
      mock.create_exit "node" 0
      mock.create_script "npx" 'echo "mock npx: $*"'
      for tool in semgrep osv-scanner gitleaks eslint prettier tsc; do
        mock.create_script "$tool" 'echo "mock ${0##*/}: $*"'
      done
      mock.activate
      WORKSPACE="$(mktemp -d)"
      printf '{"name":"cli-test","version":"1.0.0","scripts":{"build":"echo ok","test":"echo ok"}}\n' > "${WORKSPACE}/package.json"
      mkdir -p "${WORKSPACE}/node_modules"
      CONFIG="$(mktemp)"
      printf 'version: 1\nproject:\n  name: cli-test\n  stack: node\ntest:\n  framework: npm\n' > "$CONFIG"
    }
    cleanup() {
      mock.cleanup
      rm -rf "$WORKSPACE" "$CONFIG"
    }
    Before 'setup'
    After 'cleanup'

    It "accepts --with-deploy flag"
      When run script "$BRIK_BIN" integrate --workspace "$WORKSPACE" --config "$CONFIG" --with-deploy
      The status should be success
      The stdout should include "Pipeline Summary"
      The stderr should be present
    End

    It "accepts --continue-on-error flag"
      When run script "$BRIK_BIN" integrate --workspace "$WORKSPACE" --config "$CONFIG" --continue-on-error
      The status should be success
      The stdout should include "Pipeline Summary"
      The stderr should be present
    End
End
