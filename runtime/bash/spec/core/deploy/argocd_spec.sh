Describe "deploy/argocd.sh"
  Include "$BRIK_RUNTIME_LIB/logging.sh"
  Include "$BRIK_RUNTIME_LIB/tools.sh"
  Include "$BRIK_CORE_LIB/deploy/argocd.sh"
  Include "$BRIK_HOME/runtime/bash/spec/support/mock_helper.sh"

  # ---------------------------------------------------------------------------
  # deploy.argocd.sync
  # ---------------------------------------------------------------------------
  Describe "deploy.argocd.sync"
    It "returns 2 when app_name is missing"
      When call deploy.argocd.sync
      The status should equal 2
      The stderr should include "app_name is required"
    End

    Describe "require_tool argocd failure"
      setup_no_argocd() {
        mock.setup
        mock.isolate
      }
      cleanup_no_argocd() {
        mock.cleanup
      }
      Before 'setup_no_argocd'
      After 'cleanup_no_argocd'

      It "returns 3 when argocd is not on PATH"
        When call deploy.argocd.sync my-app
        The status should equal 3
        The stderr should include "required tool not found"
      End
    End

    Describe "with mock argocd"
      setup_argocd_sync() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_argocd.log"
        mock.create_logging "argocd" "$MOCK_LOG"
        mock.activate
        unset BRIK_DRY_RUN 2>/dev/null
      }
      cleanup_argocd_sync() {
        mock.cleanup
        unset BRIK_DRY_RUN 2>/dev/null
        rm -rf "$TEST_WS"
      }
      Before 'setup_argocd_sync'
      After 'cleanup_argocd_sync'

      It "calls argocd app sync with app_name"
        invoke_sync() {
          deploy.argocd.sync my-app 2>/dev/null || return 1
          grep -q "app sync my-app" "$MOCK_LOG"
        }
        When call invoke_sync
        The status should be success
      End

      It "succeeds and logs sync started"
        When call deploy.argocd.sync my-app
        The status should be success
        The stderr should include "my-app"
      End
    End

    Describe "dry-run mode"
      setup_dryrun_sync() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_argocd.log"
        mock.create_logging "argocd" "$MOCK_LOG"
        mock.activate
        export BRIK_DRY_RUN="true"
      }
      cleanup_dryrun_sync() {
        mock.cleanup
        unset BRIK_DRY_RUN 2>/dev/null
        rm -rf "$TEST_WS"
      }
      Before 'setup_dryrun_sync'
      After 'cleanup_dryrun_sync'

      It "logs dry-run message without executing argocd"
        invoke_dryrun() {
          deploy.argocd.sync my-app 2>/dev/null
          # argocd must NOT have been called (log file will not have sync entry)
          ! grep -q "app sync" "$MOCK_LOG" 2>/dev/null
        }
        When call invoke_dryrun
        The status should be success
      End

      It "prints dry-run indicator in output"
        When call deploy.argocd.sync my-app
        The status should be success
        The stderr should include "dry-run"
      End
    End
  End

  # ---------------------------------------------------------------------------
  # deploy.argocd.wait_healthy
  # ---------------------------------------------------------------------------
  Describe "deploy.argocd.wait_healthy"
    It "returns 2 when app_name is missing"
      When call deploy.argocd.wait_healthy
      The status should equal 2
      The stderr should include "app_name is required"
    End

    Describe "with mock argocd"
      setup_argocd_wait() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_argocd.log"
        mock.create_logging "argocd" "$MOCK_LOG"
        mock.activate
        unset BRIK_DRY_RUN 2>/dev/null
      }
      cleanup_argocd_wait() {
        mock.cleanup
        unset BRIK_DRY_RUN 2>/dev/null
        rm -rf "$TEST_WS"
      }
      Before 'setup_argocd_wait'
      After 'cleanup_argocd_wait'

      It "calls argocd app wait --health with default timeout 300"
        invoke_wait_default() {
          deploy.argocd.wait_healthy my-app 2>/dev/null || return 1
          grep -q "app wait my-app" "$MOCK_LOG" &&
          grep -q "\-\-timeout 300" "$MOCK_LOG"
        }
        When call invoke_wait_default
        The status should be success
      End

      It "passes --health flag"
        invoke_wait_health() {
          deploy.argocd.wait_healthy my-app 2>/dev/null || return 1
          grep -q "\-\-health" "$MOCK_LOG"
        }
        When call invoke_wait_health
        The status should be success
      End

      It "respects custom --timeout"
        invoke_wait_timeout() {
          deploy.argocd.wait_healthy my-app --timeout 600 2>/dev/null || return 1
          grep -q "\-\-timeout 600" "$MOCK_LOG"
        }
        When call invoke_wait_timeout
        The status should be success
      End

      It "succeeds and logs wait message"
        When call deploy.argocd.wait_healthy my-app
        The status should be success
        The stderr should include "my-app"
      End
    End
  End

  # ---------------------------------------------------------------------------
  # deploy.argocd.rollback
  # ---------------------------------------------------------------------------
  Describe "deploy.argocd.rollback"
    It "returns 2 when app_name is missing"
      When call deploy.argocd.rollback
      The status should equal 2
      The stderr should include "app_name is required"
    End

    Describe "with mock argocd"
      setup_argocd_rollback() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_argocd.log"
        mock.create_logging "argocd" "$MOCK_LOG"
        mock.activate
        unset BRIK_DRY_RUN 2>/dev/null
      }
      cleanup_argocd_rollback() {
        mock.cleanup
        unset BRIK_DRY_RUN 2>/dev/null
        rm -rf "$TEST_WS"
      }
      Before 'setup_argocd_rollback'
      After 'cleanup_argocd_rollback'

      It "calls argocd app rollback with app_name"
        invoke_rollback() {
          deploy.argocd.rollback my-app 2>/dev/null || return 1
          grep -q "app rollback my-app" "$MOCK_LOG"
        }
        When call invoke_rollback
        The status should be success
      End

      It "succeeds and logs rollback message"
        When call deploy.argocd.rollback my-app
        The status should be success
        The stderr should include "my-app"
      End
    End
  End

  # ---------------------------------------------------------------------------
  # deploy.argocd.diff
  # ---------------------------------------------------------------------------
  Describe "deploy.argocd.diff"
    It "returns 2 when app_name is missing"
      When call deploy.argocd.diff
      The status should equal 2
      The stderr should include "app_name is required"
    End

    Describe "with mock argocd (no diff)"
      setup_argocd_diff_ok() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_argocd.log"
        mock.create_logging "argocd" "$MOCK_LOG"
        mock.activate
        unset BRIK_DRY_RUN 2>/dev/null
      }
      cleanup_argocd_diff_ok() {
        mock.cleanup
        unset BRIK_DRY_RUN 2>/dev/null
        rm -rf "$TEST_WS"
      }
      Before 'setup_argocd_diff_ok'
      After 'cleanup_argocd_diff_ok'

      It "calls argocd app diff with app_name"
        invoke_diff() {
          deploy.argocd.diff my-app 2>/dev/null || return 1
          grep -q "app diff my-app" "$MOCK_LOG"
        }
        When call invoke_diff
        The status should be success
      End

      It "returns 0 when no diff (argocd exits 0)"
        When call deploy.argocd.diff my-app
        The status should equal 0
        The stderr should include "checking diff"
      End
    End

    Describe "with mock argocd that reports diff (exit 1)"
      setup_argocd_diff_found() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_argocd.log"
        mock.create_exit "argocd" 1
        mock.activate
        unset BRIK_DRY_RUN 2>/dev/null
      }
      cleanup_argocd_diff_found() {
        mock.cleanup
        unset BRIK_DRY_RUN 2>/dev/null
        rm -rf "$TEST_WS"
      }
      Before 'setup_argocd_diff_found'
      After 'cleanup_argocd_diff_found'

      It "returns 1 when diff exists"
        When call deploy.argocd.diff my-app
        The status should equal 1
        The stderr should include "checking diff"
      End
    End
  End

  # ---------------------------------------------------------------------------
  # deploy.argocd.status
  # ---------------------------------------------------------------------------
  Describe "deploy.argocd.status"
    It "returns 2 when app_name is missing"
      When call deploy.argocd.status
      The status should equal 2
      The stderr should include "app_name is required"
    End

    Describe "with mock argocd"
      setup_argocd_status() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_argocd.log"
        mock.create_logging "argocd" "$MOCK_LOG"
        mock.activate
        unset BRIK_DRY_RUN 2>/dev/null
      }
      cleanup_argocd_status() {
        mock.cleanup
        unset BRIK_DRY_RUN 2>/dev/null
        rm -rf "$TEST_WS"
      }
      Before 'setup_argocd_status'
      After 'cleanup_argocd_status'

      It "calls argocd app get with app_name"
        invoke_status() {
          deploy.argocd.status my-app 2>/dev/null || return 1
          grep -q "app get my-app" "$MOCK_LOG"
        }
        When call invoke_status
        The status should be success
      End

      It "succeeds and logs status message"
        When call deploy.argocd.status my-app
        The status should be success
        The stderr should include "my-app"
      End
    End

    Describe "with failing argocd"
      setup_argocd_status_fail() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        mock.create_exit "argocd" 1
        mock.activate
        unset BRIK_DRY_RUN 2>/dev/null
      }
      cleanup_argocd_status_fail() {
        mock.cleanup
        unset BRIK_DRY_RUN 2>/dev/null
        rm -rf "$TEST_WS"
      }
      Before 'setup_argocd_status_fail'
      After 'cleanup_argocd_status_fail'

      It "returns 5 when argocd app get fails"
        When call deploy.argocd.status my-app
        The status should equal 5
        The stderr should include "argocd app get failed"
      End
    End
  End

  # ---------------------------------------------------------------------------
  # _deploy.argocd._validate_app_name
  # ---------------------------------------------------------------------------
  Describe "_deploy.argocd._validate_app_name"
    It "returns 2 for invalid app name (uppercase)"
      When call _deploy.argocd._validate_app_name "MyApp"
      The status should equal 2
      The stderr should include "invalid ArgoCD app name"
    End

    It "returns 2 for invalid app name (special chars)"
      When call _deploy.argocd._validate_app_name "my app!"
      The status should equal 2
      The stderr should include "invalid ArgoCD app name"
    End

    It "returns 2 for app name starting with dot"
      When call _deploy.argocd._validate_app_name ".my-app"
      The status should equal 2
      The stderr should include "invalid ArgoCD app name"
    End
  End

  # ---------------------------------------------------------------------------
  # deploy.argocd.sync - failure
  # ---------------------------------------------------------------------------
  Describe "deploy.argocd.sync - failure"
    setup_argocd_sync_fail() {
      mock.setup
      mock.create_exit "argocd" 1
      mock.activate
      unset BRIK_DRY_RUN 2>/dev/null
    }
    cleanup_argocd_sync_fail() {
      mock.cleanup
      unset BRIK_DRY_RUN 2>/dev/null
    }
    Before 'setup_argocd_sync_fail'
    After 'cleanup_argocd_sync_fail'

    It "returns 5 when argocd app sync fails"
      When call deploy.argocd.sync my-app
      The status should equal 5
      The stderr should include "argocd app sync failed"
    End
  End

  # ---------------------------------------------------------------------------
  # deploy.argocd.wait_healthy - additional coverage
  # ---------------------------------------------------------------------------
  Describe "deploy.argocd.wait_healthy - input validation"
    It "returns 2 for unknown option"
      When call deploy.argocd.wait_healthy my-app --badopt foo
      The status should equal 2
      The stderr should include "unknown option"
    End

    It "returns 2 for non-integer timeout"
      When call deploy.argocd.wait_healthy my-app --timeout "abc"
      The status should equal 2
      The stderr should include "timeout must be a positive integer"
    End
  End

  Describe "deploy.argocd.wait_healthy - require_tool failure"
    setup_no_argocd_wait() {
      mock.setup
      mock.isolate
    }
    cleanup_no_argocd_wait() {
      mock.cleanup
    }
    Before 'setup_no_argocd_wait'
    After 'cleanup_no_argocd_wait'

    It "returns 3 when argocd is not on PATH"
      When call deploy.argocd.wait_healthy my-app
      The status should equal 3
      The stderr should include "required tool not found"
    End
  End

  Describe "deploy.argocd.wait_healthy - dry-run"
    setup_dryrun_wait() {
      mock.setup
      TEST_WS="$(mktemp -d)"
      mock.create_logging "argocd" "${TEST_WS}/mock.log"
      mock.activate
      export BRIK_DRY_RUN="true"
    }
    cleanup_dryrun_wait() {
      mock.cleanup
      unset BRIK_DRY_RUN 2>/dev/null
      rm -rf "$TEST_WS"
    }
    Before 'setup_dryrun_wait'
    After 'cleanup_dryrun_wait'

    It "logs dry-run message without executing argocd"
      When call deploy.argocd.wait_healthy my-app
      The status should be success
      The stderr should include "dry-run"
    End
  End

  Describe "deploy.argocd.wait_healthy - failure"
    setup_argocd_wait_fail() {
      mock.setup
      mock.create_exit "argocd" 1
      mock.activate
      unset BRIK_DRY_RUN 2>/dev/null
    }
    cleanup_argocd_wait_fail() {
      mock.cleanup
      unset BRIK_DRY_RUN 2>/dev/null
    }
    Before 'setup_argocd_wait_fail'
    After 'cleanup_argocd_wait_fail'

    It "returns 5 when argocd app wait fails"
      When call deploy.argocd.wait_healthy my-app
      The status should equal 5
      The stderr should include "argocd app wait failed"
    End
  End

  # ---------------------------------------------------------------------------
  # deploy.argocd.rollback - additional coverage
  # ---------------------------------------------------------------------------
  Describe "deploy.argocd.rollback - require_tool failure"
    setup_no_argocd_rollback() {
      mock.setup
      mock.isolate
    }
    cleanup_no_argocd_rollback() {
      mock.cleanup
    }
    Before 'setup_no_argocd_rollback'
    After 'cleanup_no_argocd_rollback'

    It "returns 3 when argocd is not on PATH"
      When call deploy.argocd.rollback my-app
      The status should equal 3
      The stderr should include "required tool not found"
    End
  End

  Describe "deploy.argocd.rollback - dry-run"
    setup_dryrun_rollback() {
      mock.setup
      mock.create_logging "argocd" "${MOCK_BIN}/mock.log"
      mock.activate
      export BRIK_DRY_RUN="true"
    }
    cleanup_dryrun_rollback() {
      mock.cleanup
      unset BRIK_DRY_RUN 2>/dev/null
    }
    Before 'setup_dryrun_rollback'
    After 'cleanup_dryrun_rollback'

    It "logs dry-run message without executing argocd"
      When call deploy.argocd.rollback my-app
      The status should be success
      The stderr should include "dry-run"
    End
  End

  Describe "deploy.argocd.rollback - failure"
    setup_argocd_rollback_fail() {
      mock.setup
      mock.create_exit "argocd" 1
      mock.activate
      unset BRIK_DRY_RUN 2>/dev/null
    }
    cleanup_argocd_rollback_fail() {
      mock.cleanup
      unset BRIK_DRY_RUN 2>/dev/null
    }
    Before 'setup_argocd_rollback_fail'
    After 'cleanup_argocd_rollback_fail'

    It "returns 5 when argocd app rollback fails"
      When call deploy.argocd.rollback my-app
      The status should equal 5
      The stderr should include "argocd app rollback failed"
    End
  End

  # ---------------------------------------------------------------------------
  # deploy.argocd.diff - additional coverage
  # ---------------------------------------------------------------------------
  Describe "deploy.argocd.diff - require_tool failure"
    setup_no_argocd_diff() {
      mock.setup
      mock.isolate
    }
    cleanup_no_argocd_diff() {
      mock.cleanup
    }
    Before 'setup_no_argocd_diff'
    After 'cleanup_no_argocd_diff'

    It "returns 3 when argocd is not on PATH"
      When call deploy.argocd.diff my-app
      The status should equal 3
      The stderr should include "required tool not found"
    End
  End

  Describe "deploy.argocd.diff - dry-run"
    setup_dryrun_diff() {
      mock.setup
      mock.create_logging "argocd" "${MOCK_BIN}/mock.log"
      mock.activate
      export BRIK_DRY_RUN="true"
    }
    cleanup_dryrun_diff() {
      mock.cleanup
      unset BRIK_DRY_RUN 2>/dev/null
    }
    Before 'setup_dryrun_diff'
    After 'cleanup_dryrun_diff'

    It "logs dry-run message without executing argocd"
      When call deploy.argocd.diff my-app
      The status should be success
      The stderr should include "dry-run"
    End
  End

  # ---------------------------------------------------------------------------
  # deploy.argocd.status - additional coverage
  # ---------------------------------------------------------------------------
  Describe "deploy.argocd.status - require_tool failure"
    setup_no_argocd_status() {
      mock.setup
      mock.isolate
    }
    cleanup_no_argocd_status() {
      mock.cleanup
    }
    Before 'setup_no_argocd_status'
    After 'cleanup_no_argocd_status'

    It "returns 3 when argocd is not on PATH"
      When call deploy.argocd.status my-app
      The status should equal 3
      The stderr should include "required tool not found"
    End
  End

  Describe "deploy.argocd.status - dry-run"
    setup_dryrun_status() {
      mock.setup
      mock.create_logging "argocd" "${MOCK_BIN}/mock.log"
      mock.activate
      export BRIK_DRY_RUN="true"
    }
    cleanup_dryrun_status() {
      mock.cleanup
      unset BRIK_DRY_RUN 2>/dev/null
    }
    Before 'setup_dryrun_status'
    After 'cleanup_dryrun_status'

    It "logs dry-run message without executing argocd"
      When call deploy.argocd.status my-app
      The status should be success
      The stderr should include "dry-run"
    End
  End

  # ---------------------------------------------------------------------------
  # double-sourcing guard
  # ---------------------------------------------------------------------------
  Describe "double-sourcing guard"
    It "is callable after double include"
      double_include() {
        # shellcheck source=/dev/null
        . "$BRIK_CORE_LIB/deploy/argocd.sh"
        declare -f deploy.argocd.sync >/dev/null && echo "ok" || echo "missing"
      }
      When call double_include
      The output should equal "ok"
    End
  End
End
