Describe "stages/notify.sh - internals"
  Include "$BRIK_PIPELINE_LIB/logging.sh"
  Include "$BRIK_PIPELINE_LIB/tools.sh"
  Include "$BRIK_TRANSVERSE_LIB/env.sh"
  Include "$BRIK_TRANSVERSE_LIB/infra.sh"
  Include "$BRIK_STAGES_LIB/notify.sh"
  Include "$BRIK_HOME/spec/support/mock_helper.sh"

  brik.use() { :; }

  Describe "notify.send"
    It "returns 2 when no channel specified"
      When call notify.send --message "test"
      The status should equal 2
      The stderr should include "notification channel is required"
    End

    It "returns 2 when no message specified"
      When call notify.send --channel slack
      The status should equal 2
      The stderr should include "notification message is required"
    End

    It "returns 7 for unsupported channel"
      When call notify.send --channel sms --message "test"
      The status should equal 7
      The stderr should include "unsupported notification channel"
    End

    It "returns 2 for unknown option"
      When call notify.send --badopt foo
      The status should equal 2
      The stderr should include "unknown option"
    End
  End

  Describe "notify.slack"
    It "returns 2 when no message specified"
      When call notify.slack
      The status should equal 2
      The stderr should include "message is required"
    End

    It "skips when webhook variable is not set"
      When call notify.slack --message "test"
      The status should be success
      The stderr should include "skipping"
    End

    Describe "dry-run mode"
      setup_dryrun() {
        export SLACK_WEBHOOK_URL="https://hooks.slack.com/test"
      }
      cleanup_dryrun() {
        unset SLACK_WEBHOOK_URL
      }
      Before 'setup_dryrun'
      After 'cleanup_dryrun'

      It "logs dry-run message"
        When call notify.slack --message "test" --dry-run
        The status should be success
        The stderr should include "[dry-run] slack notification"
      End
    End

    Describe "with mock curl"
      setup_curl() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_curl.log"
        mock.create_logging "curl" "$MOCK_LOG"
        mock.activate
        export SLACK_WEBHOOK_URL="https://hooks.slack.com/test"
      }
      cleanup_curl() {
        mock.cleanup
        unset SLACK_WEBHOOK_URL
        rm -rf "$TEST_WS"
      }
      Before 'setup_curl'
      After 'cleanup_curl'

      It "sends notification via curl"
        invoke_slack() {
          notify.slack --message "deploy success" 2>/dev/null || return 1
          grep -q "curl" "$MOCK_LOG"
        }
        When call invoke_slack
        The status should be success
      End

      It "includes webhook URL in curl call"
        invoke_url() {
          notify.slack --message "test" 2>/dev/null || return 1
          grep -q "hooks.slack.com" "$MOCK_LOG"
        }
        When call invoke_url
        The status should be success
      End

      It "uses custom webhook variable"
        invoke_custom_var() {
          export MY_SLACK_HOOK="https://custom.slack.com/hook"
          notify.slack --message "test" --webhook-var "MY_SLACK_HOOK" 2>/dev/null || return 1
          grep -q "custom.slack.com" "$MOCK_LOG"
        }
        When call invoke_custom_var
        The status should be success
      End

      It "logs success"
        When call notify.slack --message "test"
        The status should be success
        The stderr should include "slack notification sent"
      End
    End

    Describe "with failing curl"
      setup_fail() {
        mock.setup
        mock.create_exit "curl" 1
        mock.activate
        export SLACK_WEBHOOK_URL="https://hooks.slack.com/test"
      }
      cleanup_fail() {
        mock.cleanup
        unset SLACK_WEBHOOK_URL
      }
      Before 'setup_fail'
      After 'cleanup_fail'

      It "returns 5 when curl fails"
        When call notify.slack --message "test"
        The status should equal 5
        The stderr should include "slack notification failed"
      End
    End
  End

  Describe "notify.email"
    It "returns 2 when no body specified"
      When call notify.email
      The status should equal 2
      The stderr should include "email body is required"
    End

    It "skips when no recipient configured"
      When call notify.email --body "test"
      The status should be success
      The stderr should include "skipping"
    End

    Describe "dry-run mode"
      It "logs dry-run message"
        When call notify.email --body "test" --to "user@example.com" --dry-run
        The status should be success
        The stderr should include "[dry-run] email to user@example.com"
      End
    End

    Describe "with mock sendmail"
      setup_sendmail() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_sendmail.log"
        mock.create_script "sendmail" "cat > \"$MOCK_LOG\""
        mock.activate
      }
      cleanup_sendmail() {
        mock.cleanup
        unset BRIK_NOTIFY_EMAIL_TO
        rm -rf "$TEST_WS"
      }
      Before 'setup_sendmail'
      After 'cleanup_sendmail'

      It "sends email via sendmail"
        invoke_email() {
          notify.email --body "test message" --to "user@example.com" 2>/dev/null || return 1
          grep -q "test message" "$MOCK_LOG"
        }
        When call invoke_email
        The status should be success
      End

      It "reads recipient from BRIK_NOTIFY_EMAIL_TO"
        invoke_env_to() {
          export BRIK_NOTIFY_EMAIL_TO="env@example.com"
          notify.email --body "test" 2>/dev/null || return 1
          grep -q "env@example.com" "$MOCK_LOG"
        }
        When call invoke_env_to
        The status should be success
      End
    End
  End

  Describe "notify.webhook"
    It "returns 2 when neither message nor payload is specified"
      When call notify.webhook
      The status should equal 2
      The stderr should include "webhook message or payload is required"
    End

    Describe "referential Notification endpoint (service webhook)"
      setup_ep() {
        mock.setup
        mock.infra.setup
        mkdir -p "$BRIK_INFRA_DIR/endpoints"
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_curl.log"
        mock.create_logging "curl" "$MOCK_LOG"
        mock.activate
        cat > "$BRIK_INFRA_DIR/endpoints/notify.yml" <<'YAML'
apiVersion: brik.dev/referential/v1
kind: Notification
name: notify
service: webhook
url: https://hooks.lab:9443/notify
tls:
  trust: custom-ca
YAML
        mkdir -p "$BRIK_INFRA_DIR/trust/ca/hooks.lab"
        : > "$BRIK_INFRA_DIR/trust/ca/hooks.lab/ca.crt"
      }
      cleanup_ep() {
        mock.cleanup
        mock.infra.teardown
        rm -rf "$TEST_WS"
      }
      Before 'setup_ep'
      After 'cleanup_ep'

      It "sends to the declared url with the declared CA bundle"
        invoke_ep() {
          notify.webhook --message "deploy done" || return 1
          cat "$MOCK_LOG"
        }
        When call invoke_ep
        The status should be success
        The output should include "https://hooks.lab:9443/notify"
        The output should include "--cacert ${BRIK_INFRA_DIR}/trust/ca/hooks.lab/ca.crt"
        The stderr should include "webhook notification sent"
      End

      It "fails closed when the legacy variable contradicts the endpoint"
        invoke_conflict() {
          BRIK_NOTIFY_WEBHOOK_URL="https://elsewhere/hook" notify.webhook --message "x"
        }
        When call invoke_conflict
        The status should equal 7
        The stderr should include "contradicts"
      End
    End

    It "skips when no URL configured"
      When call notify.webhook --message "test"
      The status should be success
      The stderr should include "skipping"
    End

    Describe "dry-run mode"
      setup_dryrun() {
        export BRIK_NOTIFY_WEBHOOK_URL="https://hooks.example.com/notify"
      }
      cleanup_dryrun() {
        unset BRIK_NOTIFY_WEBHOOK_URL
      }
      Before 'setup_dryrun'
      After 'cleanup_dryrun'

      It "logs dry-run message"
        When call notify.webhook --message "test" --dry-run
        The status should be success
        The stderr should include "[dry-run] webhook POST"
      End
    End

    Describe "with mock curl"
      setup_curl() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_curl.log"
        mock.create_logging "curl" "$MOCK_LOG"
        mock.activate
        export BRIK_NOTIFY_WEBHOOK_URL="https://hooks.example.com/notify"
      }
      cleanup_curl() {
        mock.cleanup
        unset BRIK_NOTIFY_WEBHOOK_URL
        rm -rf "$TEST_WS"
      }
      Before 'setup_curl'
      After 'cleanup_curl'

      It "sends webhook via curl"
        invoke_webhook() {
          notify.webhook --message "deploy done" 2>/dev/null || return 1
          grep -q "hooks.example.com" "$MOCK_LOG"
        }
        When call invoke_webhook
        The status should be success
      End

      It "resolves URL from variable"
        invoke_var_url() {
          export MY_HOOK_URL="https://custom.example.com/hook"
          notify.webhook --message "test" --url-var "MY_HOOK_URL" 2>/dev/null || return 1
          grep -q "custom.example.com" "$MOCK_LOG"
        }
        When call invoke_var_url
        The status should be success
      End

      It "posts a structured payload verbatim with --payload"
        invoke_payload() {
          notify.webhook --payload '{"event":"deploy","status":"success","digest":"sha256:abc"}' 2>/dev/null || return 1
          grep -q '"event":"deploy"' "$MOCK_LOG"
        }
        When call invoke_payload
        The status should be success
      End

      It "rejects a payload that is not valid JSON"
        When call notify.webhook --payload '{not json'
        The status should equal 2
        The stderr should include "not valid JSON"
      End
    End
  End

  Describe "notify.webhook_configured"
    It "succeeds when the variable is set"
      probe_configured() {
        BRIK_NOTIFY_WEBHOOK_URL="https://hooks.example.com/x" notify.webhook_configured
      }
      When call probe_configured
      The status should be success
    End

    It "fails when nothing is configured"
      probe_unconfigured() {
        unset BRIK_NOTIFY_WEBHOOK_URL
        notify.webhook_configured
      }
      When call probe_unconfigured
      The status should be failure
    End
  End

  Describe "notify.slack color mapping"
    Describe "with mock curl"
      setup_color() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_curl.log"
        mock.create_logging "curl" "$MOCK_LOG"
        mock.activate
        export SLACK_WEBHOOK_URL="https://hooks.slack.com/test"
      }
      cleanup_color() {
        mock.cleanup
        unset SLACK_WEBHOOK_URL
        rm -rf "$TEST_WS"
      }
      Before 'setup_color'
      After 'cleanup_color'

      It "uses gold color for warn level"
        invoke_warn() {
          notify.slack --message "warning" --level warn 2>/dev/null || return 1
          grep -q "daa520" "$MOCK_LOG"
        }
        When call invoke_warn
        The status should be success
      End

      It "uses red color for error level"
        invoke_error() {
          notify.slack --message "error" --level error 2>/dev/null || return 1
          grep -q "cc0000" "$MOCK_LOG"
        }
        When call invoke_error
        The status should be success
      End

      It "includes channel in payload when specified"
        invoke_channel() {
          notify.slack --message "test" --channel "#deploys" 2>/dev/null || return 1
          grep -q "deploys" "$MOCK_LOG"
        }
        When call invoke_channel
        The status should be success
      End
    End
  End

  Describe "notify.email with mail fallback"
    Describe "with mock mail"
      setup_mail() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_mail.log"
        mock.create_script "mail" "printf 'mail %s\n' \"\$*\" >> \"$MOCK_LOG\"
cat >> \"$MOCK_LOG\""
        # Hybrid isolation: exclude sendmail from PATH
        export PATH="${MOCK_BIN}:/usr/bin:/bin"
      }
      cleanup_mail() {
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_mail'
      After 'cleanup_mail'

      It "falls back to mail command"
        invoke_mail() {
          notify.email --body "test body" --to "user@example.com" 2>/dev/null || return 1
          grep -q "mail" "$MOCK_LOG"
        }
        When call invoke_mail
        The status should be success
      End

      It "uses custom subject"
        invoke_subject() {
          notify.email --body "test" --to "user@example.com" --subject "Custom Subject" 2>/dev/null || return 1
          grep -q "Custom Subject" "$MOCK_LOG"
        }
        When call invoke_subject
        The status should be success
      End
    End
  End

  Describe "notify.webhook with --url option"
    Describe "with mock curl"
      setup_url() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_curl.log"
        mock.create_logging "curl" "$MOCK_LOG"
        mock.activate
      }
      cleanup_url() {
        mock.cleanup
        unset BRIK_NOTIFY_WEBHOOK_URL
        rm -rf "$TEST_WS"
      }
      Before 'setup_url'
      After 'cleanup_url'

      It "uses --url option"
        invoke_url_opt() {
          notify.webhook --message "test" --url "https://direct.example.com/hook" 2>/dev/null || return 1
          grep -q "direct.example.com" "$MOCK_LOG"
        }
        When call invoke_url_opt
        The status should be success
      End

      It "logs webhook sent"
        invoke_log() {
          notify.webhook --message "test" --url "https://direct.example.com/hook"
        }
        When call invoke_log
        The status should be success
        The stderr should include "webhook notification sent"
      End
    End

    Describe "with failing curl"
      setup_fail_webhook() {
        mock.setup
        mock.create_exit "curl" 1
        mock.activate
        export BRIK_NOTIFY_WEBHOOK_URL="https://hooks.example.com/notify"
      }
      cleanup_fail_webhook() {
        mock.cleanup
        unset BRIK_NOTIFY_WEBHOOK_URL
      }
      Before 'setup_fail_webhook'
      After 'cleanup_fail_webhook'

      It "returns 5 when curl fails"
        When call notify.webhook --message "test"
        The status should equal 5
        The stderr should include "webhook notification failed"
      End
    End
  End

  Describe "notify.send dispatches correctly"
    Describe "dispatches to slack"
      It "calls notify.slack via send"
        invoke_dispatch_slack() {
          export SLACK_WEBHOOK_URL="https://hooks.slack.com/test"
          notify.slack() { printf 'slack_called\n'; return 0; }
          notify.send --channel slack --message "test" 2>/dev/null
        }
        When call invoke_dispatch_slack
        The output should include "slack_called"
      End
    End

    Describe "dispatches to email"
      It "calls notify.email via send"
        invoke_dispatch_email() {
          notify.email() { printf 'email_called\n'; return 0; }
          notify.send --channel email --message "test" 2>/dev/null
        }
        When call invoke_dispatch_email
        The output should include "email_called"
      End
    End

    Describe "dispatches to webhook"
      It "calls notify.webhook via send"
        invoke_dispatch_webhook() {
          notify.webhook() { printf 'webhook_called\n'; return 0; }
          notify.send --channel webhook --message "test" 2>/dev/null
        }
        When call invoke_dispatch_webhook
        The output should include "webhook_called"
      End
    End

    Describe "passes dry-run to channels"
      It "passes --dry-run to slack"
        invoke_dry_slack() {
          export SLACK_WEBHOOK_URL="https://hooks.slack.com/test"
          notify.send --channel slack --message "test" --dry-run 2>&1
        }
        When call invoke_dry_slack
        The output should include "[dry-run]"
      End
    End
  End

  Describe "_notify._should_send"
    It "returns 0 for always condition"
      When call _notify._should_send "always" "success"
      The status should be success
    End

    It "returns 0 when condition matches status"
      When call _notify._should_send "success" "success"
      The status should be success
    End

    It "returns 1 when condition does not match status"
      When call _notify._should_send "failure" "success"
      The status should equal 1
    End

    It "returns 0 for failure condition with failed status"
      When call _notify._should_send "failure" "failed"
      The status should be success
    End

    It "returns 0 for always condition with failed status"
      When call _notify._should_send "always" "failed"
      The status should be success
    End

    It "returns 1 for success condition with failed status"
      When call _notify._should_send "success" "failed"
      The status should equal 1
    End
  End

  Describe "_notify._build_notify_metadata"
    clear_notify_env() {
      unset BRIK_NOTIFY_SLACK_CHANNEL BRIK_NOTIFY_SLACK_ON
      unset BRIK_NOTIFY_EMAIL_TO BRIK_NOTIFY_EMAIL_ON
      unset BRIK_NOTIFY_WEBHOOK_URL BRIK_NOTIFY_WEBHOOK_ON
    }
    Before 'clear_notify_env'

    It "reports every channel as not configured when no env var is set"
      When call _notify._build_notify_metadata "success"
      The status should be success
      The output should include '"configured":false'
      The output should include '"would_send":false'
      # Three channels emitted in fixed order: slack, email, webhook.
      The output should include '"type":"slack"'
      The output should include '"type":"email"'
      The output should include '"type":"webhook"'
    End

    It "marks slack as configured + would_send when the channel env var is set on a success run"
      export BRIK_NOTIFY_SLACK_CHANNEL="#brik-ci"
      When call _notify._build_notify_metadata "success"
      The status should be success
      The output should include '"type":"slack","configured":true,"on":"always","would_send":true'
      unset BRIK_NOTIFY_SLACK_CHANNEL
    End

    It "marks email as configured + would_send filtered by on=failure on an error run"
      export BRIK_NOTIFY_EMAIL_TO="ops@example.test"
      export BRIK_NOTIFY_EMAIL_ON="failure"
      When call _notify._build_notify_metadata "error"
      The status should be success
      The output should include '"type":"email","configured":true,"on":"failure","would_send":true'
      unset BRIK_NOTIFY_EMAIL_TO BRIK_NOTIFY_EMAIL_ON
    End

    It "marks webhook configured but would_send=false when on=failure on a success run"
      export BRIK_NOTIFY_WEBHOOK_URL="https://hooks.example.test/n"
      export BRIK_NOTIFY_WEBHOOK_ON="failure"
      When call _notify._build_notify_metadata "success"
      The status should be success
      The output should include '"type":"webhook","configured":true,"on":"failure","would_send":false'
      unset BRIK_NOTIFY_WEBHOOK_URL BRIK_NOTIFY_WEBHOOK_ON
    End

    It "emits gatekeeper.decision=pass on success"
      When call _notify._build_notify_metadata "success"
      The status should be success
      The output should include '"gatekeeper":{"decision":"pass","business_status":"success"}'
    End

    It "emits gatekeeper.decision=pass on warning (warning is not error)"
      When call _notify._build_notify_metadata "warning"
      The status should be success
      The output should include '"decision":"pass"'
      The output should include '"business_status":"warning"'
    End

    It "emits gatekeeper.decision=fail when business_status is error"
      When call _notify._build_notify_metadata "error"
      The status should be success
      The output should include '"decision":"fail"'
      The output should include '"business_status":"error"'
    End
  End

  Describe "_notify._inject_notify_metadata"
    setup_aggregate() {
      INJ_TMP="$(mktemp -d)"
      AGG="$INJ_TMP/aggregate-report.json"
      cat > "$AGG" <<'JSON'
{"schema_version":"1.1",
 "pipeline":{"id":"42","platform":"local","project":"demo",
   "started_at":"2026-05-14T10:00:00+0000","finished_at":"2026-05-14T10:05:00+0000",
   "status":"success","context":"snapshot","business":{"status":"success"}},
 "stages":[],
 "summary":{"stages":{"total":0,"passed":0,"failed":0,"skipped":0},
            "business":{"success_count":0,"warning_count":0,"error_count":0}}}
JSON
    }
    cleanup_aggregate() { rm -rf "$INJ_TMP"; }
    Before 'setup_aggregate'
    After  'cleanup_aggregate'

    It "patches the aggregate JSON with pipeline.notify when invoked"
      unset BRIK_NOTIFY_SLACK_CHANNEL BRIK_NOTIFY_EMAIL_TO BRIK_NOTIFY_WEBHOOK_URL
      When call _notify._inject_notify_metadata "$AGG" "success"
      The status should be success
      # The patched JSON now carries .pipeline.notify with channels[] and gatekeeper.
      The contents of file "$AGG" should include '"notify"'
      The contents of file "$AGG" should include '"channels"'
      The contents of file "$AGG" should include '"gatekeeper"'
      The contents of file "$AGG" should include '"decision":"pass"'
    End

    It "marks decision=fail when business_status is error"
      When call _notify._inject_notify_metadata "$AGG" "error"
      The status should be success
      The contents of file "$AGG" should include '"decision":"fail"'
      The contents of file "$AGG" should include '"business_status":"error"'
    End

    It "no-ops gracefully when the aggregate file is missing"
      When call _notify._inject_notify_metadata "/nonexistent/path.json" "success"
      The status should be success
    End
  End
End
