Describe "security.sh"
  Include "$BRIK_RUNTIME_LIB/logging.sh"
  Include "$BRIK_RUNTIME_LIB/tools.sh"
  Include "$BRIK_CORE_LIB/quality/_tools.sh"
  Include "$BRIK_CORE_LIB/security.sh"

  # brik.use is called lazily; sub-modules are mocked in test setup
  brik.use() { :; }

  Describe "security.run"
    It "returns 6 for nonexistent workspace"
      When call security.run "/nonexistent/workspace"
      The status should equal 6
      The stderr should include "required directory not found"
    End

    Describe "unknown option"
      setup_ws() { TEST_WS="$(mktemp -d)"; }
      cleanup_ws() { rm -rf "$TEST_WS"; }
      Before 'setup_ws'
      After 'cleanup_ws'

      It "returns 2 for unknown option"
        When call security.run "$TEST_WS" --badopt foo
        The status should equal 2
        The stderr should include "unknown option"
      End
    End

    Describe "with all scans disabled"
      setup_none() { TEST_WS="$(mktemp -d)"; }
      cleanup_none() { rm -rf "$TEST_WS"; }
      Before 'setup_none'
      After 'cleanup_none'

      It "succeeds when all scans disabled"
        When call security.run "$TEST_WS" --dependency-scan false --secret-scan false --container-scan false
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
        eval "security.deps.run() { printf '%s\n' \"\$*\" > \"$MOCK_DEPS_LOG\"; return 0; }"
        eval "security.secret_scan.run() { printf '%s\n' \"\$*\" > \"$MOCK_SECRET_LOG\"; return 0; }"
        eval "security.container.run() { printf '%s\n' \"\$*\" > \"$MOCK_CONTAINER_LOG\"; return 0; }"
      }
      cleanup_mocks() {
        unset -f security.deps.run security.secret_scan.run security.container.run 2>/dev/null
        rm -rf "$TEST_WS"
      }
      Before 'setup_mocks'
      After 'cleanup_mocks'

      It "runs dependency and secret scans by default"
        When call security.run "$TEST_WS"
        The status should be success
        The stderr should include "2/2 scans passed"
      End

      It "runs all three scans when container scan enabled"
        When call security.run "$TEST_WS" --container-scan true --image "myapp:1.0"
        The status should be success
        The stderr should include "3/3 scans passed"
      End

      It "passes --severity to deps scan"
        invoke_check_severity() {
          security.run "$TEST_WS" --severity critical 2>/dev/null || return 1
          grep -q "\-\-severity critical" "$MOCK_DEPS_LOG"
        }
        When call invoke_check_severity
        The status should be success
      End

      It "passes --image to container scan"
        invoke_check_image() {
          security.run "$TEST_WS" --container-scan true --image "webapp:2.0" 2>/dev/null || return 1
          grep -q "\-\-image webapp:2.0" "$MOCK_CONTAINER_LOG"
        }
        When call invoke_check_image
        The status should be success
      End

      It "delegates to security.secret_scan.run"
        invoke_check_secret() {
          security.run "$TEST_WS" 2>/dev/null || return 1
          [[ -f "$MOCK_SECRET_LOG" ]]
        }
        When call invoke_check_secret
        The status should be success
      End
    End

    Describe "selective disable: only deps"
      setup_selective() {
        TEST_WS="$(mktemp -d)"
        security.deps.run() { return 0; }
        security.secret_scan.run() { return 0; }
      }
      cleanup_selective() {
        unset -f security.deps.run security.secret_scan.run 2>/dev/null
        rm -rf "$TEST_WS"
      }
      Before 'setup_selective'
      After 'cleanup_selective'

      It "runs only secret scan when deps disabled"
        When call security.run "$TEST_WS" --dependency-scan false
        The status should be success
        The stderr should include "1/1 scans passed"
      End
    End

    Describe "with failing scan"
      setup_fail() {
        TEST_WS="$(mktemp -d)"
        security.deps.run() { return 10; }
        security.secret_scan.run() { return 0; }
      }
      cleanup_fail() {
        unset -f security.deps.run security.secret_scan.run 2>/dev/null
        rm -rf "$TEST_WS"
      }
      Before 'setup_fail'
      After 'cleanup_fail'

      It "returns 10 when any scan fails"
        When call security.run "$TEST_WS"
        The status should equal 10
        The stderr should include "1 failed"
      End

      It "reports partial success"
        When call security.run "$TEST_WS"
        The status should equal 10
        The stderr should include "1/2 scans passed"
      End
    End
  End
End
