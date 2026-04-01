Describe "stages.notify"
  Include "$BRIK_HOME/runtime/bash/lib/runtime/stage.sh"
  Include "$BRIK_HOME/runtime/bash/lib/core/_loader.sh"
  Include "$BRIK_HOME/runtime/bash/lib/core/config.sh"
  Include "$BRIK_HOME/runtime/bash/lib/stages/notify.sh"

  setup_env() {
    export BRIK_CONFIG_FILE
    BRIK_CONFIG_FILE="$(mktemp)"
    printf 'version: 1\nproject:\n  name: test-project\n  stack: node\n' > "$BRIK_CONFIG_FILE"
    export BRIK_LOG_DIR
    BRIK_LOG_DIR="$(mktemp -d)"
    export BRIK_WORKSPACE
    BRIK_WORKSPACE="$(mktemp -d)"
    export BRIK_PROJECT_DIR="$BRIK_WORKSPACE"
    export BRIK_PLATFORM="gitlab"
    export BRIK_COMMIT_REF="main"
    export BRIK_COMMIT_SHORT_SHA="abc123d"
    config.read "$BRIK_CONFIG_FILE" >/dev/null 2>&1 || true
  }
  cleanup_env() {
    rm -f "$BRIK_CONFIG_FILE"
    rm -rf "$BRIK_LOG_DIR" "$BRIK_WORKSPACE"
    unset BRIK_NOTIFY_SLACK_CHANNEL BRIK_NOTIFY_EMAIL_TO BRIK_NOTIFY_WEBHOOK_URL 2>/dev/null || true
  }
  Before 'setup_env'
  After 'cleanup_env'

  It "is callable as a function"
    callable_check() { declare -f stages.notify >/dev/null; }
    When call callable_check
    The status should be success
  End

  It "returns 0 on success"
    run_notify() {
      local ctx
      ctx="$(context.create "notify")" 2>/dev/null || ctx="$(mktemp)"
      stages.notify "$ctx" >/dev/null 2>&1
    }
    When call run_notify
    The status should be success
  End

  It "prints Pipeline Summary with project name"
    run_notify_output() {
      local ctx
      ctx="$(context.create "notify")" 2>/dev/null || ctx="$(mktemp)"
      stages.notify "$ctx"
    }
    When call run_notify_output
    The output should include "Pipeline Summary"
    The output should include "test-project"
    The error should be present
  End

  It "uses BRIK_PLATFORM instead of hardcoded platform"
    run_notify_platform() {
      local ctx
      ctx="$(context.create "notify")" 2>/dev/null || ctx="$(mktemp)"
      stages.notify "$ctx"
    }
    When call run_notify_platform
    The output should include "gitlab"
    The error should be present
  End

  It "uses BRIK_COMMIT_REF for ref display"
    run_notify_ref() {
      local ctx
      ctx="$(context.create "notify")" 2>/dev/null || ctx="$(mktemp)"
      stages.notify "$ctx"
    }
    When call run_notify_ref
    The output should include "main"
    The error should be present
  End

  It "uses BRIK_COMMIT_SHORT_SHA for SHA display"
    run_notify_sha() {
      local ctx
      ctx="$(context.create "notify")" 2>/dev/null || ctx="$(mktemp)"
      stages.notify "$ctx"
    }
    When call run_notify_sha
    The output should include "abc123d"
    The error should be present
  End

  Describe "with slack notification configured"
    setup_slack() {
      cat > "$BRIK_CONFIG_FILE" <<'YAML'
version: 1
project:
  name: test-project
notify:
  slack:
    channel: "#builds"
    on: failure
YAML
      config.read "$BRIK_CONFIG_FILE" >/dev/null 2>&1 || true
    }
    Before 'setup_slack'

    It "logs slack channel notification"
      run_notify_slack() {
        local ctx
        ctx="$(context.create "notify")" 2>/dev/null || ctx="$(mktemp)"
        stages.notify "$ctx" >/dev/null
      }
      When call run_notify_slack
      The error should include "would notify slack channel: #builds"
    End
  End

  Describe "with email notification configured"
    setup_email() {
      cat > "$BRIK_CONFIG_FILE" <<'YAML'
version: 1
project:
  name: test-project
notify:
  email:
    to: team@example.com
    on: always
YAML
      config.read "$BRIK_CONFIG_FILE" >/dev/null 2>&1 || true
    }
    Before 'setup_email'

    It "logs email notification"
      run_notify_email() {
        local ctx
        ctx="$(context.create "notify")" 2>/dev/null || ctx="$(mktemp)"
        stages.notify "$ctx" >/dev/null
      }
      When call run_notify_email
      The error should include "would notify email: team@example.com"
    End
  End

  Describe "with webhook notification configured"
    setup_webhook() {
      cat > "$BRIK_CONFIG_FILE" <<'YAML'
version: 1
project:
  name: test-project
notify:
  webhook:
    url: https://hooks.example.com/notify
    on: success
YAML
      config.read "$BRIK_CONFIG_FILE" >/dev/null 2>&1 || true
    }
    Before 'setup_webhook'

    It "logs webhook notification"
      run_notify_webhook() {
        local ctx
        ctx="$(context.create "notify")" 2>/dev/null || ctx="$(mktemp)"
        stages.notify "$ctx" >/dev/null
      }
      When call run_notify_webhook
      The error should include "would notify webhook: https://hooks.example.com/notify"
    End
  End
End
