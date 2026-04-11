Describe "security/container.sh"
  Include "$BRIK_RUNTIME_LIB/logging.sh"
  Include "$BRIK_RUNTIME_LIB/tools.sh"
  Include "$BRIK_CORE_LIB/_loader.sh"
  Include "$BRIK_CORE_LIB/quality/_tools.sh"
  Include "$BRIK_CORE_LIB/security/container.sh"
  Include "$BRIK_HOME/runtime/bash/spec/support/mock_helper.sh"

  Describe "security.container.run"
    Describe "Tier 3: auto-detect grype"
      setup_grype() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock.log"
        mock.create_logging "grype" "$MOCK_LOG"
        mock.activate
      }
      cleanup_grype() {
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_grype'
      After 'cleanup_grype'

      It "auto-detects grype and scans image"
        invoke_grype() {
          security.container.run "$TEST_WS" --image "myapp:1.0" 2>/dev/null || return 1
          grep -q "grype myapp:1.0" "$MOCK_LOG"
        }
        When call invoke_grype
        The status should be success
      End
    End

    Describe "no scanner available"
      setup_none() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        mock.isolate
      }
      cleanup_none() {
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_none'
      After 'cleanup_none'

      It "skips when no scanner available"
        When call security.container.run "$TEST_WS"
        The status should be success
        The stderr should include "skipping"
      End
    End
  End
End
