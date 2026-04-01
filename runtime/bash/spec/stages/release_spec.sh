Describe "stages.release"
  Include "$BRIK_HOME/runtime/bash/lib/runtime/stage.sh"
  Include "$BRIK_HOME/runtime/bash/lib/core/_loader.sh"
  Include "$BRIK_HOME/runtime/bash/lib/core/config.sh"
  Include "$BRIK_HOME/runtime/bash/lib/stages/release.sh"

  setup_env() {
    export BRIK_CONFIG_FILE
    BRIK_CONFIG_FILE="$(mktemp)"
    printf 'version: 1\nproject:\n  name: test\n  stack: node\n' > "$BRIK_CONFIG_FILE"
    export BRIK_LOG_DIR
    BRIK_LOG_DIR="$(mktemp -d)"
    export BRIK_WORKSPACE
    BRIK_WORKSPACE="$(mktemp -d)"
    export BRIK_PROJECT_DIR="$BRIK_WORKSPACE"
    export BRIK_PLATFORM="gitlab"
    config.read "$BRIK_CONFIG_FILE" >/dev/null 2>&1 || true
  }
  cleanup_env() {
    rm -f "$BRIK_CONFIG_FILE"
    rm -rf "$BRIK_LOG_DIR" "$BRIK_WORKSPACE"
  }
  Before 'setup_env'
  After 'cleanup_env'

  It "is callable as a function"
    callable_check() { declare -f stages.release >/dev/null; }
    When call callable_check
    The status should be success
  End

  It "returns 0 on success"
    run_release() {
      local ctx
      ctx="$(context.create "release")" 2>/dev/null || ctx="$(mktemp)"
      stages.release "$ctx" >/dev/null 2>&1
    }
    When call run_release
    The status should be success
  End

  It "writes BRIK_VERSION to context"
    run_release_check() {
      local ctx
      ctx="$(context.create "release")" 2>/dev/null || ctx="$(mktemp)"
      stages.release "$ctx" >/dev/null 2>&1
      local version
      version="$(grep "^BRIK_VERSION=" "$ctx" | cut -d= -f2)"
      if [[ -n "$version" ]]; then echo "has_version"; else echo "no_version"; fi
    }
    When call run_release_check
    The output should equal "has_version"
  End

  It "exports BRIK_RELEASE_STRATEGY from config"
    run_release_strategy() {
      local ctx
      ctx="$(context.create "release")" 2>/dev/null || ctx="$(mktemp)"
      stages.release "$ctx" >/dev/null 2>&1
      printf '%s' "${BRIK_RELEASE_STRATEGY:-}"
    }
    When call run_release_strategy
    The output should equal "semver"
  End

  It "exports BRIK_RELEASE_TAG_PREFIX from config"
    run_release_prefix() {
      local ctx
      ctx="$(context.create "release")" 2>/dev/null || ctx="$(mktemp)"
      stages.release "$ctx" >/dev/null 2>&1
      printf '%s' "${BRIK_RELEASE_TAG_PREFIX:-}"
    }
    When call run_release_prefix
    The output should equal "v"
  End

  Describe "with custom release config"
    setup_release() {
      cat > "$BRIK_CONFIG_FILE" <<'YAML'
version: 1
project:
  name: test
  stack: node
release:
  strategy: calver
  tag_prefix: release-
YAML
      config.read "$BRIK_CONFIG_FILE" >/dev/null 2>&1 || true
    }
    Before 'setup_release'

    It "uses custom strategy and prefix"
      run_release_custom() {
        local ctx
        ctx="$(context.create "release")" 2>/dev/null || ctx="$(mktemp)"
        stages.release "$ctx"
      }
      When call run_release_custom
      The error should include "release strategy: calver"
      The error should include "tag prefix: release-"
    End
  End
End
