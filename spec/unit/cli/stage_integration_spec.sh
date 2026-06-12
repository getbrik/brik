Describe "brik stage - integration"
  Include "$BRIK_HOME/spec/support/mock_helper.sh"

  Describe "brik stage build --config"
    setup() {
      # Pin the in-process (in-container) execution path: these examples
      # exercise the verb business logic, not the containerized engine.
      export BRIK_LOCAL_CONTAINER=1
      export BRIK_LOG_DIR
      BRIK_LOG_DIR="$(mktemp -d)"
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
      rm -rf "$BRIK_LOG_DIR"; unset BRIK_LOG_DIR
      mock.cleanup
      rm -rf "$WORKSPACE"
    }
    Before 'setup'
    After 'cleanup'

    It "accepts --config option"
      When run script "$BRIK_BIN" stage build --workspace "$WORKSPACE" --config "$CONFIG"
      The status should be success
      The stdout should be present
      The stderr should include "stage build completed successfully"
    End
  End

  Describe "brik stage build"
    setup() {
      # Pin the in-process (in-container) execution path: these examples
      # exercise the verb business logic, not the containerized engine.
      export BRIK_LOCAL_CONTAINER=1
      export BRIK_LOG_DIR
      BRIK_LOG_DIR="$(mktemp -d)"
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
      rm -rf "$BRIK_LOG_DIR"; unset BRIK_LOG_DIR
      mock.cleanup
      rm -rf "$WORKSPACE"
    }
    Before 'setup'
    After 'cleanup'

    It "executes successfully with a node workspace"
      When run script "$BRIK_BIN" stage build --workspace "$WORKSPACE"
      The status should be success
      The stdout should be present
      The stderr should include "stage build completed successfully"
    End
  End

  Describe "brik stage test"
    setup() {
      # Pin the in-process (in-container) execution path: these examples
      # exercise the verb business logic, not the containerized engine.
      export BRIK_LOCAL_CONTAINER=1
      export BRIK_LOG_DIR
      BRIK_LOG_DIR="$(mktemp -d)"
      mock.setup
      mock.create_script "npx" 'echo "mock npx: $*"'
      mock.create_script "npm" 'exit 0'
      mock.activate
      WORKSPACE="$(mktemp -d)"
      printf '{"name":"cli-test","version":"1.0.0","scripts":{"test":"echo ok"}}\n' > "${WORKSPACE}/package.json"
      printf 'version: 1\nproject:\n  name: cli-test\n  stack: node\ntest:\n  framework: npm\n' > "${WORKSPACE}/brik.yml"
    }
    cleanup() {
      rm -rf "$BRIK_LOG_DIR"; unset BRIK_LOG_DIR
      mock.cleanup
      rm -rf "$WORKSPACE"
    }
    Before 'setup'
    After 'cleanup'

    It "executes test stage successfully with a node workspace"
      When run script "$BRIK_BIN" stage test --workspace "$WORKSPACE"
      The status should be success
      The stdout should be present
      The stderr should include "stage test completed successfully"
    End
  End

  Describe "brik stage init"
    Include "$BRIK_HOME/spec/support/mock_helper.sh"

    setup() {

      # Pin the in-process (in-container) execution path: these examples

      # exercise the verb business logic, not the containerized engine.

      export BRIK_LOCAL_CONTAINER=1
      export BRIK_LOG_DIR
      BRIK_LOG_DIR="$(mktemp -d)"
      mock.infra.setup
      WORKSPACE="$(mktemp -d)"
      printf '{"name":"cli-test","version":"1.0.0"}\n' > "${WORKSPACE}/package.json"
      CONFIG="$(mktemp)"
      printf 'version: 1\nproject:\n  name: cli-test\n  stack: node\ntest:\n  framework: npm\n' > "$CONFIG"
    }
    cleanup() {
      rm -rf "$BRIK_LOG_DIR" "$WORKSPACE" "$CONFIG"; unset BRIK_LOG_DIR
      mock.infra.teardown
    }
    Before 'setup'
    After 'cleanup'

    It "executes init stage successfully"
      When run script "$BRIK_BIN" stage init --workspace "$WORKSPACE" --config "$CONFIG"
      The status should be success
      The stdout should include "cli-test"
      The stderr should include "stage init completed successfully"
    End
  End

  Describe "brik stage lint"
    Include "$BRIK_HOME/spec/support/mock_helper.sh"

    setup() {

      # Pin the in-process (in-container) execution path: these examples

      # exercise the verb business logic, not the containerized engine.

      export BRIK_LOCAL_CONTAINER=1
      export BRIK_LOG_DIR
      BRIK_LOG_DIR="$(mktemp -d)"
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
      rm -rf "$BRIK_LOG_DIR"; unset BRIK_LOG_DIR
      mock.cleanup
      rm -rf "$WORKSPACE" "$CONFIG"
    }
    Before 'setup'
    After 'cleanup'

    It "executes lint stage successfully"
      When run script "$BRIK_BIN" stage lint --workspace "$WORKSPACE" --config "$CONFIG"
      The status should be success
      The stdout should include "lint"
      The stderr should be present
    End
  End

End
