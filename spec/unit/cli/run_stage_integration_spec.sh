Describe "brik run stage - integration"
  Include "$BRIK_HOME/spec/support/mock_helper.sh"

  Describe "brik run stage build --config"
    setup() {
      mock.setup
      mock.create_script "npm" 'echo "mock npm: $*"'
      mock.create_exit "node" 0
      mock.activate
      WORKSPACE="$(mktemp -d)"
      printf '{"name":"cli-test","version":"1.0.0","scripts":{"build":"echo ok"}}\n' > "${WORKSPACE}/package.json"
      mkdir -p "${WORKSPACE}/node_modules"
      CONFIG="${WORKSPACE}/brik.yml"
      printf 'version: 1\nproject:\n  name: cli-test\n  stack: node\ntest:\n  framework: npm\n' > "$CONFIG"
    }
    cleanup() {
      mock.cleanup
      rm -rf "$WORKSPACE"
    }
    Before 'setup'
    After 'cleanup'

    It "accepts --config option"
      When run script "$BRIK_BIN" run stage build --workspace "$WORKSPACE" --config "$CONFIG"
      The status should be success
      The stdout should be present
      The stderr should include "stage build completed successfully"
    End
  End

  Describe "brik run stage build"
    setup() {
      mock.setup
      mock.create_script "npm" 'echo "mock npm: $*"'
      mock.create_exit "node" 0
      mock.activate
      WORKSPACE="$(mktemp -d)"
      printf '{"name":"cli-test","version":"1.0.0","scripts":{"build":"echo ok"}}\n' > "${WORKSPACE}/package.json"
      mkdir -p "${WORKSPACE}/node_modules"
      printf 'version: 1\nproject:\n  name: cli-test\n  stack: node\ntest:\n  framework: npm\n' > "${WORKSPACE}/brik.yml"
    }
    cleanup() {
      mock.cleanup
      rm -rf "$WORKSPACE"
    }
    Before 'setup'
    After 'cleanup'

    It "executes successfully with a node workspace"
      When run script "$BRIK_BIN" run stage build --workspace "$WORKSPACE"
      The status should be success
      The stdout should be present
      The stderr should include "stage build completed successfully"
    End
  End

  Describe "brik run stage test"
    setup() {
      mock.setup
      mock.create_script "npx" 'echo "mock npx: $*"'
      mock.create_script "npm" 'exit 0'
      mock.activate
      WORKSPACE="$(mktemp -d)"
      printf '{"name":"cli-test","version":"1.0.0","scripts":{"test":"echo ok"}}\n' > "${WORKSPACE}/package.json"
      printf 'version: 1\nproject:\n  name: cli-test\n  stack: node\ntest:\n  framework: npm\n' > "${WORKSPACE}/brik.yml"
    }
    cleanup() {
      mock.cleanup
      rm -rf "$WORKSPACE"
    }
    Before 'setup'
    After 'cleanup'

    It "executes test stage successfully with a node workspace"
      When run script "$BRIK_BIN" run stage test --workspace "$WORKSPACE"
      The status should be success
      The stdout should be present
      The stderr should include "stage test completed successfully"
    End
  End

  Describe "brik run stage init"
    setup() {
      WORKSPACE="$(mktemp -d)"
      printf '{"name":"cli-test","version":"1.0.0"}\n' > "${WORKSPACE}/package.json"
      CONFIG="$(mktemp)"
      printf 'version: 1\nproject:\n  name: cli-test\n  stack: node\ntest:\n  framework: npm\n' > "$CONFIG"
    }
    cleanup() { rm -rf "$WORKSPACE" "$CONFIG"; }
    Before 'setup'
    After 'cleanup'

    It "executes init stage successfully"
      When run script "$BRIK_BIN" run stage init --workspace "$WORKSPACE" --config "$CONFIG"
      The status should be success
      The stdout should include "cli-test"
      The stderr should include "stage init completed successfully"
    End
  End

  Describe "brik run stage lint"
    Include "$BRIK_HOME/spec/support/mock_helper.sh"

    setup() {
      mock.setup
      mock.create_script "npm" 'echo "mock npm: $*"'
      mock.create_exit "node" 0
      for tool in eslint prettier tsc; do
        mock.create_script "$tool" 'echo "mock ${0##*/}: $*"'
      done
      mock.activate
      WORKSPACE="$(mktemp -d)"
      CONFIG="$(mktemp)"
      printf 'version: 1\nproject:\n  name: cli-test\n  stack: node\n' > "$CONFIG"
    }
    cleanup() {
      mock.cleanup
      rm -rf "$WORKSPACE" "$CONFIG"
    }
    Before 'setup'
    After 'cleanup'

    It "executes lint stage successfully"
      When run script "$BRIK_BIN" run stage lint --workspace "$WORKSPACE" --config "$CONFIG"
      The status should be success
      The stdout should include "lint"
      The stderr should be present
    End
  End

End
