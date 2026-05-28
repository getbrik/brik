Describe "security.sh"
  Include "$BRIK_PIPELINE_LIB/logging.sh"
  Include "$BRIK_PIPELINE_LIB/tools.sh"
  Include "$BRIK_HOME/lib/transverse/tools.sh"
  Include "$BRIK_HOME/lib/stages/verify/scan/scan.sh"

  # brik.use is called lazily; sub-modules are mocked in test setup
  brik.use() { :; }

  Describe "verify.scan.run"
    It "returns 6 for nonexistent workspace"
      When call verify.scan.run "/nonexistent/workspace"
      The status should equal 6
      The stderr should include "required directory not found"
    End

    Describe "unknown option"
      setup_ws() { TEST_WS="$(mktemp -d)"; }
      cleanup_ws() { rm -rf "$TEST_WS"; }
      Before 'setup_ws'
      After 'cleanup_ws'

      It "returns 2 for unknown option"
        When call verify.scan.run "$TEST_WS" --badopt foo
        The status should equal 2
        The stderr should include "unknown option"
      End
    End

    Describe "with empty --scans"
      setup_empty() { TEST_WS="$(mktemp -d)"; }
      cleanup_empty() { rm -rf "$TEST_WS"; }
      Before 'setup_empty'
      After 'cleanup_empty'

      It "succeeds with no scans"
        When call verify.scan.run "$TEST_WS" --scans ""
        The status should be success
        The stderr should include "0/0 scans passed"
      End
    End

    Describe "with mock security modules"
      setup_mocks() {
        TEST_WS="$(mktemp -d)"
        MOCK_DEPS_LOG="${TEST_WS}/deps_args.log"
        MOCK_SECRET_LOG="${TEST_WS}/secret_args.log"
        MOCK_CONTAINER_LOG="${TEST_WS}/container_args.log"
        MOCK_SAST_LOG="${TEST_WS}/sast_args.log"
        MOCK_LICENSE_LOG="${TEST_WS}/license_args.log"
        MOCK_IAC_LOG="${TEST_WS}/iac_args.log"
        eval "verify.scan.deps.run() { printf '%s\n' \"\$*\" > \"$MOCK_DEPS_LOG\"; return 0; }"
        eval "verify.scan.secret.run() { printf '%s\n' \"\$*\" > \"$MOCK_SECRET_LOG\"; return 0; }"
        eval "verify.scan.container.run() { printf '%s\n' \"\$*\" > \"$MOCK_CONTAINER_LOG\"; return 0; }"
        eval "verify.scan.sast.run() { printf '%s\n' \"\$*\" > \"$MOCK_SAST_LOG\"; return 0; }"
        eval "verify.scan.license.run() { printf '%s\n' \"\$*\" > \"$MOCK_LICENSE_LOG\"; return 0; }"
        eval "verify.scan.iac.run() { printf '%s\n' \"\$*\" > \"$MOCK_IAC_LOG\"; return 0; }"
      }
      cleanup_mocks() {
        unset -f verify.scan.deps.run verify.scan.secret.run verify.scan.container.run \
          verify.scan.sast.run verify.scan.license.run verify.scan.iac.run 2>/dev/null
        rm -rf "$TEST_WS"
      }
      Before 'setup_mocks'
      After 'cleanup_mocks'

      It "runs deps and secret scans by default (no --scans)"
        When call verify.scan.run "$TEST_WS"
        The status should be success
        The stderr should include "2/2 scans passed"
      End

      It "runs specified scans via --scans"
        When call verify.scan.run "$TEST_WS" --scans "deps,sast,iac"
        The status should be success
        The stderr should include "3/3 scans passed"
      End

      It "runs all six scans"
        When call verify.scan.run "$TEST_WS" --scans "deps,secret,sast,license,iac,container" --image "app:1.0"
        The status should be success
        The stderr should include "6/6 scans passed"
      End

      It "passes --severity to deps scan"
        invoke_check_severity() {
          verify.scan.run "$TEST_WS" --scans "deps" --severity critical 2>/dev/null || return 1
          grep -q "\-\-severity critical" "$MOCK_DEPS_LOG"
        }
        When call invoke_check_severity
        The status should be success
      End

      It "passes --image and --severity to container scan"
        invoke_check_container() {
          verify.scan.run "$TEST_WS" --scans "container" --image "webapp:2.0" --severity medium 2>/dev/null || return 1
          grep -q "\-\-image webapp:2.0" "$MOCK_CONTAINER_LOG" &&
          grep -q "\-\-severity medium" "$MOCK_CONTAINER_LOG"
        }
        When call invoke_check_container
        The status should be success
      End

      It "maps 'secret' to verify.scan.secret.run"
        invoke_check_secret() {
          verify.scan.run "$TEST_WS" --scans "secret" 2>/dev/null || return 1
          [[ -f "$MOCK_SECRET_LOG" ]]
        }
        When call invoke_check_secret
        The status should be success
      End
    End

    Describe "unknown scan name"
      setup_unknown() {
        TEST_WS="$(mktemp -d)"
        verify.scan.deps.run() { return 0; }
      }
      cleanup_unknown() {
        unset -f verify.scan.deps.run 2>/dev/null
        rm -rf "$TEST_WS"
      }
      Before 'setup_unknown'
      After 'cleanup_unknown'

      It "warns and skips unknown scan, continues others"
        When call verify.scan.run "$TEST_WS" --scans "deps,TYPO"
        The status should be success
        The stderr should include "unknown security scan: TYPO (skipping)"
        The stderr should include "1/1 scans passed"
      End
    End

    Describe "with failing scan"
      setup_fail() {
        TEST_WS="$(mktemp -d)"
        verify.scan.deps.run() { return 10; }
        verify.scan.secret.run() { return 0; }
      }
      cleanup_fail() {
        unset -f verify.scan.deps.run verify.scan.secret.run 2>/dev/null
        rm -rf "$TEST_WS"
      }
      Before 'setup_fail'
      After 'cleanup_fail'

      It "returns 10 when any scan fails"
        When call verify.scan.run "$TEST_WS" --scans "deps,secret"
        The status should equal 10
        The stderr should include "1 failed"
      End

      It "reports partial success"
        When call verify.scan.run "$TEST_WS" --scans "deps,secret"
        The status should equal 10
        The stderr should include "1/2 scans passed"
      End
    End

    Describe "module not available"
      setup_nomod() {
        TEST_WS="$(mktemp -d)"
      }
      cleanup_nomod() {
        rm -rf "$TEST_WS"
      }
      Before 'setup_nomod'
      After 'cleanup_nomod'

      It "warns when module function not found"
        When call verify.scan.run "$TEST_WS" --scans "deps"
        The status should be success
        The stderr should include "not available"
        The stderr should include "0/0 scans passed"
      End
    End
  End
End
