Describe "deploy/strategy.sh"
  Include "$BRIK_RUNTIME_LIB/logging.sh"
  Include "$BRIK_RUNTIME_LIB/tools.sh"
  Include "$BRIK_CORE_LIB/deploy/strategy.sh"
  Include "$BRIK_HOME/runtime/bash/spec/support/mock_helper.sh"

  # =========================================================================
  # deploy.strategy.rolling
  # =========================================================================
  Describe "deploy.strategy.rolling"
    It "returns 2 when no manifest or deployment name specified"
      When call deploy.strategy.rolling
      The status should equal 2
      The stderr should include "deployment name is required"
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
        When call deploy.strategy.rolling --deployment my-app
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
        invoke_rolling() {
          deploy.strategy.rolling --deployment my-app 2>/dev/null || return 1
          grep -q "rollout status" "$MOCK_LOG"
        }
        When call invoke_rolling
        The status should be success
      End

      It "uses default timeout 300s"
        invoke_default_timeout() {
          deploy.strategy.rolling --deployment my-app 2>/dev/null || return 1
          grep -q "300s" "$MOCK_LOG"
        }
        When call invoke_default_timeout
        The status should be success
      End

      It "respects --timeout option"
        invoke_timeout() {
          deploy.strategy.rolling --deployment my-app --timeout 60 2>/dev/null || return 1
          grep -q "60s" "$MOCK_LOG"
        }
        When call invoke_timeout
        The status should be success
      End

      It "passes --namespace to kubectl"
        invoke_namespace() {
          deploy.strategy.rolling --deployment my-app --namespace production 2>/dev/null || return 1
          grep -q "production" "$MOCK_LOG"
        }
        When call invoke_namespace
        The status should be success
      End

      It "succeeds and logs rollout status check"
        When call deploy.strategy.rolling --deployment my-app
        The status should be success
        The stderr should include "rolling"
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
        When call deploy.strategy.rolling --deployment my-app
        The status should be success
        The stderr should include "dry-run"
      End
    End
  End

  # =========================================================================
  # deploy.strategy.blue_green
  # =========================================================================
  Describe "deploy.strategy.blue_green"
    It "returns 2 when --service is missing"
      When call deploy.strategy.blue_green --namespace production
      The status should equal 2
      The stderr should include "service is required"
    End

    It "returns 2 when --target-selector is missing"
      When call deploy.strategy.blue_green --service my-svc
      The status should equal 2
      The stderr should include "target-selector is required"
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
        When call deploy.strategy.blue_green --service my-svc --target-selector version=green
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

      It "patches service selector for blue-green switch"
        invoke_patch() {
          deploy.strategy.blue_green --service my-svc --target-selector version=green 2>/dev/null || return 1
          grep -q "patch" "$MOCK_LOG"
        }
        When call invoke_patch
        The status should be success
      End

      It "passes --namespace to kubectl"
        invoke_namespace() {
          deploy.strategy.blue_green --service my-svc --target-selector version=green \
            --namespace staging 2>/dev/null || return 1
          grep -q "staging" "$MOCK_LOG"
        }
        When call invoke_namespace
        The status should be success
      End

      It "succeeds and logs the switch"
        When call deploy.strategy.blue_green --service my-svc --target-selector version=green
        The status should be success
        The stderr should include "blue-green"
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
        When call deploy.strategy.blue_green --service my-svc --target-selector version=green
        The status should be success
        The stderr should include "dry-run"
      End
    End
  End

  # =========================================================================
  # deploy.strategy.canary
  # =========================================================================
  Describe "deploy.strategy.canary"
    It "returns 2 when --service is missing"
      When call deploy.strategy.canary --namespace production
      The status should equal 2
      The stderr should include "service is required"
    End

    It "returns 2 when --deployment is missing"
      When call deploy.strategy.canary --service my-svc
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
        When call deploy.strategy.canary --service my-svc --deployment my-canary
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

      It "uses default replicas of 1"
        invoke_default_weight() {
          deploy.strategy.canary --service my-svc --deployment my-canary 2>/dev/null || return 1
          grep -q "1" "$MOCK_LOG"
        }
        When call invoke_default_weight
        The status should be success
      End

      It "respects --replicas option"
        invoke_weight() {
          deploy.strategy.canary --service my-svc --deployment my-canary --replicas 3 2>/dev/null || return 1
          grep -q "3" "$MOCK_LOG"
        }
        When call invoke_weight
        The status should be success
      End

      It "calls kubectl scale to set canary replicas"
        invoke_scale() {
          deploy.strategy.canary --service my-svc --deployment my-canary 2>/dev/null || return 1
          grep -q "scale" "$MOCK_LOG"
        }
        When call invoke_scale
        The status should be success
      End

      It "succeeds and logs canary deployment"
        When call deploy.strategy.canary --service my-svc --deployment my-canary
        The status should be success
        The stderr should include "canary"
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
        When call deploy.strategy.canary --service my-svc --deployment my-canary
        The status should be success
        The stderr should include "dry-run"
      End
    End
  End

  # =========================================================================
  # deploy.strategy.rolling - additional coverage
  # =========================================================================
  Describe "deploy.strategy.rolling - input validation"
    It "returns 2 for unknown option"
      When call deploy.strategy.rolling --badopt foo
      The status should equal 2
      The stderr should include "unknown option"
    End

    It "returns 2 for non-integer timeout"
      When call deploy.strategy.rolling --deployment my-app --timeout "abc"
      The status should equal 2
      The stderr should include "timeout must be a positive integer"
    End

    Describe "passthrough options"
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
        When call deploy.strategy.rolling --deployment my-app --target k8s --env staging
        The status should be success
        The stderr should include "rolling"
      End
    End
  End

  Describe "deploy.strategy.rolling - kubectl failure"
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
      When call deploy.strategy.rolling --deployment my-app
      The status should equal 5
      The stderr should include "rolling update check failed"
    End
  End

  # =========================================================================
  # deploy.strategy.blue_green - additional coverage
  # =========================================================================
  Describe "deploy.strategy.blue_green - selector validation"
    setup_bg_kubectl() {
      mock.setup
      TEST_WS="$(mktemp -d)"
      MOCK_LOG="${TEST_WS}/mock_kubectl.log"
      mock.create_logging "kubectl" "$MOCK_LOG"
      mock.activate
    }
    cleanup_bg_kubectl() {
      mock.cleanup
      rm -rf "$TEST_WS"
    }
    Before 'setup_bg_kubectl'
    After 'cleanup_bg_kubectl'

    It "returns 2 for invalid selector key"
      When call deploy.strategy.blue_green --service my-svc --target-selector "bad key=green"
      The status should equal 2
      The stderr should include "invalid selector key"
    End

    It "returns 2 for invalid selector value"
      When call deploy.strategy.blue_green --service my-svc --target-selector "version=bad value!"
      The status should equal 2
      The stderr should include "invalid selector value"
    End
  End

  Describe "deploy.strategy.blue_green - kubectl failure"
    setup_bg_fail() {
      mock.setup
      mock.create_exit "kubectl" 1
      mock.activate
      unset BRIK_DRY_RUN 2>/dev/null
    }
    cleanup_bg_fail() {
      mock.cleanup
      unset BRIK_DRY_RUN 2>/dev/null
    }
    Before 'setup_bg_fail'
    After 'cleanup_bg_fail'

    It "returns 5 when kubectl patch fails"
      When call deploy.strategy.blue_green --service my-svc --target-selector version=green
      The status should equal 5
      The stderr should include "blue-green switch failed"
    End
  End

  Describe "deploy.strategy.blue_green - passthrough options"
    setup_bg_pass() {
      mock.setup
      TEST_WS="$(mktemp -d)"
      MOCK_LOG="${TEST_WS}/mock_kubectl.log"
      mock.create_logging "kubectl" "$MOCK_LOG"
      mock.activate
    }
    cleanup_bg_pass() {
      mock.cleanup
      rm -rf "$TEST_WS"
    }
    Before 'setup_bg_pass'
    After 'cleanup_bg_pass'

    It "ignores --target and --env passthrough options"
      When call deploy.strategy.blue_green --service my-svc --target-selector version=green --target k8s --env staging
      The status should be success
      The stderr should include "blue-green"
    End
  End

  # =========================================================================
  # deploy.strategy.canary - additional coverage
  # =========================================================================
  Describe "deploy.strategy.canary - input validation"
    It "returns 2 for non-integer replicas"
      When call deploy.strategy.canary --service my-svc --deployment my-canary --replicas "abc"
      The status should equal 2
      The stderr should include "replicas must be a positive integer"
    End

    It "returns 2 for replicas of 0"
      When call deploy.strategy.canary --service my-svc --deployment my-canary --replicas 0
      The status should equal 2
      The stderr should include "replicas must be a positive integer"
    End

    It "returns 2 for unknown option"
      When call deploy.strategy.canary --badopt foo
      The status should equal 2
      The stderr should include "unknown option"
    End
  End

  Describe "deploy.strategy.canary - kubectl failure"
    setup_canary_fail() {
      mock.setup
      mock.create_exit "kubectl" 1
      mock.activate
      unset BRIK_DRY_RUN 2>/dev/null
    }
    cleanup_canary_fail() {
      mock.cleanup
      unset BRIK_DRY_RUN 2>/dev/null
    }
    Before 'setup_canary_fail'
    After 'cleanup_canary_fail'

    It "returns 5 when kubectl scale fails"
      When call deploy.strategy.canary --service my-svc --deployment my-canary
      The status should equal 5
      The stderr should include "canary scale failed"
    End
  End

  Describe "deploy.strategy.canary - namespace"
    setup_canary_ns() {
      mock.setup
      TEST_WS="$(mktemp -d)"
      MOCK_LOG="${TEST_WS}/mock_kubectl.log"
      mock.create_logging "kubectl" "$MOCK_LOG"
      mock.activate
    }
    cleanup_canary_ns() {
      mock.cleanup
      rm -rf "$TEST_WS"
    }
    Before 'setup_canary_ns'
    After 'cleanup_canary_ns'

    It "passes --namespace to kubectl"
      invoke_ns() {
        deploy.strategy.canary --service my-svc --deployment my-canary --namespace production 2>/dev/null || return 1
        grep -q "production" "$MOCK_LOG"
      }
      When call invoke_ns
      The status should be success
    End
  End

  Describe "deploy.strategy.canary - passthrough options"
    setup_canary_pass() {
      mock.setup
      TEST_WS="$(mktemp -d)"
      MOCK_LOG="${TEST_WS}/mock_kubectl.log"
      mock.create_logging "kubectl" "$MOCK_LOG"
      mock.activate
    }
    cleanup_canary_pass() {
      mock.cleanup
      rm -rf "$TEST_WS"
    }
    Before 'setup_canary_pass'
    After 'cleanup_canary_pass'

    It "ignores --target and --env passthrough options"
      When call deploy.strategy.canary --service my-svc --deployment my-canary --target k8s --env staging
      The status should be success
      The stderr should include "canary"
    End
  End

  # =========================================================================
  # double-sourcing guard
  # =========================================================================
  Describe "double-sourcing guard"
    It "is callable after double include"
      double_include() {
        # shellcheck source=/dev/null
        . "$BRIK_CORE_LIB/deploy/strategy.sh"
        declare -f deploy.strategy.rolling >/dev/null && echo "ok" || echo "missing"
      }
      When call double_include
      The output should equal "ok"
    End
  End
End
