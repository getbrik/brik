Describe "hooks.sh"
  Include "$BRIK_RUNTIME_LIB/hooks.sh"

  Describe "hook.pre_stage"
    It "returns 0 when no hook script exists (no-op)"
      export BRIK_PROJECT_DIR="/nonexistent"
      export BRIK_HOME="/nonexistent"
      When call hook.pre_stage "build" "/tmp/ctx" "/tmp/log"
      The status should be success
    End

    Describe "with a project hook script"
      setup_hook() {
        HOOK_DIR="$(mktemp -d)"
        mkdir -p "${HOOK_DIR}/.brik/hooks"
        cat > "${HOOK_DIR}/.brik/hooks/pre_stage.sh" << 'HOOKEOF'
pre_stage() { printf 'pre_stage_called\n'; return 0; }
HOOKEOF
        export BRIK_PROJECT_DIR="$HOOK_DIR"
      }
      cleanup_hook() { rm -rf "$HOOK_DIR"; }
      Before 'setup_hook'
      After 'cleanup_hook'

      It "executes the hook and returns its output"
        When call hook.pre_stage "build" "/tmp/ctx" "/tmp/log"
        The status should be success
        The output should equal "pre_stage_called"
      End
    End

    Describe "with a failing hook script"
      setup_failing_hook() {
        HOOK_DIR="$(mktemp -d)"
        mkdir -p "${HOOK_DIR}/.brik/hooks"
        cat > "${HOOK_DIR}/.brik/hooks/pre_stage.sh" << 'HOOKEOF'
pre_stage() { return 2; }
HOOKEOF
        export BRIK_PROJECT_DIR="$HOOK_DIR"
      }
      cleanup_failing_hook() { rm -rf "$HOOK_DIR"; }
      Before 'setup_failing_hook'
      After 'cleanup_failing_hook'

      It "propagates non-zero return from hook"
        When call hook.pre_stage "build" "/tmp/ctx" "/tmp/log"
        The status should equal 2
      End
    End

    Describe "with brik.yml inline pre hook"
      setup_config_hook() {
        HOOK_DIR="$(mktemp -d)"
        export BRIK_PROJECT_DIR="$HOOK_DIR"
        export BRIK_HOME="/nonexistent"
        export BRIK_HOOK_PRE_BUILD="printf 'config_pre_hook_called\n'"
      }
      cleanup_config_hook() {
        rm -rf "$HOOK_DIR"
        unset BRIK_HOOK_PRE_BUILD 2>/dev/null || true
      }
      Before 'setup_config_hook'
      After 'cleanup_config_hook'

      It "executes the brik.yml inline hook"
        When call hook.pre_stage "build" "/tmp/ctx" "/tmp/log"
        The status should be success
        The output should equal "config_pre_hook_called"
      End
    End
  End

  Describe "hook.on_success"
    It "returns 0 when no hook exists"
      export BRIK_PROJECT_DIR="/nonexistent"
      export BRIK_HOME="/nonexistent"
      When call hook.on_success "build" "/tmp/ctx" "/tmp/log"
      The status should be success
    End

    Describe "with a success hook script"
      setup_success_hook() {
        HOOK_DIR="$(mktemp -d)"
        MARKER_FILE="$(mktemp)"
        mkdir -p "${HOOK_DIR}/.brik/hooks"
        cat > "${HOOK_DIR}/.brik/hooks/on_success.sh" << HOOKEOF
on_success() { printf '%s\n' "\$*" > "$MARKER_FILE"; return 0; }
HOOKEOF
        export BRIK_PROJECT_DIR="$HOOK_DIR"
      }
      cleanup_success_hook() { rm -rf "$HOOK_DIR" "$MARKER_FILE"; }
      Before 'setup_success_hook'
      After 'cleanup_success_hook'

      It "executes the hook with correct arguments"
        verify_success_args() {
          hook.on_success "deploy" "/tmp/ctx" "/tmp/log" 2>/dev/null
          grep -q "deploy /tmp/ctx /tmp/log" "$MARKER_FILE"
        }
        When call verify_success_args
        The status should be success
      End
    End

    Describe "with a failing success hook"
      setup_fail_success() {
        HOOK_DIR="$(mktemp -d)"
        mkdir -p "${HOOK_DIR}/.brik/hooks"
        cat > "${HOOK_DIR}/.brik/hooks/on_success.sh" << 'HOOKEOF'
on_success() { return 3; }
HOOKEOF
        export BRIK_PROJECT_DIR="$HOOK_DIR"
      }
      cleanup_fail_success() { rm -rf "$HOOK_DIR"; }
      Before 'setup_fail_success'
      After 'cleanup_fail_success'

      It "propagates the hook return code"
        When call hook.on_success "build" "/tmp/ctx" "/tmp/log"
        The status should equal 3
      End
    End
  End

  Describe "hook.on_failure"
    It "returns 0 when no hook exists"
      export BRIK_PROJECT_DIR="/nonexistent"
      export BRIK_HOME="/nonexistent"
      When call hook.on_failure "build" "/tmp/ctx" "/tmp/log" "5"
      The status should be success
    End

    Describe "with a failure hook script"
      setup_failure_hook() {
        HOOK_DIR="$(mktemp -d)"
        MARKER_FILE="$(mktemp)"
        mkdir -p "${HOOK_DIR}/.brik/hooks"
        cat > "${HOOK_DIR}/.brik/hooks/on_failure.sh" << HOOKEOF
on_failure() { printf '%s\n' "\$*" > "$MARKER_FILE"; return 0; }
HOOKEOF
        export BRIK_PROJECT_DIR="$HOOK_DIR"
      }
      cleanup_failure_hook() { rm -rf "$HOOK_DIR" "$MARKER_FILE"; }
      Before 'setup_failure_hook'
      After 'cleanup_failure_hook'

      It "executes with stage name, context, log, and exit code"
        verify_failure_args() {
          hook.on_failure "build" "/tmp/ctx" "/tmp/log" "10" 2>/dev/null
          grep -q "build /tmp/ctx /tmp/log 10" "$MARKER_FILE"
        }
        When call verify_failure_args
        The status should be success
      End
    End
  End

  Describe "hook.on_cleanup"
    It "returns 0 when no hook exists"
      export BRIK_PROJECT_DIR="/nonexistent"
      export BRIK_HOME="/nonexistent"
      When call hook.on_cleanup "build" "/tmp/ctx" "/tmp/log"
      The status should be success
    End

    Describe "with a cleanup hook script"
      setup_cleanup_hook() {
        HOOK_DIR="$(mktemp -d)"
        MARKER_FILE="$(mktemp)"
        mkdir -p "${HOOK_DIR}/.brik/hooks"
        cat > "${HOOK_DIR}/.brik/hooks/on_cleanup.sh" << HOOKEOF
on_cleanup() { printf '%s\n' "\$*" > "$MARKER_FILE"; return 0; }
HOOKEOF
        export BRIK_PROJECT_DIR="$HOOK_DIR"
      }
      cleanup_cleanup_hook() { rm -rf "$HOOK_DIR" "$MARKER_FILE"; }
      Before 'setup_cleanup_hook'
      After 'cleanup_cleanup_hook'

      It "executes with correct arguments"
        verify_cleanup_args() {
          hook.on_cleanup "test" "/tmp/ctx" "/tmp/log" 2>/dev/null
          grep -q "test /tmp/ctx /tmp/log" "$MARKER_FILE"
        }
        When call verify_cleanup_args
        The status should be success
      End
    End

    Describe "with a failing cleanup hook"
      setup_fail_cleanup() {
        HOOK_DIR="$(mktemp -d)"
        mkdir -p "${HOOK_DIR}/.brik/hooks"
        cat > "${HOOK_DIR}/.brik/hooks/on_cleanup.sh" << 'HOOKEOF'
on_cleanup() { return 4; }
HOOKEOF
        export BRIK_PROJECT_DIR="$HOOK_DIR"
      }
      cleanup_fail_cleanup() { rm -rf "$HOOK_DIR"; }
      Before 'setup_fail_cleanup'
      After 'cleanup_fail_cleanup'

      It "propagates the hook return code"
        When call hook.on_cleanup "build" "/tmp/ctx" "/tmp/log"
        The status should equal 4
      End
    End
  End

  Describe "hook.post_stage"
    It "returns 0 when no hook exists"
      export BRIK_PROJECT_DIR="/nonexistent"
      export BRIK_HOME="/nonexistent"
      When call hook.post_stage "build" "/tmp/ctx" "/tmp/log" "0"
      The status should be success
    End

    Describe "with a post_stage hook script"
      setup_post_hook() {
        HOOK_DIR="$(mktemp -d)"
        MARKER_FILE="$(mktemp)"
        mkdir -p "${HOOK_DIR}/.brik/hooks"
        cat > "${HOOK_DIR}/.brik/hooks/post_stage.sh" << HOOKEOF
post_stage() { printf '%s\n' "\$*" > "$MARKER_FILE"; return 0; }
HOOKEOF
        export BRIK_PROJECT_DIR="$HOOK_DIR"
      }
      cleanup_post_hook() { rm -rf "$HOOK_DIR" "$MARKER_FILE"; }
      Before 'setup_post_hook'
      After 'cleanup_post_hook'

      It "executes with stage name, context, log, and exit code"
        verify_post_args() {
          hook.post_stage "build" "/tmp/ctx" "/tmp/log" "0" 2>/dev/null
          grep -q "build /tmp/ctx /tmp/log 0" "$MARKER_FILE"
        }
        When call verify_post_args
        The status should be success
      End
    End

    Describe "with brik.yml inline post hook"
      setup_config_post_hook() {
        HOOK_DIR="$(mktemp -d)"
        export BRIK_PROJECT_DIR="$HOOK_DIR"
        export BRIK_HOME="/nonexistent"
        export BRIK_HOOK_POST_BUILD="printf 'config_post_hook_called\n'"
      }
      cleanup_config_post_hook() {
        rm -rf "$HOOK_DIR"
        unset BRIK_HOOK_POST_BUILD 2>/dev/null || true
      }
      Before 'setup_config_post_hook'
      After 'cleanup_config_post_hook'

      It "executes the brik.yml inline post hook"
        When call hook.post_stage "build" "/tmp/ctx" "/tmp/log" "0"
        The status should be success
        The output should equal "config_post_hook_called"
      End
    End
  End

  Describe "_hook._resolve_config"
    Describe "with config hook set"
      setup_config_resolve() {
        export BRIK_HOOK_PRE_TEST="echo pre-test"
      }
      cleanup_config_resolve() {
        unset BRIK_HOOK_PRE_TEST 2>/dev/null || true
      }
      Before 'setup_config_resolve'
      After 'cleanup_config_resolve'

      It "returns inline command for pre hook"
        When call _hook._resolve_config "PRE" "test"
        The status should be success
        The output should equal "echo pre-test"
      End
    End

    It "returns 1 when no config hook set"
      resolve_missing() {
        unset BRIK_HOOK_PRE_NONEXISTENT 2>/dev/null || true
        _hook._resolve_config "PRE" "nonexistent"
      }
      When call resolve_missing
      The status should equal 1
    End
  End
End
