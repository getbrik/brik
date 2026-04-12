Describe "deploy/strategy.sh"
  Include "$BRIK_RUNTIME_LIB/logging.sh"
  Include "$BRIK_RUNTIME_LIB/tools.sh"
  Include "$BRIK_CORE_LIB/deploy/strategy.sh"
  Include "$BRIK_HOME/runtime/bash/spec/support/mock_helper.sh"

  # =========================================================================
  # deploy.strategy.run - input validation
  # =========================================================================
  Describe "deploy.strategy.run"
    It "returns 2 when --type is missing"
      When call deploy.strategy.run --deploy-fn "echo hello"
      The status should equal 2
      The stderr should include "type is required"
    End

    It "returns 2 for unknown strategy type"
      When call deploy.strategy.run --type rainbow --deploy-fn "echo hello"
      The status should equal 2
      The stderr should include "unknown strategy type"
    End

    It "returns 2 when --deploy-fn is missing"
      When call deploy.strategy.run --type rolling
      The status should equal 2
      The stderr should include "deploy-fn is required"
    End

    It "returns 2 when deploy-fn is not a declared function"
      When call deploy.strategy.run --type rolling --deploy-fn "nonexistent_func arg1"
      The status should equal 2
      The stderr should include "not a declared function"
    End

    It "returns 2 when rollback-fn is not a declared function"
      my_deploy_fn() { return 0; }
      When call deploy.strategy.run --type rolling --deploy-fn "my_deploy_fn" --rollback-fn "nonexistent_rollback"
      The status should equal 2
      The stderr should include "not a declared function"
    End

    It "returns 2 for unknown option"
      When call deploy.strategy.run --badopt foo
      The status should equal 2
      The stderr should include "unknown option"
    End
  End

  # =========================================================================
  # deploy.strategy.run - rolling strategy
  # =========================================================================
  Describe "deploy.strategy.run - rolling"
    Describe "successful deploy"
      # Define test functions available in spec context
      test_deploy_ok() { log.info "test deploy called with: $*"; return 0; }

      It "calls deploy-fn and succeeds"
        When call deploy.strategy.run --type rolling --deploy-fn "test_deploy_ok --app my-app"
        The status should be success
        The stderr should include "rolling deployment completed"
      End

      It "passes args from deploy-fn string"
        When call deploy.strategy.run --type rolling --deploy-fn "test_deploy_ok --app my-app --flag"
        The status should be success
        The stderr should include "test deploy called with: --app my-app --flag"
      End
    End

    Describe "deploy failure without rollback"
      test_deploy_fail() { return 1; }

      It "returns 1 when deploy fails and no rollback-fn"
        When call deploy.strategy.run --type rolling --deploy-fn "test_deploy_fail"
        The status should equal 1
        The stderr should include "deploy failed"
        The stderr should include "no rollback-fn provided"
      End
    End

    Describe "deploy failure with successful rollback"
      test_deploy_fail2() { return 1; }
      test_rollback_ok() { log.info "rollback executed"; return 0; }

      It "returns 5 when deploy fails but rollback succeeds"
        When call deploy.strategy.run --type rolling --deploy-fn "test_deploy_fail2" --rollback-fn "test_rollback_ok"
        The status should equal 5
        The stderr should include "deploy failed"
        The stderr should include "rollback succeeded"
      End
    End

    Describe "deploy failure with failed rollback"
      test_deploy_fail3() { return 1; }
      test_rollback_fail() { return 1; }

      It "returns 1 when both deploy and rollback fail"
        When call deploy.strategy.run --type rolling --deploy-fn "test_deploy_fail3" --rollback-fn "test_rollback_fail"
        The status should equal 1
        The stderr should include "deploy failed"
        The stderr should include "rollback also failed"
      End
    End

    Describe "dry-run mode"
      test_deploy_dryrun() { return 0; }

      It "logs dry-run message"
        When call deploy.strategy.run --type rolling --deploy-fn "test_deploy_dryrun --app my-app" --dry-run
        The status should be success
        The stderr should include "dry-run"
        The stderr should include "strategy=rolling"
      End
    End
  End

  # =========================================================================
  # deploy.strategy.run - blue-green strategy
  # =========================================================================
  Describe "deploy.strategy.run - blue-green"
    test_bg_deploy() { return 0; }

    It "calls deploy-fn and succeeds"
      When call deploy.strategy.run --type blue-green --deploy-fn "test_bg_deploy"
      The status should be success
      The stderr should include "blue-green deployment completed"
    End
  End

  # =========================================================================
  # deploy.strategy.run - canary strategy
  # =========================================================================
  Describe "deploy.strategy.run - canary"
    test_canary_deploy() { return 0; }

    It "calls deploy-fn and succeeds"
      When call deploy.strategy.run --type canary --deploy-fn "test_canary_deploy"
      The status should be success
      The stderr should include "canary deployment completed"
    End
  End

  # =========================================================================
  # deploy.strategy.run - passthrough options
  # =========================================================================
  Describe "deploy.strategy.run - passthrough"
    test_pass_deploy() { return 0; }

    It "ignores --target and --env"
      When call deploy.strategy.run --type rolling --deploy-fn "test_pass_deploy" --target k8s --env staging
      The status should be success
      The stderr should include "rolling deployment completed"
    End
  End

  # =========================================================================
  # deploy.strategy.run - BRIK_DRY_RUN env var
  # =========================================================================
  Describe "deploy.strategy.run - BRIK_DRY_RUN env"
    setup_env_dryrun() { export BRIK_DRY_RUN="true"; }
    cleanup_env_dryrun() { unset BRIK_DRY_RUN 2>/dev/null; }
    Before 'setup_env_dryrun'
    After 'cleanup_env_dryrun'

    test_env_deploy() { return 0; }

    It "respects BRIK_DRY_RUN env var"
      When call deploy.strategy.run --type rolling --deploy-fn "test_env_deploy"
      The status should be success
      The stderr should include "dry-run"
    End
  End

  # =========================================================================
  # _deploy.strategy._rolling_kubectl
  # =========================================================================
  Describe "_deploy.strategy._rolling_kubectl"
    It "returns 2 when --deployment is missing"
      When call _deploy.strategy._rolling_kubectl
      The status should equal 2
      The stderr should include "deployment name is required"
    End

    It "returns 2 for non-integer timeout"
      When call _deploy.strategy._rolling_kubectl --deployment my-app --timeout "abc"
      The status should equal 2
      The stderr should include "timeout must be a positive integer"
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
        When call _deploy.strategy._rolling_kubectl --deployment my-app
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
          _deploy.strategy._rolling_kubectl --deployment my-app 2>/dev/null || return 1
          grep -q "rollout status" "$MOCK_LOG"
        }
        When call invoke_rolling
        The status should be success
      End

      It "uses default timeout 300s"
        invoke_default_timeout() {
          _deploy.strategy._rolling_kubectl --deployment my-app 2>/dev/null || return 1
          grep -q "300s" "$MOCK_LOG"
        }
        When call invoke_default_timeout
        The status should be success
      End

      It "respects --timeout option"
        invoke_timeout() {
          _deploy.strategy._rolling_kubectl --deployment my-app --timeout 60 2>/dev/null || return 1
          grep -q "60s" "$MOCK_LOG"
        }
        When call invoke_timeout
        The status should be success
      End

      It "succeeds and logs rollout status check"
        When call _deploy.strategy._rolling_kubectl --deployment my-app
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
        When call _deploy.strategy._rolling_kubectl --deployment my-app
        The status should be success
        The stderr should include "dry-run"
      End
    End

    Describe "kubectl failure"
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
        When call _deploy.strategy._rolling_kubectl --deployment my-app
        The status should equal 5
        The stderr should include "rolling update check failed"
      End
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
        When call _deploy.strategy._rolling_kubectl --deployment my-app --target k8s --env staging
        The status should be success
        The stderr should include "rolling"
      End
    End
  End

  # =========================================================================
  # _deploy.strategy._blue_green_kubectl
  # =========================================================================
  Describe "_deploy.strategy._blue_green_kubectl"
    It "returns 2 when --service is missing"
      When call _deploy.strategy._blue_green_kubectl --namespace production
      The status should equal 2
      The stderr should include "service is required"
    End

    It "returns 2 when --target-selector is missing"
      When call _deploy.strategy._blue_green_kubectl --service my-svc
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
        When call _deploy.strategy._blue_green_kubectl --service my-svc --target-selector version=green
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
          _deploy.strategy._blue_green_kubectl --service my-svc --target-selector version=green 2>/dev/null || return 1
          grep -q "patch" "$MOCK_LOG"
        }
        When call invoke_patch
        The status should be success
      End

      It "passes --namespace to kubectl"
        invoke_namespace() {
          _deploy.strategy._blue_green_kubectl --service my-svc --target-selector version=green \
            --namespace staging 2>/dev/null || return 1
          grep -q "staging" "$MOCK_LOG"
        }
        When call invoke_namespace
        The status should be success
      End

      It "succeeds and logs the switch"
        When call _deploy.strategy._blue_green_kubectl --service my-svc --target-selector version=green
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
        When call _deploy.strategy._blue_green_kubectl --service my-svc --target-selector version=green
        The status should be success
        The stderr should include "dry-run"
      End
    End

    Describe "selector validation"
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
        When call _deploy.strategy._blue_green_kubectl --service my-svc --target-selector "bad key=green"
        The status should equal 2
        The stderr should include "invalid selector key"
      End

      It "returns 2 for invalid selector value"
        When call _deploy.strategy._blue_green_kubectl --service my-svc --target-selector "version=bad value!"
        The status should equal 2
        The stderr should include "invalid selector value"
      End
    End

    Describe "kubectl failure"
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
        When call _deploy.strategy._blue_green_kubectl --service my-svc --target-selector version=green
        The status should equal 5
        The stderr should include "blue-green switch failed"
      End
    End

    Describe "passthrough options"
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
        When call _deploy.strategy._blue_green_kubectl --service my-svc --target-selector version=green --target k8s --env staging
        The status should be success
        The stderr should include "blue-green"
      End
    End
  End

  # =========================================================================
  # _deploy.strategy._canary_kubectl
  # =========================================================================
  Describe "_deploy.strategy._canary_kubectl"
    It "returns 2 when --service is missing"
      When call _deploy.strategy._canary_kubectl --namespace production
      The status should equal 2
      The stderr should include "service is required"
    End

    It "returns 2 when --deployment is missing"
      When call _deploy.strategy._canary_kubectl --service my-svc
      The status should equal 2
      The stderr should include "deployment is required"
    End

    It "returns 2 for non-integer replicas"
      When call _deploy.strategy._canary_kubectl --service my-svc --deployment my-canary --replicas "abc"
      The status should equal 2
      The stderr should include "replicas must be a positive integer"
    End

    It "returns 2 for replicas of 0"
      When call _deploy.strategy._canary_kubectl --service my-svc --deployment my-canary --replicas 0
      The status should equal 2
      The stderr should include "replicas must be a positive integer"
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
        When call _deploy.strategy._canary_kubectl --service my-svc --deployment my-canary
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
          _deploy.strategy._canary_kubectl --service my-svc --deployment my-canary 2>/dev/null || return 1
          grep -q "1" "$MOCK_LOG"
        }
        When call invoke_default_weight
        The status should be success
      End

      It "respects --replicas option"
        invoke_weight() {
          _deploy.strategy._canary_kubectl --service my-svc --deployment my-canary --replicas 3 2>/dev/null || return 1
          grep -q "3" "$MOCK_LOG"
        }
        When call invoke_weight
        The status should be success
      End

      It "calls kubectl scale to set canary replicas"
        invoke_scale() {
          _deploy.strategy._canary_kubectl --service my-svc --deployment my-canary 2>/dev/null || return 1
          grep -q "scale" "$MOCK_LOG"
        }
        When call invoke_scale
        The status should be success
      End

      It "passes --namespace to kubectl"
        invoke_ns() {
          _deploy.strategy._canary_kubectl --service my-svc --deployment my-canary --namespace production 2>/dev/null || return 1
          grep -q "production" "$MOCK_LOG"
        }
        When call invoke_ns
        The status should be success
      End

      It "succeeds and logs canary deployment"
        When call _deploy.strategy._canary_kubectl --service my-svc --deployment my-canary
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
        When call _deploy.strategy._canary_kubectl --service my-svc --deployment my-canary
        The status should be success
        The stderr should include "dry-run"
      End
    End

    Describe "kubectl failure"
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
        When call _deploy.strategy._canary_kubectl --service my-svc --deployment my-canary
        The status should equal 5
        The stderr should include "canary scale failed"
      End
    End

    Describe "passthrough options"
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
        When call _deploy.strategy._canary_kubectl --service my-svc --deployment my-canary --target k8s --env staging
        The status should be success
        The stderr should include "canary"
      End
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
        declare -f deploy.strategy.run >/dev/null && echo "ok" || echo "missing"
      }
      When call double_include
      The output should equal "ok"
    End
  End
End
