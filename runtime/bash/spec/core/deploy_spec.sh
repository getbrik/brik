Describe "deploy.sh"
  Include "$BRIK_RUNTIME_LIB/logging.sh"
  Include "$BRIK_RUNTIME_LIB/tools.sh"
  Include "$BRIK_CORE_LIB/_loader.sh"
  Include "$BRIK_CORE_LIB/deploy.sh"

  Describe "deploy.run"
    It "returns 2 when no target specified"
      When call deploy.run --env staging
      The status should equal 2
      The stderr should include "deploy target is required"
    End

    Describe "with unsupported target"
      It "returns 7 for unsupported target"
        When call deploy.run --target ftp
        The status should equal 7
        The stderr should include "unsupported deploy target"
      End
    End

    Describe "with mock k8s module"
      setup_mock() {
        MOCK_K8S_LOG="$(mktemp)"
        eval "deploy.k8s.run() { printf '%s\n' \"\$*\" > \"$MOCK_K8S_LOG\"; return 0; }"
        eval "_BRIK_MODULE_DEPLOY_K8S_LOADED=1"
        export _BRIK_MODULE_DEPLOY_K8S_LOADED
      }
      cleanup_mock() {
        unset -f deploy.k8s.run 2>/dev/null
        unset _BRIK_MODULE_DEPLOY_K8S_LOADED
        rm -f "$MOCK_K8S_LOG"
      }
      Before 'setup_mock'
      After 'cleanup_mock'

      It "delegates to k8s module"
        When call deploy.run --target k8s
        The status should be success
        The stderr should include "deploying with target: k8s"
      End

      It "passes --dry-run to sub-module"
        invoke_dryrun() {
          deploy.run --target k8s --dry-run 2>/dev/null || return 1
          grep -q "\-\-dry-run" "$MOCK_K8S_LOG"
        }
        When call invoke_dryrun
        The status should be success
      End

      It "passes unknown args through to sub-module"
        invoke_passthrough() {
          deploy.run --target k8s --manifest /tmp/test.yaml --namespace prod 2>/dev/null || return 1
          grep -q "\-\-manifest /tmp/test.yaml" "$MOCK_K8S_LOG" && grep -q "\-\-namespace prod" "$MOCK_K8S_LOG"
        }
        When call invoke_passthrough
        The status should be success
      End
    End

    Describe "with --env loading"
      setup_env() {
        MOCK_K8S_LOG="$(mktemp)"
        eval "deploy.k8s.run() { printf '%s\n' \"\$*\" > \"$MOCK_K8S_LOG\"; return 0; }"
        eval "_BRIK_MODULE_DEPLOY_K8S_LOADED=1"
        export _BRIK_MODULE_DEPLOY_K8S_LOADED
        # Mock env.load to verify it is called
        ENV_LOAD_LOG="$(mktemp)"
        eval "env.load() { printf '%s\n' \"\$1\" > \"$ENV_LOAD_LOG\"; return 0; }"
      }
      cleanup_env() {
        unset -f deploy.k8s.run env.load 2>/dev/null
        unset _BRIK_MODULE_DEPLOY_K8S_LOADED
        rm -f "$MOCK_K8S_LOG" "$ENV_LOAD_LOG"
      }
      Before 'setup_env'
      After 'cleanup_env'

      It "calls env.load with the specified environment"
        invoke_env_check() {
          deploy.run --target k8s --env production 2>/dev/null || return 1
          grep -qx "production" "$ENV_LOAD_LOG"
        }
        When call invoke_env_check
        The status should be success
      End
    End

    Describe "deploy function not found"
      setup_no_fn() {
        # Module loaded but no deploy function
        eval "_BRIK_MODULE_DEPLOY_NOOP_LOADED=1"
        export _BRIK_MODULE_DEPLOY_NOOP_LOADED
      }
      cleanup_no_fn() {
        unset _BRIK_MODULE_DEPLOY_NOOP_LOADED
      }
      Before 'setup_no_fn'
      After 'cleanup_no_fn'

      It "returns 7 when deploy function not declared"
        When call deploy.run --target noop
        The status should equal 7
        The stderr should include "deploy function not found"
      End
    End
  End
End
