Describe "security/license.sh"
  Include "$BRIK_RUNTIME_LIB/logging.sh"
  Include "$BRIK_RUNTIME_LIB/tools.sh"
  Include "$BRIK_CORE_LIB/_loader.sh"
  Include "$BRIK_CORE_LIB/quality/_tools.sh"
  Include "$BRIK_CORE_LIB/security/license.sh"
  Include "$BRIK_HOME/runtime/bash/spec/support/mock_helper.sh"

  Describe "security.license.run"
    It "returns 6 for nonexistent workspace"
      When call security.license.run "/nonexistent/workspace"
      The status should equal 6
      The stderr should include "required directory not found"
    End

    Describe "license_finder available"
      setup_lf() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock.log"
        mock.create_logging "license_finder" "$MOCK_LOG"
        mock.activate
      }
      cleanup_lf() {
        unset BRIK_SECURITY_LICENSE_ALLOWED BRIK_SECURITY_LICENSE_DENIED
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_lf'
      After 'cleanup_lf'

      It "runs license_finder action_items"
        invoke_lf() {
          security.license.run "$TEST_WS" 2>/dev/null || return 1
          grep -q "license_finder action_items" "$MOCK_LOG"
        }
        When call invoke_lf
        The status should be success
      End

      It "adds permitted licenses when BRIK_SECURITY_LICENSE_ALLOWED is set"
        invoke_with_allowed() {
          export BRIK_SECURITY_LICENSE_ALLOWED="MIT,Apache-2.0"
          security.license.run "$TEST_WS" 2>/dev/null || return 1
          grep -c "permitted_licenses add" "$MOCK_LOG"
        }
        When call invoke_with_allowed
        The output should equal "2"
      End

      It "adds restricted licenses when BRIK_SECURITY_LICENSE_DENIED is set"
        invoke_with_denied() {
          export BRIK_SECURITY_LICENSE_DENIED="GPL-3.0,AGPL-3.0"
          security.license.run "$TEST_WS" 2>/dev/null || return 1
          grep -c "restricted_licenses add" "$MOCK_LOG"
        }
        When call invoke_with_denied
        The output should equal "2"
      End

      It "logs license check passed on success"
        When call security.license.run "$TEST_WS"
        The status should be success
        The stderr should include "license check passed"
      End
    End

    Describe "license_finder fails"
      setup_lf_fail() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        mock.create_script "license_finder" 'if [ "$1" = "action_items" ]; then
  exit 1
fi
exit 0'
        mock.activate
      }
      cleanup_lf_fail() {
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_lf_fail'
      After 'cleanup_lf_fail'

      It "returns 10 when license violations found"
        When call security.license.run "$TEST_WS"
        The status should equal 10
        The stderr should include "license violations found"
      End
    End

    Describe "fallback via registry (syft)"
      setup_syft() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock.log"
        mock.create_logging "syft" "$MOCK_LOG"
        ln -sf "$(command -v bash)" "${MOCK_BIN}/bash"
        ln -sf "$(command -v grep)" "${MOCK_BIN}/grep"
        mock.isolate
      }
      cleanup_syft() {
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_syft'
      After 'cleanup_syft'

      It "auto-detects syft as fallback"
        invoke_syft() {
          security.license.run "$TEST_WS" 2>/dev/null || return 1
          grep -q "syft" "$MOCK_LOG"
        }
        When call invoke_syft
        The status should be success
      End
    End

    Describe "no tool available"
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

      It "skips when no license scanner available"
        When call security.license.run "$TEST_WS"
        The status should be success
        The stderr should include "skipping"
      End
    End
  End
End
