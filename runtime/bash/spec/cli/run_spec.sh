Describe "brik run"
  Include "$BRIK_HOME/runtime/bash/spec/support/mock_helper.sh"

  Describe "brik run without subcommand"
    It "shows an error message"
      When run script "$BRIK_BIN" run
      The status should equal 2
      The stderr should include "requires a subcommand"
    End
  End

  Describe "brik run stage without name"
    It "shows an error message"
      When run script "$BRIK_BIN" run stage
      The status should equal 2
      The stderr should include "requires a stage name"
    End
  End

  Describe "brik run unknown subcommand"
    It "shows an error message"
      When run script "$BRIK_BIN" run foobar
      The status should equal 2
      The stderr should include "unknown run subcommand"
    End
  End

  Describe "brik unknown command"
    It "shows an error and help hint"
      When run script "$BRIK_BIN" foobar
      The status should equal 2
      The stderr should include "unknown command"
      The stderr should include "brik help"
    End
  End

  Describe "brik run stage build --badopt"
    It "shows an error for unknown option"
      When run script "$BRIK_BIN" run stage build --badopt
      The status should equal 2
      The stderr should include "unknown option"
    End
  End

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
    setup() {
      WORKSPACE="$(mktemp -d)"
      CONFIG="$(mktemp)"
      printf 'version: 1\nproject:\n  name: cli-test\n  stack: node\nquality:\n  lint:\n    enabled: false\n' > "$CONFIG"
    }
    cleanup() { rm -rf "$WORKSPACE" "$CONFIG"; }
    Before 'setup'
    After 'cleanup'

    It "executes lint stage successfully (disabled)"
      When run script "$BRIK_BIN" run stage lint --workspace "$WORKSPACE" --config "$CONFIG"
      The status should be success
      The stdout should include "lint disabled"
      The stderr should include "stage lint completed successfully"
    End
  End

End
