Describe "stages.deploy"
  Include "$BRIK_HOME/runtime/bash/lib/runtime/stage.sh"
  Include "$BRIK_HOME/runtime/bash/lib/core/_loader.sh"
  Include "$BRIK_HOME/runtime/bash/lib/core/config.sh"
  Include "$BRIK_HOME/runtime/bash/lib/stages/deploy.sh"

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
    unset BRIK_DEPLOY_ENVIRONMENTS BRIK_DEPLOY_STAGING_TARGET \
          BRIK_DEPLOY_STAGING_NAMESPACE BRIK_DEPLOY_STAGING_WHEN 2>/dev/null || true
  }
  Before 'setup_env'
  After 'cleanup_env'

  It "is callable as a function"
    callable_check() { declare -f stages.deploy >/dev/null; }
    When call callable_check
    The status should be success
  End

  It "sets BRIK_DEPLOY_STATUS to skipped when no environments"
    run_deploy_skip() {
      brik.use() { :; }
      local ctx
      ctx="$(context.create "deploy")" 2>/dev/null || ctx="$(mktemp)"
      stages.deploy "$ctx" >/dev/null 2>&1
      grep "^BRIK_DEPLOY_STATUS=" "$ctx" | cut -d= -f2
    }
    When call run_deploy_skip
    The output should equal "skipped"
  End

  Describe "with deploy environments"
    setup_deploy() {
      cat > "$BRIK_CONFIG_FILE" <<'YAML'
version: 1
project:
  name: test
  stack: node
deploy:
  environments:
    staging:
      target: kubernetes
      namespace: staging-ns
YAML
      config.read "$BRIK_CONFIG_FILE" >/dev/null 2>&1 || true
    }
    Before 'setup_deploy'

    It "returns 0 when deploy.run succeeds"
      run_deploy_success() {
        brik.use() { :; }
        deploy.run() { return 0; }
        deploy.eval_condition() { return 0; }
        local ctx
        ctx="$(context.create "deploy")" 2>/dev/null || ctx="$(mktemp)"
        stages.deploy "$ctx" >/dev/null 2>&1
      }
      When call run_deploy_success
      The status should be success
    End

    It "sets BRIK_DEPLOY_STATUS to success"
      run_deploy_ctx() {
        brik.use() { :; }
        deploy.run() { return 0; }
        deploy.eval_condition() { return 0; }
        local ctx
        ctx="$(context.create "deploy")" 2>/dev/null || ctx="$(mktemp)"
        stages.deploy "$ctx" >/dev/null 2>&1
        grep "^BRIK_DEPLOY_STATUS=" "$ctx" | cut -d= -f2
      }
      When call run_deploy_ctx
      The output should equal "success"
    End

    It "sets BRIK_DEPLOY_STATUS to failed when deploy.run fails"
      run_deploy_fail() {
        brik.use() { :; }
        deploy.run() { return 1; }
        deploy.eval_condition() { return 0; }
        local ctx
        ctx="$(context.create "deploy")" 2>/dev/null || ctx="$(mktemp)"
        stages.deploy "$ctx" >/dev/null 2>&1 || true
        grep "^BRIK_DEPLOY_STATUS=" "$ctx" | cut -d= -f2
      }
      When call run_deploy_fail
      The output should equal "failed"
    End

    It "passes target and namespace to deploy.run"
      run_deploy_args() {
        brik.use() { :; }
        deploy.run() { printf '%s ' "$@"; printf '\n'; return 0; }
        deploy.eval_condition() { return 0; }
        local ctx
        ctx="$(context.create "deploy")" 2>/dev/null || ctx="$(mktemp)"
        stages.deploy "$ctx" 2>/dev/null
      }
      When call run_deploy_args
      The output should include "--target kubernetes"
      The output should include "--env staging"
      The output should include "--namespace staging-ns"
    End

    It "logs environment name"
      run_deploy_log() {
        brik.use() { :; }
        deploy.run() { return 0; }
        deploy.eval_condition() { return 0; }
        local ctx
        ctx="$(context.create "deploy")" 2>/dev/null || ctx="$(mktemp)"
        stages.deploy "$ctx"
      }
      When call run_deploy_log
      The error should include "deploying to staging"
    End
  End
End
