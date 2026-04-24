Describe "stages.notify"
  Include "$BRIK_HOME/lib/pipeline/stage.sh"
  Include "$BRIK_HOME/lib/pipeline/loader.sh"
  Include "$BRIK_HOME/lib/transverse/config.sh"
  Include "$BRIK_HOME/lib/stages/notify.sh"

  setup_env() {
    export BRIK_CONFIG_FILE
    BRIK_CONFIG_FILE="$(mktemp)"
    printf 'version: 1\nproject:\n  name: test-project\n  stack: node\n' > "$BRIK_CONFIG_FILE"
    export BRIK_WORKSPACE
    BRIK_WORKSPACE="$(mktemp -d)"
    export BRIK_PROJECT_DIR="$BRIK_WORKSPACE"
    export BRIK_PLATFORM="gitlab"
    export BRIK_COMMIT_REF="main"
    export BRIK_COMMIT_SHORT_SHA="abc123d"
    # Isolate BRIK_LOG_DIR so a stale pipeline-report.md left by earlier specs
    # (e.g. report_spec) doesn't get `cat`'d by notify.sh, masking the fallback
    # banner the notify tests assert against.
    _NOTIFY_ORIG_LOG_DIR="${BRIK_LOG_DIR:-}"
    export BRIK_LOG_DIR
    BRIK_LOG_DIR="$(mktemp -d)"
    config.read "$BRIK_CONFIG_FILE" >/dev/null 2>&1 || true
  }
  cleanup_env() {
    rm -f "$BRIK_CONFIG_FILE"
    rm -rf "$BRIK_WORKSPACE" "$BRIK_LOG_DIR"
    if [[ -n "${_NOTIFY_ORIG_LOG_DIR}" ]]; then
      export BRIK_LOG_DIR="${_NOTIFY_ORIG_LOG_DIR}"
    else
      unset BRIK_LOG_DIR
    fi
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

  Describe "pipeline-report copy into workspace"
    # CI templates declare artifacts: paths: [brik-artifacts/]; if notify
    # leaves the report only under BRIK_LOG_DIR (outside the workspace),
    # GitLab/Jenkins emit "no matching files" warnings on every run.
    setup_report() {
      printf '# Pipeline Report\n' > "${BRIK_LOG_DIR}/pipeline-report.md"
      printf '{"stages":[]}\n'      > "${BRIK_LOG_DIR}/pipeline-report.json"
    }
    Before 'setup_report'

    It "copies pipeline-report.md into workspace brik-artifacts/"
      run_notify_copy_md() {
        local ctx
        ctx="$(context.create "notify")" 2>/dev/null || ctx="$(mktemp)"
        stages.notify "$ctx" >/dev/null 2>&1
        [[ -f "${BRIK_WORKSPACE}/brik-artifacts/pipeline-report.md" ]]
      }
      When call run_notify_copy_md
      The status should be success
    End

    It "copies pipeline-report.json into workspace brik-artifacts/"
      run_notify_copy_json() {
        local ctx
        ctx="$(context.create "notify")" 2>/dev/null || ctx="$(mktemp)"
        stages.notify "$ctx" >/dev/null 2>&1
        [[ -f "${BRIK_WORKSPACE}/brik-artifacts/pipeline-report.json" ]]
      }
      When call run_notify_copy_json
      The status should be success
    End

    It "logs a warning when the copy into brik-artifacts/ fails"
      # Make brik-artifacts/ unwritable so cp must fail. The stage must
      # still return 0 (notification is best-effort) but emit a WARN so
      # operators see the I/O problem instead of a silent skip.
      run_notify_copy_failure() {
        mkdir -p "${BRIK_WORKSPACE}/brik-artifacts"
        chmod a-w "${BRIK_WORKSPACE}/brik-artifacts"
        local ctx
        ctx="$(context.create "notify")" 2>/dev/null || ctx="$(mktemp)"
        stages.notify "$ctx"
        local rc=$?
        chmod u+w "${BRIK_WORKSPACE}/brik-artifacts"
        return $rc
      }
      When call run_notify_copy_failure
      The status should be success
      The error should include "WARN"
      The error should include "brik-artifacts"
      The output should be present
    End
  End

  Describe "pipeline-report copy when reports absent"
    It "does not create brik-artifacts/ when no report exists"
      run_notify_no_report() {
        local ctx
        ctx="$(context.create "notify")" 2>/dev/null || ctx="$(mktemp)"
        stages.notify "$ctx" >/dev/null 2>&1
        [[ ! -d "${BRIK_WORKSPACE}/brik-artifacts" ]]
      }
      When call run_notify_no_report
      The status should be success
    End
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
    on: always
YAML
      config.read "$BRIK_CONFIG_FILE" >/dev/null 2>&1 || true
      # Mock notify module as loaded + mock notify.send
      eval "_BRIK_MODULE_NOTIFY_LOADED=1"
      export _BRIK_MODULE_NOTIFY_LOADED
      NOTIFY_SEND_LOG="$(mktemp)"
      eval "notify.send() { printf '%s\n' \"\$*\" >> \"$NOTIFY_SEND_LOG\"; return 0; }"
    }
    cleanup_slack() {
      unset -f notify.send 2>/dev/null
      unset _BRIK_MODULE_NOTIFY_LOADED
      rm -f "$NOTIFY_SEND_LOG"
    }
    Before 'setup_slack'
    After 'cleanup_slack'

    It "sends slack notification"
      run_notify_slack() {
        local ctx
        ctx="$(context.create "notify")" 2>/dev/null || ctx="$(mktemp)"
        stages.notify "$ctx" >/dev/null 2>/dev/null
        grep -q "\-\-channel slack" "$NOTIFY_SEND_LOG"
      }
      When call run_notify_slack
      The status should be success
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
      eval "_BRIK_MODULE_NOTIFY_LOADED=1"
      export _BRIK_MODULE_NOTIFY_LOADED
      NOTIFY_SEND_LOG="$(mktemp)"
      eval "notify.send() { printf '%s\n' \"\$*\" >> \"$NOTIFY_SEND_LOG\"; return 0; }"
    }
    cleanup_email() {
      unset -f notify.send 2>/dev/null
      unset _BRIK_MODULE_NOTIFY_LOADED
      rm -f "$NOTIFY_SEND_LOG"
    }
    Before 'setup_email'
    After 'cleanup_email'

    It "sends email notification"
      run_notify_email() {
        local ctx
        ctx="$(context.create "notify")" 2>/dev/null || ctx="$(mktemp)"
        stages.notify "$ctx" >/dev/null 2>/dev/null
        grep -q "\-\-channel email" "$NOTIFY_SEND_LOG"
      }
      When call run_notify_email
      The status should be success
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
    on: always
YAML
      config.read "$BRIK_CONFIG_FILE" >/dev/null 2>&1 || true
      eval "_BRIK_MODULE_NOTIFY_LOADED=1"
      export _BRIK_MODULE_NOTIFY_LOADED
      NOTIFY_SEND_LOG="$(mktemp)"
      eval "notify.send() { printf '%s\n' \"\$*\" >> \"$NOTIFY_SEND_LOG\"; return 0; }"
    }
    cleanup_webhook() {
      unset -f notify.send 2>/dev/null
      unset _BRIK_MODULE_NOTIFY_LOADED
      rm -f "$NOTIFY_SEND_LOG"
    }
    Before 'setup_webhook'
    After 'cleanup_webhook'

    It "sends webhook notification"
      run_notify_webhook() {
        local ctx
        ctx="$(context.create "notify")" 2>/dev/null || ctx="$(mktemp)"
        stages.notify "$ctx" >/dev/null 2>/dev/null
        grep -q "\-\-channel webhook" "$NOTIFY_SEND_LOG"
      }
      When call run_notify_webhook
      The status should be success
    End
  End
End
