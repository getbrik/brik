Describe "doctor.sh"
  Include "$BRIK_RUNTIME_LIB/logging.sh"
  Include "$BRIK_RUNTIME_LIB/tools.sh"
  Include "$BRIK_CORE_LIB/_loader.sh"
  Include "$BRIK_CORE_LIB/doctor.sh"

  Describe "doctor.run"
    It "succeeds when core tools are present"
      When call doctor.run "."
      The status should eq 0
      The output should include "checks passed"
    End

    It "reports bash version"
      When call doctor.run "."
      The output should include "bash"
      The output should include "OK"
    End

    It "reports yq and jq"
      When call doctor.run "."
      The output should include "yq"
      The output should include "jq"
    End

    It "prints header"
      When call doctor.run "."
      The output should include "brik doctor"
    End

    It "returns IO_FAILURE for missing workspace"
      When call doctor.run "/nonexistent/workspace"
      The status should eq 6
      The stderr should include "not found"
    End
  End

  Describe "doctor.run with stack detection"
    setup_node_workspace() {
      TEMP_WS="$(mktemp -d)"
      printf '{"name":"test"}\n' > "$TEMP_WS/package.json"
    }
    cleanup_node_workspace() { rm -rf "$TEMP_WS"; }
    Before 'setup_node_workspace'
    After 'cleanup_node_workspace'

    It "detects node stack"
      When call doctor.run "$TEMP_WS"
      The output should include "Detected stack: node"
    End
  End

  Describe "doctor.run with python workspace"
    setup_python_workspace() {
      TEMP_WS="$(mktemp -d)"
      printf 'flask\n' > "$TEMP_WS/requirements.txt"
    }
    cleanup_python_workspace() { rm -rf "$TEMP_WS"; }
    Before 'setup_python_workspace'
    After 'cleanup_python_workspace'

    It "detects python from requirements.txt"
      When call doctor.run "$TEMP_WS"
      The output should include "Detected stack: python"
    End
  End

  Describe "doctor.run with empty workspace"
    setup_empty_workspace() { TEMP_WS="$(mktemp -d)"; }
    cleanup_empty_workspace() { rm -rf "$TEMP_WS"; }
    Before 'setup_empty_workspace'
    After 'cleanup_empty_workspace'

    It "reports no stack detected"
      When call doctor.run "$TEMP_WS"
      The output should include "No stack detected"
    End
  End

  Describe "doctor._tool_version"
    It "returns version for bash"
      When call doctor._tool_version bash
      The output should not eq ""
    End

    It "returns 'installed' as fallback"
      When call doctor._tool_version "nonexistent-tool-xyz"
      The output should eq "installed"
    End
  End
End
