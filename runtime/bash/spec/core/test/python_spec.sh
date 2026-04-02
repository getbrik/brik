Describe "test/python.sh"
  Include "$BRIK_RUNTIME_LIB/logging.sh"
  Include "$BRIK_RUNTIME_LIB/tools.sh"
  Include "$BRIK_CORE_LIB/test/python.sh"

  Describe "test.python.cmd"
    It "returns python -m pytest for pytest framework"
      When call test.python.cmd "pytest" "/workspace" ""
      The output should equal "python -m pytest"
    End

    It "adds --junitxml when report_dir is provided"
      When call test.python.cmd "pytest" "/workspace" "/reports"
      The output should equal "python -m pytest --junitxml=/reports/report.xml"
    End

    It "returns 7 for unsupported framework"
      When call test.python.cmd "unknown" "/workspace" ""
      The status should equal 7
      The stderr should include "unsupported Python test framework"
    End
  End

  Describe "test.python.run_cmd"
    It "delegates to pytest by default"
      When call test.python.run_cmd "/workspace" ""
      The output should equal "python -m pytest"
    End

    It "passes report_dir through"
      When call test.python.run_cmd "/workspace" "/reports"
      The output should equal "python -m pytest --junitxml=/reports/report.xml"
    End
  End
End
