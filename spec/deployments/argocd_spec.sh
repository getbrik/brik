Describe "deploy/argocd.sh"
  Include "$BRIK_PIPELINE_LIB/logging.sh"
  Include "$BRIK_PIPELINE_LIB/tools.sh"
  Include "$BRIK_TRANSVERSE_LIB/env.sh"
  Include "$BRIK_DEPLOYMENTS_LIB/argocd.sh"
  Include "$BRIK_HOME/spec/support/mock_helper.sh"

  # ---------------------------------------------------------------------------
  # _deploy.argocd._validate_app_name
  # ---------------------------------------------------------------------------
  Describe "_deploy.argocd._validate_app_name"
    It "returns 2 when app_name is empty"
      When call _deploy.argocd._validate_app_name ""
      The status should equal 2
      The stderr should include "app is required"
    End

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

    It "accepts valid app names"
      When call _deploy.argocd._validate_app_name "my-app.v2"
      The status should be success
    End
  End

  # ---------------------------------------------------------------------------
  # deploy.argocd.sync
  # ---------------------------------------------------------------------------
  Describe "deploy.argocd.sync"
    It "returns 2 when --app is missing"
      When call deploy.argocd.sync
      The status should equal 2
      The stderr should include "app is required"
    End

    It "returns 2 for unknown option"
      When call deploy.argocd.sync --app my-app --badopt
      The status should equal 2
      The stderr should include "unknown option"
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
        When call deploy.argocd.sync --app my-app
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
          deploy.argocd.sync --app my-app 2>/dev/null || return 1
          grep -q "app sync my-app" "$MOCK_LOG"
        }
        When call invoke_sync
        The status should be success
      End

      It "succeeds and logs sync started"
        When call deploy.argocd.sync --app my-app
        The status should be success
        The stderr should include "my-app"
      End

      It "passes --prune flag"
        invoke_prune() {
          deploy.argocd.sync --app my-app --prune 2>/dev/null || return 1
          grep -q "\-\-prune" "$MOCK_LOG"
        }
        When call invoke_prune
        The status should be success
      End

      It "passes --async flag"
        invoke_async() {
          deploy.argocd.sync --app my-app --async 2>/dev/null || return 1
          grep -q "\-\-async" "$MOCK_LOG"
        }
        When call invoke_async
        The status should be success
      End

      It "passes --server flag"
        invoke_server() {
          deploy.argocd.sync --app my-app --server https://argocd.example.com 2>/dev/null || return 1
          grep -q "\-\-server https://argocd.example.com" "$MOCK_LOG"
        }
        When call invoke_server
        The status should be success
      End

      It "passes --auth-token from env var"
        invoke_auth() {
          export MY_ARGO_TOKEN="s3cret"
          deploy.argocd.sync --app my-app --auth-token-var MY_ARGO_TOKEN 2>/dev/null || return 1
          grep -q "\-\-auth-token s3cret" "$MOCK_LOG"
          local rc=$?
          unset MY_ARGO_TOKEN
          return $rc
        }
        When call invoke_auth
        The status should be success
      End

      It "passes ARGOCD_AUTH_TOKEN env var as fallback auth"
        invoke_env_token() {
          export ARGOCD_AUTH_TOKEN="env-token-value"
          deploy.argocd.sync --app my-app 2>/dev/null || return 1
          local rc=0
          grep -q "\-\-auth-token env-token-value" "$MOCK_LOG" || rc=1
          unset ARGOCD_AUTH_TOKEN
          return $rc
        }
        When call invoke_env_token
        The status should be success
      End

      It "returns 4 when auth-token-var points to empty variable"
        invoke_empty_token() {
          unset MY_EMPTY_TOKEN 2>/dev/null
          deploy.argocd.sync --app my-app --auth-token-var MY_EMPTY_TOKEN 2>/dev/null
        }
        When call invoke_empty_token
        The status should equal 4
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
          deploy.argocd.sync --app my-app 2>/dev/null
          ! grep -q "app sync" "$MOCK_LOG" 2>/dev/null
        }
        When call invoke_dryrun
        The status should be success
      End

      It "prints dry-run indicator in output"
        When call deploy.argocd.sync --app my-app
        The status should be success
        The stderr should include "dry-run"
      End

      It "dry-run via --dry-run flag"
        invoke_dryrun_flag() {
          unset BRIK_DRY_RUN 2>/dev/null
          deploy.argocd.sync --app my-app --dry-run 2>/dev/null
          ! grep -q "app sync" "$MOCK_LOG" 2>/dev/null
        }
        When call invoke_dryrun_flag
        The status should be success
      End
    End

    Describe "sync failure"
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
        When call deploy.argocd.sync --app my-app
        The status should equal 5
        The stderr should include "argocd app sync failed"
      End
    End
  End

  # ---------------------------------------------------------------------------
  # deploy.argocd.wait_healthy
  # ---------------------------------------------------------------------------
  Describe "deploy.argocd.wait_healthy"
    It "returns 2 when --app is missing"
      When call deploy.argocd.wait_healthy
      The status should equal 2
      The stderr should include "app is required"
    End

    It "returns 2 for unknown option"
      When call deploy.argocd.wait_healthy --app my-app --badopt foo
      The status should equal 2
      The stderr should include "unknown option"
    End

    It "returns 2 for non-integer timeout"
      When call deploy.argocd.wait_healthy --app my-app --timeout "abc"
      The status should equal 2
      The stderr should include "timeout must be a positive integer"
    End

    Describe "require_tool failure"
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
        When call deploy.argocd.wait_healthy --app my-app
        The status should equal 3
        The stderr should include "required tool not found"
      End
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
          deploy.argocd.wait_healthy --app my-app 2>/dev/null || return 1
          grep -q "app wait my-app" "$MOCK_LOG" &&
          grep -q "\-\-timeout 300" "$MOCK_LOG"
        }
        When call invoke_wait_default
        The status should be success
      End

      It "passes --health flag"
        invoke_wait_health() {
          deploy.argocd.wait_healthy --app my-app 2>/dev/null || return 1
          grep -q "\-\-health" "$MOCK_LOG"
        }
        When call invoke_wait_health
        The status should be success
      End

      It "respects custom --timeout"
        invoke_wait_timeout() {
          deploy.argocd.wait_healthy --app my-app --timeout 600 2>/dev/null || return 1
          grep -q "\-\-timeout 600" "$MOCK_LOG"
        }
        When call invoke_wait_timeout
        The status should be success
      End

      It "succeeds and logs wait message"
        When call deploy.argocd.wait_healthy --app my-app
        The status should be success
        The stderr should include "my-app"
      End

      It "passes --server and --auth-token-var"
        invoke_wait_server_auth() {
          export MY_TOKEN="tok123"
          deploy.argocd.wait_healthy --app my-app --server https://argo.local --auth-token-var MY_TOKEN 2>/dev/null || return 1
          grep -q "\-\-server https://argo.local" "$MOCK_LOG" &&
          grep -q "\-\-auth-token tok123" "$MOCK_LOG"
          local rc=$?
          unset MY_TOKEN
          return $rc
        }
        When call invoke_wait_server_auth
        The status should be success
      End
    End

    Describe "dry-run mode"
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
        When call deploy.argocd.wait_healthy --app my-app
        The status should be success
        The stderr should include "dry-run"
      End
    End

    Describe "failure"
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
        When call deploy.argocd.wait_healthy --app my-app
        The status should equal 5
        The stderr should include "argocd app wait failed"
      End
    End
  End

  # ---------------------------------------------------------------------------
  # deploy.argocd.rollback
  # ---------------------------------------------------------------------------
  Describe "deploy.argocd.rollback"
    It "returns 2 when --app is missing"
      When call deploy.argocd.rollback
      The status should equal 2
      The stderr should include "app is required"
    End

    Describe "require_tool failure"
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
        When call deploy.argocd.rollback --app my-app
        The status should equal 3
        The stderr should include "required tool not found"
      End
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
          deploy.argocd.rollback --app my-app 2>/dev/null || return 1
          grep -q "app rollback my-app" "$MOCK_LOG"
        }
        When call invoke_rollback
        The status should be success
      End

      It "passes --revision number"
        invoke_revision() {
          deploy.argocd.rollback --app my-app --revision 42 2>/dev/null || return 1
          grep -q "42" "$MOCK_LOG"
        }
        When call invoke_revision
        The status should be success
      End

      It "succeeds and logs rollback message"
        When call deploy.argocd.rollback --app my-app
        The status should be success
        The stderr should include "my-app"
      End

      It "passes --server to argocd"
        invoke_rollback_server() {
          deploy.argocd.rollback --app my-app --server https://argocd.example.com 2>/dev/null || return 1
          grep -q "\-\-server" "$MOCK_LOG"
        }
        When call invoke_rollback_server
        The status should be success
      End

      It "passes --auth-token to argocd when --auth-token-var set"
        invoke_rollback_auth() {
          export MY_ARGOCD_TOKEN="test-token-123"
          deploy.argocd.rollback --app my-app --auth-token-var MY_ARGOCD_TOKEN 2>/dev/null || return 1
          grep -q "\-\-auth-token" "$MOCK_LOG"
          local rc=$?
          unset MY_ARGOCD_TOKEN
          return $rc
        }
        When call invoke_rollback_auth
        The status should be success
      End

      It "returns 2 for unknown option"
        When call deploy.argocd.rollback --app my-app --badopt foo
        The status should equal 2
        The stderr should include "unknown option"
      End
    End

    Describe "dry-run mode"
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
        When call deploy.argocd.rollback --app my-app
        The status should be success
        The stderr should include "dry-run"
      End
    End

    Describe "failure"
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
        When call deploy.argocd.rollback --app my-app
        The status should equal 5
        The stderr should include "argocd app rollback failed"
      End
    End
  End

  # ---------------------------------------------------------------------------
  # deploy.argocd.diff
  # ---------------------------------------------------------------------------
  Describe "deploy.argocd.diff"
    It "returns 2 when --app is missing"
      When call deploy.argocd.diff
      The status should equal 2
      The stderr should include "app is required"
    End

    Describe "require_tool failure"
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
        When call deploy.argocd.diff --app my-app
        The status should equal 3
        The stderr should include "required tool not found"
      End
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
          deploy.argocd.diff --app my-app 2>/dev/null || return 1
          grep -q "app diff my-app" "$MOCK_LOG"
        }
        When call invoke_diff
        The status should be success
      End

      It "returns 0 when no diff (argocd exits 0)"
        When call deploy.argocd.diff --app my-app
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
        When call deploy.argocd.diff --app my-app
        The status should equal 1
        The stderr should include "checking diff"
      End
    End

    Describe "dry-run mode"
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
        When call deploy.argocd.diff --app my-app
        The status should be success
        The stderr should include "dry-run"
      End
    End

    Describe "with --server flag"
      setup_diff_server() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_argocd.log"
        mock.create_logging "argocd" "$MOCK_LOG"
        mock.activate
      }
      cleanup_diff_server() {
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_diff_server'
      After 'cleanup_diff_server'

      It "passes --server to argocd diff command"
        invoke_diff_server() {
          deploy.argocd.diff --app my-app --server https://argocd.local 2>/dev/null || return 1
          grep -q "\-\-server https://argocd.local" "$MOCK_LOG"
        }
        When call invoke_diff_server
        The status should be success
      End

      It "returns 2 for unknown option"
        When call deploy.argocd.diff --app my-app --badopt
        The status should equal 2
        The stderr should include "unknown option"
      End
    End
  End

  # ---------------------------------------------------------------------------
  # deploy.argocd.status
  # ---------------------------------------------------------------------------
  Describe "deploy.argocd.status"
    It "returns 2 when --app is missing"
      When call deploy.argocd.status
      The status should equal 2
      The stderr should include "app is required"
    End

    Describe "require_tool failure (argocd)"
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
        When call deploy.argocd.status --app my-app
        The status should equal 3
        The stderr should include "required tool not found"
      End
    End

    Describe "require_tool failure (jq)"
      setup_no_jq_status() {
        mock.setup
        mock.create_exit "argocd" 0
        # jq is NOT provided -> require_tool jq should fail
        # Use PATH restriction to exclude jq while keeping argocd
        mock.activate
        # Override PATH to only include mock bin (no jq)
      }
      cleanup_no_jq_status() {
        mock.cleanup
      }
      Before 'setup_no_jq_status'
      After 'cleanup_no_jq_status'

      # Note: jq is likely on the system PATH so this test would only work
      # if we fully isolate. Since argocd mock is needed, we skip the jq
      # require_tool isolation test (it uses the same pattern as argocd).
    End

    Describe "with mock argocd outputting JSON"
      setup_argocd_status_json() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_argocd.log"
        export MOCK_LOG
        # Create argocd mock that outputs JSON to stdout
        local mock_script="${MOCK_BIN}/argocd"
        cat > "$mock_script" <<SCRIPT
#!/usr/bin/env bash
echo "\$@" >> "${MOCK_LOG}"
if [[ "\$*" == *"app get"* ]]; then
  cat <<'JSON'
{
  "status": {
    "health": {"status": "Healthy"},
    "sync": {"status": "Synced", "revision": "abc1234"},
    "conditions": [{"message": "all good"}]
  }
}
JSON
fi
SCRIPT
        chmod +x "$mock_script"
        mock.activate
        unset BRIK_DRY_RUN 2>/dev/null
      }
      cleanup_argocd_status_json() {
        mock.cleanup
        unset BRIK_DRY_RUN 2>/dev/null
        rm -rf "$TEST_WS"
      }
      Before 'setup_argocd_status_json'
      After 'cleanup_argocd_status_json'

      It "outputs structured JSON to stdout"
        invoke_status_json() {
          local out
          out=$(deploy.argocd.status --app my-app 2>/dev/null) || return 1
          printf '%s' "$out" | jq -e '.health_status == "Healthy"' >/dev/null &&
          printf '%s' "$out" | jq -e '.sync_status == "Synced"' >/dev/null &&
          printf '%s' "$out" | jq -e '.revision == "abc1234"' >/dev/null
        }
        When call invoke_status_json
        The status should be success
      End

      It "passes -o json to argocd"
        invoke_status_json_flag() {
          deploy.argocd.status --app my-app 2>/dev/null >/dev/null || return 1
          grep -q "\-o json" "$MOCK_LOG"
        }
        When call invoke_status_json_flag
        The status should be success
      End

      It "passes --server and --auth-token-var"
        invoke_status_server() {
          export MY_TOKEN="tok"
          deploy.argocd.status --app my-app --server https://argo.local --auth-token-var MY_TOKEN 2>/dev/null >/dev/null || return 1
          grep -q "\-\-server https://argo.local" "$MOCK_LOG" &&
          grep -q "\-\-auth-token tok" "$MOCK_LOG"
          local rc=$?
          unset MY_TOKEN
          return $rc
        }
        When call invoke_status_server
        The status should be success
      End
    End

    Describe "with failing argocd"
      setup_argocd_status_fail() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        mock.create_exit "argocd" 1
        # Need jq on PATH too
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
        When call deploy.argocd.status --app my-app
        The status should equal 5
        The stderr should include "argocd app get failed"
      End
    End

    Describe "dry-run mode"
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
        When call deploy.argocd.status --app my-app
        The status should be success
        The stderr should include "dry-run"
      End
    End
  End

  # ---------------------------------------------------------------------------
  # deploy.argocd.is_synced
  # ---------------------------------------------------------------------------
  Describe "deploy.argocd.is_synced"
    It "returns 2 when --app is missing"
      When call deploy.argocd.is_synced
      The status should equal 2
      The stderr should include "app is required"
    End

    Describe "when app is Healthy+Synced"
      setup_is_synced_ok() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        # Create argocd mock that returns Healthy/Synced JSON
        local mock_script="${MOCK_BIN}/argocd"
        cat > "$mock_script" <<'SCRIPT'
#!/usr/bin/env bash
if [[ "$*" == *"app get"* ]]; then
  cat <<'JSON'
{
  "status": {
    "health": {"status": "Healthy"},
    "sync": {"status": "Synced", "revision": "abc1234"},
    "conditions": []
  }
}
JSON
fi
SCRIPT
        chmod +x "$mock_script"
        mock.activate
        unset BRIK_DRY_RUN 2>/dev/null
      }
      cleanup_is_synced_ok() {
        mock.cleanup
        unset BRIK_DRY_RUN 2>/dev/null
        rm -rf "$TEST_WS"
      }
      Before 'setup_is_synced_ok'
      After 'cleanup_is_synced_ok'

      It "returns 0 when Healthy and Synced"
        invoke_is_synced_ok() {
          deploy.argocd.is_synced --app my-app 2>/dev/null
        }
        When call invoke_is_synced_ok
        The status should be success
      End
    End

    Describe "when app is not synced"
      setup_is_synced_progressing() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        local mock_script="${MOCK_BIN}/argocd"
        cat > "$mock_script" <<'SCRIPT'
#!/usr/bin/env bash
if [[ "$*" == *"app get"* ]]; then
  cat <<'JSON'
{
  "status": {
    "health": {"status": "Progressing"},
    "sync": {"status": "OutOfSync", "revision": "abc1234"},
    "conditions": []
  }
}
JSON
fi
SCRIPT
        chmod +x "$mock_script"
        mock.activate
        unset BRIK_DRY_RUN 2>/dev/null
      }
      cleanup_is_synced_progressing() {
        mock.cleanup
        unset BRIK_DRY_RUN 2>/dev/null
        rm -rf "$TEST_WS"
      }
      Before 'setup_is_synced_progressing'
      After 'cleanup_is_synced_progressing'

      It "returns 1 when not Healthy+Synced"
        invoke_is_synced_no() {
          deploy.argocd.is_synced --app my-app 2>/dev/null
        }
        When call invoke_is_synced_no
        The status should equal 1
      End
    End

    Describe "Healthy but OutOfSync"
      setup_partial_sync() {
        mock.setup
        mock.create_script "argocd" 'echo "{\"status\":{\"health\":{\"status\":\"Healthy\"},\"sync\":{\"status\":\"OutOfSync\"}}}"'
        mock.create_script "jq" 'exec /usr/bin/jq "$@"'
        mock.activate
      }
      cleanup_partial_sync() {
        mock.cleanup
      }
      Before 'setup_partial_sync'
      After 'cleanup_partial_sync'

      It "returns 1 when Healthy but OutOfSync"
        invoke_healthy_outofsync() {
          deploy.argocd.is_synced --app my-app 2>/dev/null
        }
        When call invoke_healthy_outofsync
        The status should equal 1
      End
    End
  End

  # ---------------------------------------------------------------------------
  # deploy.argocd.deploy
  # ---------------------------------------------------------------------------
  Describe "deploy.argocd.deploy"
    It "returns 2 when --app is missing"
      When call deploy.argocd.deploy --repo https://git.example.com/config.git --branch main --path apps/myapp --source /tmp/rendered
      The status should equal 2
      The stderr should include "app is required"
    End

    It "returns 2 when --repo is missing"
      When call deploy.argocd.deploy --app my-app --branch main --path apps/myapp --source /tmp/rendered
      The status should equal 2
      The stderr should include "repo is required"
    End

    It "returns 2 when --branch is missing"
      When call deploy.argocd.deploy --app my-app --repo https://git.example.com/config.git --path apps/myapp --source /tmp/rendered
      The status should equal 2
      The stderr should include "branch is required"
    End

    It "returns 2 when --path is missing"
      When call deploy.argocd.deploy --app my-app --repo https://git.example.com/config.git --branch main --source /tmp/rendered
      The status should equal 2
      The stderr should include "path is required"
    End

    It "returns 2 when --source is missing"
      When call deploy.argocd.deploy --app my-app --repo https://git.example.com/config.git --branch main --path apps/myapp
      The status should equal 2
      The stderr should include "source is required"
    End

    It "returns 2 for unknown option"
      When call deploy.argocd.deploy --app my-app --repo https://git.example.com/config.git \
        --branch main --path apps --source /tmp/rendered --badopt foo
      The status should equal 2
      The stderr should include "unknown option"
    End

    It "returns 2 for invalid app name"
      When call deploy.argocd.deploy --app MY_APP --repo https://git.example.com/config.git \
        --branch main --path apps --source /tmp/rendered
      The status should equal 2
      The stderr should include "invalid ArgoCD app name"
    End
  End

  # ---------------------------------------------------------------------------
  # deploy.argocd.sync - "another operation in progress" warning
  # ---------------------------------------------------------------------------
  Describe "deploy.argocd.sync - another operation in progress"
    setup_sync_in_progress() {
      mock.setup
      TEST_WS="$(mktemp -d)"
      MOCK_LOG="${TEST_WS}/mock_argocd.log"
      # argocd mock that fails with "another operation is already in progress"
      local mock_script="${MOCK_BIN}/argocd"
      cat > "$mock_script" <<'SCRIPT'
#!/usr/bin/env bash
echo "another operation is already in progress" >&2
exit 1
SCRIPT
      chmod +x "$mock_script"
      mock.activate
      unset BRIK_DRY_RUN 2>/dev/null
    }
    cleanup_sync_in_progress() {
      mock.cleanup
      unset BRIK_DRY_RUN 2>/dev/null
      rm -rf "$TEST_WS"
    }
    Before 'setup_sync_in_progress'
    After 'cleanup_sync_in_progress'

    It "warns and succeeds when another operation is already in progress"
      When call deploy.argocd.sync --app my-app
      The status should be success
      The stderr should include "another operation already in progress"
    End
  End

  # ---------------------------------------------------------------------------
  # deploy.argocd.rollback - auto-sync retry logic
  # ---------------------------------------------------------------------------
  Describe "deploy.argocd.rollback - auto-sync retry"
    setup_rollback_autosync() {
      mock.setup
      TEST_WS="$(mktemp -d)"
      MOCK_LOG="${TEST_WS}/mock_argocd.log"
      export MOCK_LOG
      # First rollback fails with "auto-sync is enabled",
      # then "app set" succeeds, retry rollback succeeds, re-enable succeeds
      local mock_script="${MOCK_BIN}/argocd"
      cat > "$mock_script" <<SCRIPT
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "${MOCK_LOG}"
if [[ "\$*" == *"app rollback"* ]]; then
  count_file="${TEST_WS}/rollback_count"
  count=\$(cat "\$count_file" 2>/dev/null || echo 0)
  count=\$((count + 1))
  echo "\$count" > "\$count_file"
  if [[ "\$count" -eq 1 ]]; then
    echo "auto-sync is enabled" >&2
    exit 1
  fi
  exit 0
fi
exit 0
SCRIPT
      chmod +x "$mock_script"
      mock.activate
      unset BRIK_DRY_RUN 2>/dev/null
    }
    cleanup_rollback_autosync() {
      mock.cleanup
      unset BRIK_DRY_RUN 2>/dev/null
      rm -rf "$TEST_WS"
    }
    Before 'setup_rollback_autosync'
    After 'cleanup_rollback_autosync'

    It "disables auto-sync and retries rollback successfully"
      invoke_autosync_retry() {
        deploy.argocd.rollback --app my-app 2>/dev/null || return 1
        grep -q "app set my-app --sync-policy none" "$MOCK_LOG" &&
        grep -q "app set my-app --sync-policy automated" "$MOCK_LOG"
      }
      When call invoke_autosync_retry
      The status should be success
    End

    It "logs disabling and re-enabling auto-sync"
      When call deploy.argocd.rollback --app my-app
      The status should be success
      The stderr should include "disabling auto-sync"
      The stderr should include "re-enabling auto-sync"
    End
  End

  Describe "deploy.argocd.rollback - auto-sync retry fails on second rollback"
    setup_rollback_autosync_fail() {
      mock.setup
      TEST_WS="$(mktemp -d)"
      MOCK_LOG="${TEST_WS}/mock_argocd.log"
      export MOCK_LOG
      # rollback always fails with auto-sync, then retry also fails
      local mock_script="${MOCK_BIN}/argocd"
      cat > "$mock_script" <<SCRIPT
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "${MOCK_LOG}"
if [[ "\$*" == *"app rollback"* ]]; then
  count_file="${TEST_WS}/rollback_count"
  count=\$(cat "\$count_file" 2>/dev/null || echo 0)
  count=\$((count + 1))
  echo "\$count" > "\$count_file"
  if [[ "\$count" -eq 1 ]]; then
    echo "auto-sync is enabled" >&2
    exit 1
  fi
  echo "rollback still fails" >&2
  exit 1
fi
exit 0
SCRIPT
      chmod +x "$mock_script"
      mock.activate
      unset BRIK_DRY_RUN 2>/dev/null
    }
    cleanup_rollback_autosync_fail() {
      mock.cleanup
      unset BRIK_DRY_RUN 2>/dev/null
      rm -rf "$TEST_WS"
    }
    Before 'setup_rollback_autosync_fail'
    After 'cleanup_rollback_autosync_fail'

    It "returns 5 when retry rollback also fails"
      When call deploy.argocd.rollback --app my-app
      The status should equal 5
      The stderr should include "argocd app rollback failed"
    End
  End

  Describe "deploy.argocd.rollback - auto-sync disable fails"
    setup_rollback_set_fail() {
      mock.setup
      TEST_WS="$(mktemp -d)"
      MOCK_LOG="${TEST_WS}/mock_argocd.log"
      export MOCK_LOG
      local mock_script="${MOCK_BIN}/argocd"
      cat > "$mock_script" <<SCRIPT
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "${MOCK_LOG}"
if [[ "\$*" == *"app rollback"* ]]; then
  echo "auto-sync is enabled" >&2
  exit 1
fi
if [[ "\$*" == *"app set"*"--sync-policy none"* ]]; then
  exit 1
fi
exit 0
SCRIPT
      chmod +x "$mock_script"
      mock.activate
      unset BRIK_DRY_RUN 2>/dev/null
    }
    cleanup_rollback_set_fail() {
      mock.cleanup
      unset BRIK_DRY_RUN 2>/dev/null
      rm -rf "$TEST_WS"
    }
    Before 'setup_rollback_set_fail'
    After 'cleanup_rollback_set_fail'

    It "returns 5 when disabling auto-sync fails"
      When call deploy.argocd.rollback --app my-app
      The status should equal 5
      The stderr should include "failed to disable auto-sync"
    End
  End

  Describe "deploy.argocd.rollback - re-enable auto-sync fails gracefully"
    setup_rollback_reenable_fail() {
      mock.setup
      TEST_WS="$(mktemp -d)"
      MOCK_LOG="${TEST_WS}/mock_argocd.log"
      export MOCK_LOG
      local mock_script="${MOCK_BIN}/argocd"
      cat > "$mock_script" <<SCRIPT
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "${MOCK_LOG}"
if [[ "\$*" == *"app rollback"* ]]; then
  count_file="${TEST_WS}/rollback_count"
  count=\$(cat "\$count_file" 2>/dev/null || echo 0)
  count=\$((count + 1))
  echo "\$count" > "\$count_file"
  if [[ "\$count" -eq 1 ]]; then
    echo "auto-sync is enabled" >&2
    exit 1
  fi
  exit 0
fi
if [[ "\$*" == *"--sync-policy automated"* ]]; then
  exit 1
fi
exit 0
SCRIPT
      chmod +x "$mock_script"
      mock.activate
      unset BRIK_DRY_RUN 2>/dev/null
    }
    cleanup_rollback_reenable_fail() {
      mock.cleanup
      unset BRIK_DRY_RUN 2>/dev/null
      rm -rf "$TEST_WS"
    }
    Before 'setup_rollback_reenable_fail'
    After 'cleanup_rollback_reenable_fail'

    It "succeeds but warns when re-enabling auto-sync fails"
      When call deploy.argocd.rollback --app my-app
      The status should be success
      The stderr should include "failed to re-enable auto-sync"
    End
  End

  # ---------------------------------------------------------------------------
  # deploy.argocd.diff - --dry-run via explicit flag + --auth-token-var
  # ---------------------------------------------------------------------------
  Describe "deploy.argocd.diff - --dry-run flag"
    setup_diff_dryrun_flag() {
      mock.setup
      TEST_WS="$(mktemp -d)"
      mock.create_logging "argocd" "${TEST_WS}/mock.log"
      mock.activate
      unset BRIK_DRY_RUN 2>/dev/null
    }
    cleanup_diff_dryrun_flag() {
      mock.cleanup
      unset BRIK_DRY_RUN 2>/dev/null
      rm -rf "$TEST_WS"
    }
    Before 'setup_diff_dryrun_flag'
    After 'cleanup_diff_dryrun_flag'

    It "logs dry-run message via --dry-run flag"
      When call deploy.argocd.diff --app my-app --dry-run
      The status should be success
      The stderr should include "dry-run"
    End
  End

  Describe "deploy.argocd.diff - --auth-token-var"
    setup_diff_auth() {
      mock.setup
      TEST_WS="$(mktemp -d)"
      MOCK_LOG="${TEST_WS}/mock_argocd.log"
      mock.create_logging "argocd" "$MOCK_LOG"
      mock.activate
      unset BRIK_DRY_RUN 2>/dev/null
    }
    cleanup_diff_auth() {
      mock.cleanup
      unset BRIK_DRY_RUN 2>/dev/null
      rm -rf "$TEST_WS"
    }
    Before 'setup_diff_auth'
    After 'cleanup_diff_auth'

    It "passes --auth-token-var to argocd diff"
      invoke_diff_auth() {
        export MY_TOKEN="diff-token"
        deploy.argocd.diff --app my-app --auth-token-var MY_TOKEN 2>/dev/null || return 1
        grep -q "\-\-auth-token diff-token" "$MOCK_LOG"
        local rc=$?
        unset MY_TOKEN
        return $rc
      }
      When call invoke_diff_auth
      The status should be success
    End
  End

  # ---------------------------------------------------------------------------
  # deploy.argocd.status - unknown option + --dry-run via flag
  # ---------------------------------------------------------------------------
  Describe "deploy.argocd.status - unknown option"
    It "returns 2 for unknown option"
      When call deploy.argocd.status --app my-app --badopt
      The status should equal 2
      The stderr should include "unknown option"
    End
  End

  Describe "deploy.argocd.status - --dry-run via flag"
    setup_status_dryrun_flag() {
      mock.setup
      mock.create_logging "argocd" "${MOCK_BIN}/mock.log"
      mock.create_exit "jq" 0
      mock.activate
      unset BRIK_DRY_RUN 2>/dev/null
    }
    cleanup_status_dryrun_flag() {
      mock.cleanup
      unset BRIK_DRY_RUN 2>/dev/null
    }
    Before 'setup_status_dryrun_flag'
    After 'cleanup_status_dryrun_flag'

    It "logs dry-run message via --dry-run flag"
      When call deploy.argocd.status --app my-app --dry-run
      The status should be success
      The stderr should include "dry-run"
    End
  End

  # ---------------------------------------------------------------------------
  # deploy.argocd.is_synced - with --server and --auth-token-var
  # ---------------------------------------------------------------------------
  Describe "deploy.argocd.is_synced - with server and auth"
    setup_is_synced_auth() {
      mock.setup
      TEST_WS="$(mktemp -d)"
      MOCK_LOG="${TEST_WS}/mock_argocd.log"
      export MOCK_LOG
      local mock_script="${MOCK_BIN}/argocd"
      cat > "$mock_script" <<SCRIPT
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "${MOCK_LOG}"
if [[ "\$*" == *"app get"* ]]; then
  cat <<'JSON'
{
  "status": {
    "health": {"status": "Healthy"},
    "sync": {"status": "Synced", "revision": "xyz"},
    "conditions": []
  }
}
JSON
fi
SCRIPT
      chmod +x "$mock_script"
      mock.activate
      unset BRIK_DRY_RUN 2>/dev/null
    }
    cleanup_is_synced_auth() {
      mock.cleanup
      unset BRIK_DRY_RUN 2>/dev/null
      rm -rf "$TEST_WS"
    }
    Before 'setup_is_synced_auth'
    After 'cleanup_is_synced_auth'

    It "passes --server and --auth-token-var through to status"
      invoke_synced_auth() {
        export MY_TOKEN="synced-tok"
        deploy.argocd.is_synced --app my-app --server https://argo.local --auth-token-var MY_TOKEN 2>/dev/null
        local rc=$?
        grep -q "\-\-server https://argo.local" "$MOCK_LOG" &&
        grep -q "\-\-auth-token synced-tok" "$MOCK_LOG"
        local grep_rc=$?
        unset MY_TOKEN
        [[ $rc -eq 0 && $grep_rc -eq 0 ]]
      }
      When call invoke_synced_auth
      The status should be success
    End

    It "returns 2 for unknown option"
      When call deploy.argocd.is_synced --app my-app --badopt
      The status should equal 2
      The stderr should include "unknown option"
    End
  End

  # ---------------------------------------------------------------------------
  # deploy.argocd.deploy - integration tests
  # ---------------------------------------------------------------------------
  Describe "deploy.argocd.deploy - dry-run integration"
    Include "$BRIK_DEPLOYMENTS_LIB/gitops.sh"

    setup_deploy_dryrun() {
      mock.setup
      TEST_WS="$(mktemp -d)"
      MOCK_LOG="${TEST_WS}/mock.log"
      export MOCK_LOG
      mock.create_logging "argocd" "$MOCK_LOG"
      mock.create_logging "git" "$MOCK_LOG"
      mock.activate
      export BRIK_DRY_RUN="true"
      brik.use() { :; }
    }
    cleanup_deploy_dryrun() {
      mock.cleanup
      unset BRIK_DRY_RUN 2>/dev/null
      unset -f brik.use 2>/dev/null
      rm -rf "$TEST_WS"
    }
    Before 'setup_deploy_dryrun'
    After 'cleanup_deploy_dryrun'

    It "runs all steps in dry-run mode"
      When call deploy.argocd.deploy \
        --app my-app \
        --repo https://git.example.com/config.git \
        --branch main \
        --path apps/myapp \
        --source /tmp/rendered \
        --dry-run
      The status should be success
      The stderr should include "dry-run"
    End
  End

  Describe "deploy.argocd.deploy - happy path with mocks"
    Include "$BRIK_TRANSVERSE_LIB/git.sh"
    Include "$BRIK_DEPLOYMENTS_LIB/gitops.sh"

    setup_deploy_happy() {
      mock.setup
      TEST_WS="$(mktemp -d)"
      MOCK_LOG="${TEST_WS}/mock.log"
      export MOCK_LOG
      export TEST_WS
      mkdir -p "${TEST_WS}/rendered"
      echo "apiVersion: v1" > "${TEST_WS}/rendered/deploy.yaml"
      mock.create_logging "argocd" "$MOCK_LOG"
      local mock_git="${MOCK_BIN}/git"
      cat > "$mock_git" <<SCRIPT
#!/usr/bin/env bash
printf 'git %s\n' "\$*" >> "${MOCK_LOG}"
if [[ "\$1" == "clone" ]]; then
  target="\${@: -1}"
  mkdir -p "\$target"
fi
if [[ "\$1" == "rev-parse" ]]; then
  echo "abc1234"
fi
SCRIPT
      chmod +x "$mock_git"
      mock.create_logging "rsync" "$MOCK_LOG"
      mock.activate
      unset BRIK_DRY_RUN 2>/dev/null
      brik.use() { :; }
    }
    cleanup_deploy_happy() {
      mock.cleanup
      unset BRIK_DRY_RUN 2>/dev/null
      unset -f brik.use 2>/dev/null
      rm -rf "$TEST_WS"
    }
    Before 'setup_deploy_happy'
    After 'cleanup_deploy_happy'

    It "runs push_manifests + sync + wait_healthy"
      invoke_deploy_happy() {
        deploy.argocd.deploy \
          --app my-app \
          --repo https://git.example.com/config.git \
          --branch main \
          --path apps/myapp \
          --source "${TEST_WS}/rendered" \
          --server https://argocd.local \
          --timeout 120 2>/dev/null || return $?
        grep -q "app sync my-app" "$MOCK_LOG" &&
        grep -q "app wait my-app" "$MOCK_LOG"
      }
      When call invoke_deploy_happy
      The status should be success
    End

    It "logs deployment completed"
      When call deploy.argocd.deploy \
        --app my-app \
        --repo https://git.example.com/config.git \
        --branch main \
        --path apps/myapp \
        --source "${TEST_WS}/rendered"
      The status should be success
      The stderr should include "argocd deployment completed"
    End

    It "passes --git-token-var to push_manifests"
      invoke_deploy_git_token() {
        export GIT_TOK="my-git-token"
        deploy.argocd.deploy \
          --app my-app \
          --repo https://git.example.com/config.git \
          --branch main \
          --path apps/myapp \
          --source "${TEST_WS}/rendered" \
          --git-token-var GIT_TOK 2>/dev/null
        local rc=$?
        unset GIT_TOK
        return $rc
      }
      When call invoke_deploy_git_token
      The status should be success
    End

    It "passes --auth-token-var to sync and wait_healthy"
      invoke_deploy_auth() {
        export ARGO_TOK="argo-secret"
        deploy.argocd.deploy \
          --app my-app \
          --repo https://git.example.com/config.git \
          --branch main \
          --path apps/myapp \
          --source "${TEST_WS}/rendered" \
          --auth-token-var ARGO_TOK 2>/dev/null || return $?
        grep -q "\-\-auth-token argo-secret" "$MOCK_LOG"
        local rc=$?
        unset ARGO_TOK
        return $rc
      }
      When call invoke_deploy_auth
      The status should be success
    End
  End

  # ---------------------------------------------------------------------------
  # deploy.argocd.wait_healthy - --dry-run via explicit flag
  # ---------------------------------------------------------------------------
  Describe "deploy.argocd.wait_healthy - --dry-run via flag"
    setup_wait_dryrun_flag() {
      mock.setup
      TEST_WS="$(mktemp -d)"
      mock.create_logging "argocd" "${TEST_WS}/mock.log"
      mock.activate
      unset BRIK_DRY_RUN 2>/dev/null
    }
    cleanup_wait_dryrun_flag() {
      mock.cleanup
      unset BRIK_DRY_RUN 2>/dev/null
      rm -rf "$TEST_WS"
    }
    Before 'setup_wait_dryrun_flag'
    After 'cleanup_wait_dryrun_flag'

    It "logs dry-run message via --dry-run flag (not env var)"
      When call deploy.argocd.wait_healthy --app my-app --dry-run
      The status should be success
      The stderr should include "dry-run"
    End
  End

  # ---------------------------------------------------------------------------
  # deploy.argocd.rollback - --dry-run via explicit flag
  # ---------------------------------------------------------------------------
  Describe "deploy.argocd.rollback - --dry-run via flag"
    setup_rollback_dryrun_flag() {
      mock.setup
      mock.create_logging "argocd" "${MOCK_BIN}/mock.log"
      mock.activate
      unset BRIK_DRY_RUN 2>/dev/null
    }
    cleanup_rollback_dryrun_flag() {
      mock.cleanup
      unset BRIK_DRY_RUN 2>/dev/null
    }
    Before 'setup_rollback_dryrun_flag'
    After 'cleanup_rollback_dryrun_flag'

    It "logs dry-run via --dry-run flag"
      When call deploy.argocd.rollback --app my-app --dry-run
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
        . "$BRIK_DEPLOYMENTS_LIB/argocd.sh"
        declare -f deploy.argocd.sync >/dev/null && echo "ok" || echo "missing"
      }
      When call double_include
      The output should equal "ok"
    End
  End
End
