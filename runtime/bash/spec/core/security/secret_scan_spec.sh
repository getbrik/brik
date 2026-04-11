Describe "security/secret_scan.sh"
  Include "$BRIK_RUNTIME_LIB/logging.sh"
  Include "$BRIK_RUNTIME_LIB/tools.sh"
  Include "$BRIK_CORE_LIB/_loader.sh"
  Include "$BRIK_CORE_LIB/quality/_tools.sh"
  Include "$BRIK_CORE_LIB/security/secret_scan.sh"
  Include "$BRIK_HOME/runtime/bash/spec/support/mock_helper.sh"

  Describe "security.secret_scan.run"
    It "returns 6 for nonexistent workspace"
      When call security.secret_scan.run "/nonexistent/workspace"
      The status should equal 6
      The stderr should include "required directory not found"
    End

    Describe "Tier 1: command override"
      setup_cmd() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        mock.create_exit "my-scanner" 0
        mock.activate
        export BRIK_SECURITY_SECRETS_COMMAND="my-scanner"
      }
      cleanup_cmd() {
        unset BRIK_SECURITY_SECRETS_COMMAND
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_cmd'
      After 'cleanup_cmd'

      It "runs command override"
        When call security.secret_scan.run "$TEST_WS"
        The status should be success
        The stderr should include "security secret scan passed"
      End
    End

    Describe "Tier 1: command override fails"
      setup_cmd_fail() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        mock.create_exit "fail-scanner" 1
        mock.activate
        export BRIK_SECURITY_SECRETS_COMMAND="fail-scanner"
      }
      cleanup_cmd_fail() {
        unset BRIK_SECURITY_SECRETS_COMMAND
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_cmd_fail'
      After 'cleanup_cmd_fail'

      It "returns 10 when command override finds secrets"
        When call security.secret_scan.run "$TEST_WS"
        The status should equal 10
        The stderr should include "security secret scan findings detected"
      End
    End

    Describe "Tier 2: gitleaks"
      setup_gitleaks() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock.log"
        mock.create_logging "gitleaks" "$MOCK_LOG"
        mock.activate
        export BRIK_SECURITY_SECRETS_TOOL="gitleaks"
      }
      cleanup_gitleaks() {
        unset BRIK_SECURITY_SECRETS_TOOL
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_gitleaks'
      After 'cleanup_gitleaks'

      It "runs gitleaks detect"
        invoke_gitleaks() {
          security.secret_scan.run "$TEST_WS" 2>/dev/null || return 1
          grep -q "gitleaks detect" "$MOCK_LOG"
        }
        When call invoke_gitleaks
        The status should be success
      End
    End

    Describe "Tier 2: trufflehog"
      setup_trufflehog() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock.log"
        mock.create_logging "trufflehog" "$MOCK_LOG"
        mock.activate
        export BRIK_SECURITY_SECRETS_TOOL="trufflehog"
      }
      cleanup_trufflehog() {
        unset BRIK_SECURITY_SECRETS_TOOL
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_trufflehog'
      After 'cleanup_trufflehog'

      It "runs trufflehog filesystem"
        invoke_trufflehog() {
          security.secret_scan.run "$TEST_WS" 2>/dev/null || return 1
          grep -q "trufflehog filesystem" "$MOCK_LOG"
        }
        When call invoke_trufflehog
        The status should be success
      End
    End

    Describe "Tier 2: gitleaks not found"
      setup_gitleaks_missing() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        mock.isolate
        export BRIK_SECURITY_SECRETS_TOOL="gitleaks"
      }
      cleanup_gitleaks_missing() {
        unset BRIK_SECURITY_SECRETS_TOOL
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_gitleaks_missing'
      After 'cleanup_gitleaks_missing'

      It "returns 3 when gitleaks binary not found"
        When call security.secret_scan.run "$TEST_WS"
        The status should equal 3
        The stderr should include "gitleaks not found"
      End
    End

    Describe "Tier 2: trufflehog not found"
      setup_trufflehog_missing() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        mock.isolate
        export BRIK_SECURITY_SECRETS_TOOL="trufflehog"
      }
      cleanup_trufflehog_missing() {
        unset BRIK_SECURITY_SECRETS_TOOL
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_trufflehog_missing'
      After 'cleanup_trufflehog_missing'

      It "returns 3 when trufflehog binary not found"
        When call security.secret_scan.run "$TEST_WS"
        The status should equal 3
        The stderr should include "trufflehog not found"
      End
    End

    Describe "Tier 2: unknown tool"
      setup_unknown() {
        TEST_WS="$(mktemp -d)"
        export BRIK_SECURITY_SECRETS_TOOL="nosuch-tool"
      }
      cleanup_unknown() {
        unset BRIK_SECURITY_SECRETS_TOOL
        rm -rf "$TEST_WS"
      }
      Before 'setup_unknown'
      After 'cleanup_unknown'

      It "returns 7 for unknown tool name"
        When call security.secret_scan.run "$TEST_WS"
        The status should equal 7
        The stderr should include "unknown security secret scan tool"
      End
    End

    Describe "Tier 3: auto-detect trufflehog fallback"
      setup_trufflehog_auto() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock.log"
        mock.create_logging "trufflehog" "$MOCK_LOG"
        # Build a PATH that has trufflehog but NOT gitleaks
        local cleaned_path=""
        local IFS=':'
        for dir in $_MOCK_ORIG_PATH; do
          [[ -x "${dir}/gitleaks" ]] && continue
          cleaned_path="${cleaned_path:+${cleaned_path}:}${dir}"
        done
        export PATH="${MOCK_BIN}:${cleaned_path}"
      }
      cleanup_trufflehog_auto() {
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_trufflehog_auto'
      After 'cleanup_trufflehog_auto'

      It "falls back to trufflehog when gitleaks absent"
        invoke_trufflehog_auto() {
          security.secret_scan.run "$TEST_WS" 2>/dev/null || return 1
          grep -q "trufflehog filesystem" "$MOCK_LOG"
        }
        When call invoke_trufflehog_auto
        The status should be success
      End
    End

    Describe "scan detects secrets"
      setup_fail_scan() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        mock.create_exit "gitleaks" 1
        mock.activate
      }
      cleanup_fail_scan() {
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_fail_scan'
      After 'cleanup_fail_scan'

      It "returns 10 when scanner finds secrets"
        When call security.secret_scan.run "$TEST_WS"
        The status should equal 10
        The stderr should include "security secret scan findings detected"
      End
    End

    Describe "Tier 3: auto-detect"
      setup_auto() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock.log"
        mock.create_logging "gitleaks" "$MOCK_LOG"
        mock.activate
      }
      cleanup_auto() {
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_auto'
      After 'cleanup_auto'

      It "auto-detects gitleaks"
        invoke_auto() {
          security.secret_scan.run "$TEST_WS" 2>/dev/null || return 1
          grep -q "gitleaks detect" "$MOCK_LOG"
        }
        When call invoke_auto
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

      It "skips when no tool available"
        When call security.secret_scan.run "$TEST_WS"
        The status should be success
        The stderr should include "no security secret scan tool available"
      End
    End
  End
End
