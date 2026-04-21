Describe "stages.deploy"
  Include "$BRIK_HOME/lib/pipeline/stage.sh"
  Include "$BRIK_HOME/lib/pipeline/loader.sh"
  Include "$BRIK_HOME/lib/pipeline/report.sh"
  Include "$BRIK_HOME/lib/transverse/config.sh"
  Include "$BRIK_HOME/lib/transverse/conditions.sh"
  Include "$BRIK_HOME/lib/transverse/env.sh"
  Include "$BRIK_HOME/lib/stages/deploy.sh"

  setup_env() {
    export BRIK_CONFIG_FILE
    BRIK_CONFIG_FILE="$(mktemp)"
    printf 'version: 1\nproject:\n  name: test\n  stack: node\n' > "$BRIK_CONFIG_FILE"
    export BRIK_WORKSPACE
    BRIK_WORKSPACE="$(mktemp -d)"
    export BRIK_LOG_DIR
    BRIK_LOG_DIR="$(mktemp -d)"
    export BRIK_PROJECT_DIR="$BRIK_WORKSPACE"
    export BRIK_PLATFORM="gitlab"
    export BRIK_RUN_ID="deploy-spec-fixture"
    config.read "$BRIK_CONFIG_FILE" >/dev/null 2>&1 || true
    report.init >/dev/null 2>&1 || true
  }
  cleanup_env() {
    rm -f "$BRIK_CONFIG_FILE"
    rm -rf "$BRIK_WORKSPACE" "$BRIK_LOG_DIR"
    unset BRIK_DEPLOY_ENVIRONMENTS BRIK_DEPLOY_STAGING_TARGET \
          BRIK_DEPLOY_STAGING_NAMESPACE BRIK_DEPLOY_STAGING_WHEN \
          BRIK_RUN_ID 2>/dev/null || true
  }
  Before 'setup_env'
  After 'cleanup_env'

  read_deploy_status() {
    jq -r '.stages[] | select(.name == "deploy") | .tech.status // empty' \
      "$BRIK_LOG_DIR/pipeline-report.json" 2>/dev/null
  }

  It "is callable as a function"
    callable_check() { declare -f stages.deploy >/dev/null; }
    When call callable_check
    The status should be success
  End

  It "records status skipped in the pipeline report when no environments"
    run_deploy_skip() {
      brik.use() { :; }
      local ctx
      ctx="$(context.create "deploy")" 2>/dev/null || ctx="$(mktemp)"
      stages.deploy "$ctx" >/dev/null 2>&1 || return $?
      read_deploy_status
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
      target: k8s
      namespace: staging-ns
YAML
      config.read "$BRIK_CONFIG_FILE" >/dev/null 2>&1 || true
    }
    Before 'setup_deploy'

    It "returns 0 when deploy.run succeeds"
      run_deploy_success() {
        brik.use() { :; }
        deploy.k8s.run() { return 0; }

        local ctx
        ctx="$(context.create "deploy")" 2>/dev/null || ctx="$(mktemp)"
        stages.deploy "$ctx" >/dev/null 2>&1
      }
      When call run_deploy_success
      The status should be success
    End

    It "returns non-zero when deploy.run fails"
      run_deploy_fail() {
        brik.use() { :; }
        deploy.k8s.run() { return 1; }

        local ctx
        ctx="$(context.create "deploy")" 2>/dev/null || ctx="$(mktemp)"
        stages.deploy "$ctx" >/dev/null 2>&1
      }
      When call run_deploy_fail
      The status should equal 1
    End

    It "passes target and namespace to deploy.run"
      run_deploy_args() {
        brik.use() { :; }
        deploy.k8s.run() { printf '%s ' "$@"; printf '\n'; return 0; }

        local ctx
        ctx="$(context.create "deploy")" 2>/dev/null || ctx="$(mktemp)"
        stages.deploy "$ctx" 2>/dev/null
      }
      When call run_deploy_args
      The output should include "--target k8s"
      The output should include "--env staging"
      The output should include "--namespace staging-ns"
    End

    It "logs environment name"
      run_deploy_log() {
        brik.use() { :; }
        deploy.k8s.run() { return 0; }
        local ctx
        ctx="$(context.create "deploy")" 2>/dev/null || ctx="$(mktemp)"
        stages.deploy "$ctx"
      }
      When call run_deploy_log
      The error should include "deploying to staging"
    End
  End

  Describe "with deploy condition (when)"
    setup_deploy_cond() {
      cat > "$BRIK_CONFIG_FILE" <<'YAML'
version: 1
project:
  name: test
  stack: node
deploy:
  environments:
    staging:
      target: k8s
      when: "branch == 'main'"
YAML
      config.read "$BRIK_CONFIG_FILE" >/dev/null 2>&1 || true
    }
    Before 'setup_deploy_cond'

    It "skips deployment when branch condition is not met"
      run_deploy_cond_skip() {
        export BRIK_BRANCH="develop"
        brik.use() { :; }
        deploy.k8s.run() { printf 'DEPLOYED\n'; return 0; }
        local ctx
        ctx="$(context.create "deploy")" 2>/dev/null || ctx="$(mktemp)"
        stages.deploy "$ctx" 2>/dev/null
      }
      When call run_deploy_cond_skip
      The output should not include "DEPLOYED"
    End

    It "deploys when branch condition is met"
      run_deploy_cond_match() {
        export BRIK_BRANCH="main"
        brik.use() { :; }
        deploy.k8s.run() { printf 'DEPLOYED\n'; return 0; }
        local ctx
        ctx="$(context.create "deploy")" 2>/dev/null || ctx="$(mktemp)"
        stages.deploy "$ctx" 2>/dev/null
      }
      When call run_deploy_cond_match
      The output should include "DEPLOYED"
    End

    It "skips deployment when tag glob does not match"
      run_deploy_tag_skip() {
        cat > "$BRIK_CONFIG_FILE" <<'YAML'
version: 1
project:
  name: test
  stack: node
deploy:
  environments:
    production:
      target: k8s
      when: "tag =~ 'v*'"
YAML
        config.read "$BRIK_CONFIG_FILE" >/dev/null 2>&1 || true
        export BRIK_TAG=""
        brik.use() { :; }
        deploy.k8s.run() { printf 'DEPLOYED\n'; return 0; }
        local ctx
        ctx="$(context.create "deploy")" 2>/dev/null || ctx="$(mktemp)"
        stages.deploy "$ctx" 2>/dev/null
      }
      When call run_deploy_tag_skip
      The output should not include "DEPLOYED"
    End
  End
End
