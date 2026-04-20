Describe "build.sh"
  Include "$BRIK_PIPELINE_LIB/logging.sh"
  Include "$BRIK_PIPELINE_LIB/tools.sh"
  Include "$BRIK_PIPELINE_LIB/loader.sh"
  Include "$BRIK_CORE_LIB/build.sh"
  Include "$BRIK_HOME/spec/support/mock_helper.sh"

  # Note: stacks.detect tests moved to spec/stacks/_detect_spec.sh.

  Describe "build.run"
    It "returns 6 for nonexistent workspace"
      When call build.run "/nonexistent/workspace"
      The status should equal 6
      The stderr should include "required directory not found"
    End

    It "returns 2 for unknown option"
      When call build.run "$WORKSPACES/node-simple" --badopt foo
      The status should equal 2
      The stderr should include "unknown option"
    End

    Describe "with unsupported stack"
      setup_unsupported() {
        TEST_WS="$(mktemp -d)"
      }
      cleanup_unsupported() { rm -rf "$TEST_WS"; }
      Before 'setup_unsupported'
      After 'cleanup_unsupported'

      It "returns 7 when stack cannot be detected"
        When call build.run "$TEST_WS"
        The status should equal 7
        The stderr should be present
      End

      It "returns 7 for unsupported explicit stack"
        When call build.run "$TEST_WS" --stack cobol
        The status should equal 7
        The stderr should include "unsupported build stack"
      End
    End

    Describe "with node stack and mock npm"
      setup_node_build() {
        TEST_WS="$(mktemp -d)"
        printf '{"name":"test","version":"1.0.0","scripts":{"build":"echo ok"}}\n' > "${TEST_WS}/package.json"
        mkdir -p "${TEST_WS}/node_modules"
        mock.setup
        mock.create_script "npm" 'printf "mock-npm %s\n" "$*"
exit 0'
        mock.create_exit "node" 0
        mock.activate
      }
      cleanup_node_build() {
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_node_build'
      After 'cleanup_node_build'

      It "auto-detects node and builds successfully"
        When call build.run "$TEST_WS"
        The status should be success
        The stdout should be present
        The stderr should include "building with stack: node"
      End

      It "accepts --stack option and logs the specified stack"
        When call build.run "$TEST_WS" --stack node
        The status should be success
        The stdout should be present
        The stderr should include "building with stack: node"
      End
    End
  End
End
