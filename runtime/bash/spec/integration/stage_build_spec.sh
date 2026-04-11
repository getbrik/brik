Describe "Integration: stage.run with build"
  Include "$BRIK_RUNTIME_LIB/stage.sh"
  Include "$BRIK_CORE_LIB/_loader.sh"
  Include "$BRIK_HOME/runtime/bash/spec/support/mock_helper.sh"

  Describe "stage.run build with node workspace"
    setup() {
      export BRIK_PROJECT_DIR="/nonexistent"
      mock.setup
      mock.create_script "npm" 'case "$1" in
  run) echo "mock npm build ok"; exit 0 ;;
  ci|install) echo "mock npm install ok"; exit 0 ;;
  *) echo "mock npm: $*"; exit 0 ;;
esac'
      mock.activate
      WORKSPACE="$(mktemp -d)"
      printf '{"name":"integration-test","version":"1.0.0","scripts":{"build":"echo built"}}\n' > "${WORKSPACE}/package.json"
      mkdir -p "${WORKSPACE}/node_modules"
    }
    cleanup() {
      mock.cleanup
      rm -rf "$WORKSPACE"
    }
    Before 'setup'
    After 'cleanup'

    brik.use build
    brik.use build.node

    build_logic() {
      local ctx="$1"
      local ws="${WORKSPACE}"
      build.run "$ws" --stack node
      return $?
    }

    It "completes successfully with mock npm"
      When call stage.run "build" "build_logic"
      The status should be success
      The stderr should include "starting stage: build"
      The stdout should include "mock npm build ok"
    End

    It "produces a summary JSON with SUCCESS"
      verify_summary() {
        stage.run "build" "build_logic" >/dev/null 2>&1
        jq -e '.status == "SUCCESS"' "${BRIK_LOG_DIR}/build-summary.json" >/dev/null
      }
      When call verify_summary
      The status should be success
    End

    It "creates a log file"
      verify_log() {
        stage.run "build" "build_logic" >/dev/null 2>&1
        local count
        count="$(find "$BRIK_LOG_DIR" -name 'build-*.log' | wc -l)"
        [[ "$count" -gt 0 ]]
      }
      When call verify_log
      The status should be success
    End
  End

  Describe "stage.run build with failing npm"
    setup_fail() {
      export BRIK_PROJECT_DIR="/nonexistent"
      mock.setup
      mock.create_script "npm" 'echo "ERROR: build failed" >&2
exit 1'
      mock.activate
      WORKSPACE="$(mktemp -d)"
      printf '{"name":"fail-test","version":"1.0.0","scripts":{"build":"exit 1"}}\n' > "${WORKSPACE}/package.json"
      mkdir -p "${WORKSPACE}/node_modules"
    }
    cleanup_fail() {
      mock.cleanup
      rm -rf "$WORKSPACE"
    }
    Before 'setup_fail'
    After 'cleanup_fail'

    brik.use build
    brik.use build.node

    failing_build_logic() {
      local ctx="$1"
      build.run "$WORKSPACE" --stack node
      return $?
    }

    It "propagates the failure exit code"
      When call stage.run "build" "failing_build_logic"
      The status should equal 5
      The stderr should include "stage build failed"
      The stdout should include "ERROR: build failed"
    End

    It "generates a FAILED summary"
      verify_fail() {
        stage.run "build" "failing_build_logic" >/dev/null 2>&1 || true
        jq -e '.status == "FAILED"' "${BRIK_LOG_DIR}/build-summary.json" >/dev/null
      }
      When call verify_fail
      The status should be success
    End
  End
End
