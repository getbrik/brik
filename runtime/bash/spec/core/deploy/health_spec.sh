Describe "deploy/health.sh"
  Include "$BRIK_RUNTIME_LIB/logging.sh"
  Include "$BRIK_RUNTIME_LIB/tools.sh"
  Include "$BRIK_CORE_LIB/deploy/health.sh"
  Include "$BRIK_HOME/runtime/bash/spec/support/mock_helper.sh"

  # =========================================================================
  # deploy.health.check
  # =========================================================================
  Describe "deploy.health.check"
    It "returns 2 when --url is missing"
      When call deploy.health.check
      The status should equal 2
      The stderr should include "url is required"
    End

    Describe "require_tool curl failure"
      setup_no_curl() {
        mock.setup
        mock.isolate
      }
      cleanup_no_curl() {
        mock.cleanup
      }
      Before 'setup_no_curl'
      After 'cleanup_no_curl'

      It "returns 3 when curl is not on PATH"
        When call deploy.health.check --url "http://example.com/health"
        The status should equal 3
        The stderr should include "required tool not found"
      End
    End

    Describe "with mock curl returning 200"
      setup_curl_200() {
        mock.setup
        mock.create_output "curl" "200"
        mock.activate
      }
      cleanup_curl_200() {
        mock.cleanup
      }
      Before 'setup_curl_200'
      After 'cleanup_curl_200'

      It "returns 0 when status matches expected 200"
        invoke_check_200() { deploy.health.check --url "http://example.com/health" 2>/dev/null; }
        When call invoke_check_200
        The status should be success
      End

      It "returns 0 with explicit --expected-status 200"
        invoke_check_explicit() { deploy.health.check --url "http://example.com/health" --expected-status 200 2>/dev/null; }
        When call invoke_check_explicit
        The status should be success
      End
    End

    Describe "with mock curl returning 503"
      setup_curl_503() {
        mock.setup
        mock.create_output "curl" "503"
        mock.activate
      }
      cleanup_curl_503() {
        mock.cleanup
      }
      Before 'setup_curl_503'
      After 'cleanup_curl_503'

      It "returns 1 when status does not match expected"
        invoke_check_503() { deploy.health.check --url "http://example.com/health" 2>/dev/null; }
        When call invoke_check_503
        The status should equal 1
      End
    End

    Describe "with mock curl returning 201"
      setup_curl_201() {
        mock.setup
        mock.create_output "curl" "201"
        mock.activate
      }
      cleanup_curl_201() {
        mock.cleanup
      }
      Before 'setup_curl_201'
      After 'cleanup_curl_201'

      It "returns 0 when status matches custom --expected-status 201"
        invoke_check_201() { deploy.health.check --url "http://example.com/health" --expected-status 201 2>/dev/null; }
        When call invoke_check_201
        The status should be success
      End

      It "returns 1 when status does not match custom --expected-status 200"
        invoke_check_mismatch() { deploy.health.check --url "http://example.com/health" --expected-status 200 2>/dev/null; }
        When call invoke_check_mismatch
        The status should equal 1
      End
    End
  End

  # =========================================================================
  # deploy.health.wait
  # =========================================================================
  Describe "deploy.health.wait"
    It "returns 2 when --url is missing"
      When call deploy.health.wait
      The status should equal 2
      The stderr should include "url is required"
    End

    Describe "with mock curl always returning 200 (immediate success)"
      setup_curl_200() {
        mock.setup
        mock.create_output "curl" "200"
        mock.activate
      }
      cleanup_curl_200() {
        mock.cleanup
        unset BRIK_DRY_RUN 2>/dev/null
      }
      Before 'setup_curl_200'
      After 'cleanup_curl_200'

      It "returns 0 when healthy before timeout"
        invoke_wait_200() { deploy.health.wait --url "http://example.com/health" --timeout 10 --interval 1 2>/dev/null; }
        When call invoke_wait_200
        The status should be success
      End

      It "succeeds and logs health check"
        When call deploy.health.wait --url "http://example.com/health" --timeout 10 --interval 1
        The status should be success
        The stderr should include "health"
      End
    End

    Describe "with mock curl always returning 503 (timeout scenario)"
      setup_curl_503() {
        mock.setup
        mock.create_output "curl" "503"
        mock.activate
      }
      cleanup_curl_503() {
        mock.cleanup
      }
      Before 'setup_curl_503'
      After 'cleanup_curl_503'

      It "returns 1 when timeout is reached without healthy response"
        # Use very short timeout to avoid slow tests
        When call deploy.health.wait --url "http://example.com/health" --timeout 2 --interval 1
        The status should equal 1
        The stderr should include "timeout"
      End
    End

    Describe "dry-run mode"
      setup_dryrun() {
        mock.setup
        mock.create_output "curl" "200"
        mock.activate
        export BRIK_DRY_RUN="true"
      }
      cleanup_dryrun() {
        mock.cleanup
        unset BRIK_DRY_RUN 2>/dev/null
      }
      Before 'setup_dryrun'
      After 'cleanup_dryrun'

      It "logs dry-run message without polling"
        When call deploy.health.wait --url "http://example.com/health"
        The status should be success
        The stderr should include "dry-run"
      End
    End
  End

  # =========================================================================
  # deploy.health.k8s_wait
  # =========================================================================
  Describe "deploy.health.k8s_wait"
    It "returns 2 when --namespace is missing"
      When call deploy.health.k8s_wait --deployment my-app
      The status should equal 2
      The stderr should include "namespace is required"
    End

    It "returns 2 when --deployment is missing"
      When call deploy.health.k8s_wait --namespace production
      The status should equal 2
      The stderr should include "deployment is required"
    End

    Describe "require_tool kubectl failure"
      setup_no_kubectl() {
        mock.setup
        mock.isolate
      }
      cleanup_no_kubectl() {
        mock.cleanup
      }
      Before 'setup_no_kubectl'
      After 'cleanup_no_kubectl'

      It "returns 3 when kubectl is not on PATH"
        When call deploy.health.k8s_wait --namespace production --deployment my-app
        The status should equal 3
        The stderr should include "required tool not found"
      End
    End

    Describe "with mock kubectl"
      setup_kubectl() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_kubectl.log"
        mock.create_logging "kubectl" "$MOCK_LOG"
        mock.activate
      }
      cleanup_kubectl() {
        mock.cleanup
        unset BRIK_DRY_RUN 2>/dev/null
        rm -rf "$TEST_WS"
      }
      Before 'setup_kubectl'
      After 'cleanup_kubectl'

      It "calls kubectl rollout status"
        invoke_k8s_wait() {
          deploy.health.k8s_wait --namespace production --deployment my-app 2>/dev/null || return 1
          grep -q "rollout status" "$MOCK_LOG"
        }
        When call invoke_k8s_wait
        The status should be success
      End

      It "uses default timeout 300s"
        invoke_default_timeout() {
          deploy.health.k8s_wait --namespace production --deployment my-app 2>/dev/null || return 1
          grep -q "300s" "$MOCK_LOG"
        }
        When call invoke_default_timeout
        The status should be success
      End

      It "passes namespace to kubectl"
        invoke_namespace() {
          deploy.health.k8s_wait --namespace production --deployment my-app 2>/dev/null || return 1
          grep -q "production" "$MOCK_LOG"
        }
        When call invoke_namespace
        The status should be success
      End

      It "succeeds and logs wait completion"
        When call deploy.health.k8s_wait --namespace production --deployment my-app
        The status should be success
        The stderr should include "rollout"
      End
    End

    Describe "dry-run mode"
      setup_dryrun() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_kubectl.log"
        mock.create_logging "kubectl" "$MOCK_LOG"
        mock.activate
        export BRIK_DRY_RUN="true"
      }
      cleanup_dryrun() {
        mock.cleanup
        unset BRIK_DRY_RUN 2>/dev/null
        rm -rf "$TEST_WS"
      }
      Before 'setup_dryrun'
      After 'cleanup_dryrun'

      It "logs dry-run message without executing kubectl"
        When call deploy.health.k8s_wait --namespace production --deployment my-app
        The status should be success
        The stderr should include "dry-run"
      End
    End
  End

  # =========================================================================
  # deploy.health.check - additional coverage
  # =========================================================================
  Describe "deploy.health.check - input validation"
    It "returns 2 for unknown option"
      When call deploy.health.check --badopt foo
      The status should equal 2
      The stderr should include "unknown option"
    End

    It "returns 2 for invalid URL scheme (ftp)"
      When call deploy.health.check --url "ftp://example.com/health"
      The status should equal 2
      The stderr should include "http or https"
    End

    It "returns 2 for invalid expected-status (non-3-digit)"
      When call deploy.health.check --url "http://example.com/health" --expected-status "abc"
      The status should equal 2
      The stderr should include "3-digit"
    End

    It "returns 2 for expected-status with too few digits"
      When call deploy.health.check --url "http://example.com/health" --expected-status "20"
      The status should equal 2
      The stderr should include "3-digit"
    End

    Describe "dry-run mode"
      It "logs dry-run message and returns 0"
        When call deploy.health.check --url "http://example.com/health" --dry-run
        The status should be success
        The stderr should include "dry-run"
      End
    End
  End

  # =========================================================================
  # deploy.health.wait - input validation
  # =========================================================================
  Describe "deploy.health.wait - input validation"
    It "returns 2 for unknown option"
      When call deploy.health.wait --badopt foo
      The status should equal 2
      The stderr should include "unknown option"
    End

    It "returns 2 for invalid URL scheme"
      When call deploy.health.wait --url "ftp://example.com/health"
      The status should equal 2
      The stderr should include "http or https"
    End

    It "returns 2 for non-integer timeout"
      When call deploy.health.wait --url "http://example.com/health" --timeout "abc"
      The status should equal 2
      The stderr should include "timeout must be a positive integer"
    End

    It "returns 2 for non-integer interval"
      When call deploy.health.wait --url "http://example.com/health" --interval "abc"
      The status should equal 2
      The stderr should include "interval must be a positive integer"
    End

    It "returns 2 for interval of 0"
      When call deploy.health.wait --url "http://example.com/health" --interval 0
      The status should equal 2
      The stderr should include "interval must be a positive integer"
    End

    It "returns 2 for invalid expected-status in wait"
      When call deploy.health.wait --url "http://example.com/health" --expected-status "abc"
      The status should equal 2
      The stderr should include "3-digit"
    End
  End

  Describe "deploy.health.wait - require_tool failure"
    setup_no_curl_wait() {
      mock.setup
      mock.isolate
    }
    cleanup_no_curl_wait() {
      mock.cleanup
    }
    Before 'setup_no_curl_wait'
    After 'cleanup_no_curl_wait'

    It "returns 3 when curl is not on PATH"
      When call deploy.health.wait --url "http://example.com/health"
      The status should equal 3
      The stderr should include "required tool not found"
    End
  End

  Describe "deploy.health.wait - --dry-run flag"
    setup_dryrun_flag() {
      mock.setup
      mock.create_output "curl" "200"
      mock.activate
    }
    cleanup_dryrun_flag() {
      mock.cleanup
      unset BRIK_DRY_RUN 2>/dev/null
    }
    Before 'setup_dryrun_flag'
    After 'cleanup_dryrun_flag'

    It "logs dry-run message with --dry-run flag (not env)"
      When call deploy.health.wait --url "http://example.com/health" --dry-run
      The status should be success
      The stderr should include "dry-run"
    End
  End

  # =========================================================================
  # deploy.health.k8s_wait - input validation
  # =========================================================================
  Describe "deploy.health.k8s_wait - input validation"
    It "returns 2 for unknown option"
      When call deploy.health.k8s_wait --badopt foo
      The status should equal 2
      The stderr should include "unknown option"
    End

    It "returns 2 for non-integer timeout"
      When call deploy.health.k8s_wait --namespace production --deployment my-app --timeout "abc"
      The status should equal 2
      The stderr should include "timeout must be a positive integer"
    End
  End

  Describe "deploy.health.k8s_wait - custom timeout"
    setup_kubectl_timeout() {
      mock.setup
      TEST_WS="$(mktemp -d)"
      MOCK_LOG="${TEST_WS}/mock_kubectl.log"
      mock.create_logging "kubectl" "$MOCK_LOG"
      mock.activate
    }
    cleanup_kubectl_timeout() {
      mock.cleanup
      rm -rf "$TEST_WS"
    }
    Before 'setup_kubectl_timeout'
    After 'cleanup_kubectl_timeout'

    It "passes custom timeout to kubectl"
      invoke_custom_timeout() {
        deploy.health.k8s_wait --namespace production --deployment my-app --timeout 60 2>/dev/null || return 1
        grep -q "60s" "$MOCK_LOG"
      }
      When call invoke_custom_timeout
      The status should be success
    End
  End

  Describe "deploy.health.k8s_wait - kubectl failure"
    setup_kubectl_fail() {
      mock.setup
      mock.create_exit "kubectl" 1
      mock.activate
    }
    cleanup_kubectl_fail() {
      mock.cleanup
      unset BRIK_DRY_RUN 2>/dev/null
    }
    Before 'setup_kubectl_fail'
    After 'cleanup_kubectl_fail'

    It "returns 5 when kubectl rollout status fails"
      When call deploy.health.k8s_wait --namespace production --deployment my-app
      The status should equal 5
      The stderr should include "rollout status check failed"
    End
  End

  Describe "deploy.health.k8s_wait - passthrough options"
    setup_kubectl_pass() {
      mock.setup
      TEST_WS="$(mktemp -d)"
      MOCK_LOG="${TEST_WS}/mock_kubectl.log"
      mock.create_logging "kubectl" "$MOCK_LOG"
      mock.activate
    }
    cleanup_kubectl_pass() {
      mock.cleanup
      rm -rf "$TEST_WS"
    }
    Before 'setup_kubectl_pass'
    After 'cleanup_kubectl_pass'

    It "ignores --target and --env passthrough options"
      When call deploy.health.k8s_wait --namespace production --deployment my-app --target k8s --env staging
      The status should be success
      The stderr should include "rollout"
    End
  End

  # =========================================================================
  # double-sourcing guard
  # =========================================================================
  Describe "double-sourcing guard"
    It "is callable after double include"
      double_include() {
        # shellcheck source=/dev/null
        . "$BRIK_CORE_LIB/deploy/health.sh"
        declare -f deploy.health.check >/dev/null && echo "ok" || echo "missing"
      }
      When call double_include
      The output should equal "ok"
    End
  End
End
