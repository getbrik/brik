Describe "publish.sh"
  Include "$BRIK_RUNTIME_LIB/logging.sh"
  Include "$BRIK_RUNTIME_LIB/tools.sh"
  Include "$BRIK_CORE_LIB/_loader.sh"
  Include "$BRIK_CORE_LIB/publish.sh"

  Describe "publish.run"
    It "returns 2 when no target specified"
      When call publish.run
      The status should equal 2
      The stderr should include "publish target is required"
    End

    Describe "with unsupported target"
      It "returns 7 for unsupported target"
        When call publish.run --target ftp
        The status should equal 7
        The stderr should include "unsupported publish target"
      End
    End

    Describe "with mock npm module"
      setup_mock() {
        MOCK_NPM_LOG="$(mktemp)"
        eval "publish.npm.run() { printf '%s\n' \"\$*\" > \"$MOCK_NPM_LOG\"; return 0; }"
        eval "_BRIK_MODULE_PUBLISH_NPM_LOADED=1"
        export _BRIK_MODULE_PUBLISH_NPM_LOADED
      }
      cleanup_mock() {
        unset -f publish.npm.run 2>/dev/null
        unset _BRIK_MODULE_PUBLISH_NPM_LOADED
        rm -f "$MOCK_NPM_LOG"
      }
      Before 'setup_mock'
      After 'cleanup_mock'

      It "delegates to npm module"
        When call publish.run --target npm
        The status should be success
        The stderr should include "publishing with target: npm"
      End

      It "passes --dry-run to sub-module"
        invoke_dryrun() {
          publish.run --target npm --dry-run 2>/dev/null || return 1
          grep -q "\-\-dry-run" "$MOCK_NPM_LOG"
        }
        When call invoke_dryrun
        The status should be success
      End

      It "passes unknown args through to sub-module"
        invoke_passthrough() {
          publish.run --target npm --registry https://npm.example.com 2>/dev/null || return 1
          grep -q "\-\-registry https://npm.example.com" "$MOCK_NPM_LOG"
        }
        When call invoke_passthrough
        The status should be success
      End
    End

    Describe "with mock docker module"
      setup_docker_mock() {
        MOCK_DOCKER_LOG="$(mktemp)"
        eval "publish.docker.run() { printf '%s\n' \"\$*\" > \"$MOCK_DOCKER_LOG\"; return 0; }"
        eval "_BRIK_MODULE_PUBLISH_DOCKER_LOADED=1"
        export _BRIK_MODULE_PUBLISH_DOCKER_LOADED
      }
      cleanup_docker_mock() {
        unset -f publish.docker.run 2>/dev/null
        unset _BRIK_MODULE_PUBLISH_DOCKER_LOADED
        rm -f "$MOCK_DOCKER_LOG"
      }
      Before 'setup_docker_mock'
      After 'cleanup_docker_mock'

      It "delegates to docker module"
        When call publish.run --target docker
        The status should be success
        The stderr should include "publishing with target: docker"
      End
    End

    Describe "publish function not found"
      setup_no_fn() {
        eval "_BRIK_MODULE_PUBLISH_NOOP_LOADED=1"
        export _BRIK_MODULE_PUBLISH_NOOP_LOADED
      }
      cleanup_no_fn() {
        unset _BRIK_MODULE_PUBLISH_NOOP_LOADED
      }
      Before 'setup_no_fn'
      After 'cleanup_no_fn'

      It "returns 7 when publish function not declared"
        When call publish.run --target noop
        The status should equal 7
        The stderr should include "publish function not found"
      End
    End
  End

  Describe "_publish._require_secret_var"
    It "returns 7 when variable name is empty"
      When call _publish._require_secret_var "" "test token"
      The status should equal 7
      The stderr should include "variable name is not configured"
    End

    It "returns 7 when referenced variable is not set"
      When call _publish._require_secret_var "NONEXISTENT_VAR_12345" "test token"
      The status should equal 7
      The stderr should include "is not set or empty"
    End

    Describe "with valid variable"
      setup_var() { export MY_SECRET_TOKEN="abc123"; }
      cleanup_var() { unset MY_SECRET_TOKEN; }
      Before 'setup_var'
      After 'cleanup_var'

      It "returns 0 when referenced variable is set"
        When call _publish._require_secret_var "MY_SECRET_TOKEN" "test token"
        The status should be success
      End
    End
  End
End
