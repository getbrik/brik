Describe "notify.sh"
  Include "$BRIK_RUNTIME_LIB/logging.sh"
  Include "$BRIK_RUNTIME_LIB/tools.sh"
  Include "$BRIK_CORE_LIB/notify.sh"
  Include "$BRIK_HOME/runtime/bash/spec/support/mock_helper.sh"

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
    It "returns 2 when no message specified"
      When call notify.webhook
      The status should equal 2
      The stderr should include "webhook message is required"
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
End
