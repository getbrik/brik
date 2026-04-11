Describe "brik run pipeline optional flags (deploy, continue-on-error)"
  Include "$BRIK_HOME/runtime/bash/spec/support/mock_helper.sh"

    setup() {
      mock.setup
      mock.create_script "npm" 'echo "mock npm: $*"'
      mock.create_exit "node" 0
      mock.create_script "npx" 'echo "mock npx: $*"'
      for tool in semgrep osv-scanner gitleaks; do
        mock.create_script "$tool" 'echo "mock ${0##*/}: $*"'
      done
      mock.activate
      WORKSPACE="$(mktemp -d)"
      printf '{"name":"cli-test","version":"1.0.0","scripts":{"build":"echo ok","test":"echo ok"}}\n' > "${WORKSPACE}/package.json"
      mkdir -p "${WORKSPACE}/node_modules"
      CONFIG="$(mktemp)"
      printf 'version: 1\nproject:\n  name: cli-test\n  stack: node\nquality:\n  lint:\n    enabled: false\ntest:\n  framework: npm\n' > "$CONFIG"
    }
    cleanup() {
      mock.cleanup
      rm -rf "$WORKSPACE" "$CONFIG"
    }
    Before 'setup'
    After 'cleanup'

    It "accepts --with-deploy flag"
      When run script "$BRIK_BIN" run pipeline --workspace "$WORKSPACE" --config "$CONFIG" --with-deploy
      The status should be success
      The stdout should include "Pipeline Summary"
      The stderr should be present
    End

    It "accepts --continue-on-error flag"
      When run script "$BRIK_BIN" run pipeline --workspace "$WORKSPACE" --config "$CONFIG" --continue-on-error
      The status should be success
      The stdout should include "Pipeline Summary"
      The stderr should be present
    End
End
