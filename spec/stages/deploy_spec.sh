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

  read_deploy_tech_json() {
    local key="$1"
    jq -c --arg k "$key" \
      '.stages[] | select(.name == "deploy") | .tech[$k] // empty' \
      "$BRIK_LOG_DIR/pipeline-report.json" 2>/dev/null
  }

  It "is callable as a function"
    callable_check() { declare -f stages.deploy >/dev/null; }
    When call callable_check
    The status should be success
  End

  It "records deploy.tech.environments as an array of configured env names"
    run_deploy_envs() {
      cat > "$BRIK_CONFIG_FILE" <<'YAML'
version: 1
project:
  name: test
  stack: node
deploy:
  environments:
    staging:
      target: k8s
      namespace: stg
      when: branch == 'main'
    prod:
      target: k8s
      namespace: prd
      when: tag =~ 'v*'
YAML
      config.read "$BRIK_CONFIG_FILE" >/dev/null 2>&1 || true
      brik.use() { :; }
      conditions.eval() { return 1; }  # block actual deploys
      local ctx
      ctx="$(context.create "deploy")" 2>/dev/null || ctx="$(mktemp)"
      stages.deploy "$ctx" >/dev/null 2>&1
      read_deploy_tech_json "environments"
    }
    When call run_deploy_envs
    The output should equal '["staging","prod"]'
  End

  It "skips silently when no environments are configured"
    run_deploy_skip() {
      brik.use() { :; }
      local ctx
      ctx="$(context.create "deploy")" 2>/dev/null || ctx="$(mktemp)"
      stages.deploy "$ctx" >/dev/null 2>&1 || return $?
      read_deploy_status
    }
    When call run_deploy_skip
    # Silent skip: no fragment recorded, .tech.status is absent.
    The output should equal ""
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

    Describe "passes --source to deploy.run when source is set"
      setup_source_deploy() {
        cat > "$BRIK_CONFIG_FILE" <<'YAML'
version: 1
project:
  name: test
  stack: node
deploy:
  environments:
    staging:
      target: ssh
      host: staging.example.com
      remote_path: /srv/app
      source: ./build/output
YAML
        config.read "$BRIK_CONFIG_FILE" >/dev/null 2>&1 || true
      }
      Before 'setup_source_deploy'

      It "passes --source to deploy.run when source is set"
        run_deploy_source() {
          brik.use() { :; }
          deploy.ssh.run() { printf '%s ' "$@"; printf '\n'; return 0; }

          local ctx
          ctx="$(context.create "deploy")" 2>/dev/null || ctx="$(mktemp)"
          stages.deploy "$ctx" 2>/dev/null
        }
        When call run_deploy_source
        The output should include "--source ./build/output"
        The output should include "--target ssh"
      End
    End

    Describe "with git_token_var"
      setup_git_token_var_deploy() {
        cat > "$BRIK_CONFIG_FILE" <<'YAML'
version: 1
project:
  name: test
  stack: node
deploy:
  environments:
    staging:
      target: gitops
      repo: https://gitlab.example.com/org/infra.git
      path: services/api
      controller: argocd
      app_name: api-staging
      git_token_var: GITOPS_TOKEN
YAML
        config.read "$BRIK_CONFIG_FILE" >/dev/null 2>&1 || true
      }
      Before 'setup_git_token_var_deploy'

      It "forwards --git-token-var to the gitops adapter"
        run_deploy_git_token_var() {
          brik.use() { :; }
          deploy.gitops.run() { printf '%s ' "$@"; printf '\n'; return 0; }

          local ctx
          ctx="$(context.create "deploy")" 2>/dev/null || ctx="$(mktemp)"
          stages.deploy "$ctx" 2>/dev/null
        }
        When call run_deploy_git_token_var
        The output should include "--git-token-var GITOPS_TOKEN"
        The output should include "--target gitops"
      End
    End

    Describe "with auth_token_var"
      setup_auth_token_var_deploy() {
        cat > "$BRIK_CONFIG_FILE" <<'YAML'
version: 1
project:
  name: test
  stack: node
deploy:
  environments:
    production:
      target: gitops
      repo: https://gitlab.example.com/org/infra.git
      path: services/api
      controller: argocd
      app_name: api-prod
      auth_token_var: ARGOCD_TOKEN
YAML
        config.read "$BRIK_CONFIG_FILE" >/dev/null 2>&1 || true
      }
      Before 'setup_auth_token_var_deploy'

      It "forwards --auth-token-var to the gitops adapter"
        run_deploy_auth_token_var() {
          brik.use() { :; }
          deploy.gitops.run() { printf '%s ' "$@"; printf '\n'; return 0; }

          local ctx
          ctx="$(context.create "deploy")" 2>/dev/null || ctx="$(mktemp)"
          stages.deploy "$ctx" 2>/dev/null
        }
        When call run_deploy_auth_token_var
        The output should include "--auth-token-var ARGOCD_TOKEN"
        The output should include "--target gitops"
      End
    End
  End

  Describe "with deploy.environments[].strategy"
    Include "$BRIK_HOME/lib/rollout/strategy.sh"

    setup_strategy() {
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
      strategy: rolling
YAML
      config.read "$BRIK_CONFIG_FILE" >/dev/null 2>&1 || true
    }
    Before 'setup_strategy'

    It "k8s + rolling -> rollout.strategy.run invoked with correct args"
      run_k8s_rolling() {
        local strategy_type_captured="" deploy_fn_captured=""
        brik.use() { :; }
        deploy.k8s.run() { return 0; }
        rollout.strategy.run() {
          while [[ $# -gt 0 ]]; do
            case "$1" in
              --type)      strategy_type_captured="$2"; shift 2 ;;
              --deploy-fn) deploy_fn_captured="$2";     shift 2 ;;
              *)           shift ;;
            esac
          done
          printf 'strategy_type=%s deploy_fn=%s\n' "$strategy_type_captured" "$deploy_fn_captured"
          return 0
        }
        local ctx
        ctx="$(context.create "deploy")" 2>/dev/null || ctx="$(mktemp)"
        stages.deploy "$ctx" 2>/dev/null
      }
      When call run_k8s_rolling
      The output should include "strategy_type=rolling"
      The output should include "deploy_fn=_brik.deploy._strategy_wrapper"
    End

    It "helm + blue-green -> rollout.strategy.run invoked with correct args"
      run_helm_blue_green() {
        cat > "$BRIK_CONFIG_FILE" <<'YAML'
version: 1
project:
  name: test
  stack: node
deploy:
  environments:
    staging:
      target: helm
      namespace: staging-ns
      strategy: blue-green
YAML
        config.read "$BRIK_CONFIG_FILE" >/dev/null 2>&1 || true
        local strategy_type_captured="" deploy_fn_captured=""
        brik.use() { :; }
        deploy.helm.run() { return 0; }
        rollout.strategy.run() {
          while [[ $# -gt 0 ]]; do
            case "$1" in
              --type)      strategy_type_captured="$2"; shift 2 ;;
              --deploy-fn) deploy_fn_captured="$2";     shift 2 ;;
              *)           shift ;;
            esac
          done
          printf 'strategy_type=%s deploy_fn=%s\n' "$strategy_type_captured" "$deploy_fn_captured"
          return 0
        }
        local ctx
        ctx="$(context.create "deploy")" 2>/dev/null || ctx="$(mktemp)"
        stages.deploy "$ctx" 2>/dev/null
      }
      When call run_helm_blue_green
      The output should include "strategy_type=blue-green"
      The output should include "deploy_fn=_brik.deploy._strategy_wrapper"
    End

    It "ssh + rolling -> direct call (strategy logged at debug, rollout not invoked)"
      run_ssh_rolling() {
        cat > "$BRIK_CONFIG_FILE" <<'YAML'
version: 1
project:
  name: test
  stack: node
deploy:
  environments:
    staging:
      target: ssh
      host: myhost
      strategy: rolling
YAML
        config.read "$BRIK_CONFIG_FILE" >/dev/null 2>&1 || true
        brik.use() { :; }
        deploy.ssh.run() { printf 'DIRECT_CALL\n'; return 0; }
        rollout.strategy.run() { printf 'STRATEGY_CALLED\n'; return 0; }
        local ctx
        ctx="$(context.create "deploy")" 2>/dev/null || ctx="$(mktemp)"
        stages.deploy "$ctx" 2>/dev/null
      }
      When call run_ssh_rolling
      The output should include "DIRECT_CALL"
      The output should not include "STRATEGY_CALLED"
    End

    It "compose + canary -> direct call (strategy ignored, rollout not invoked)"
      run_compose_canary() {
        cat > "$BRIK_CONFIG_FILE" <<'YAML'
version: 1
project:
  name: test
  stack: node
deploy:
  environments:
    staging:
      target: compose
      file: docker-compose.yml
      strategy: canary
YAML
        config.read "$BRIK_CONFIG_FILE" >/dev/null 2>&1 || true
        brik.use() { :; }
        deploy.compose.run() { printf 'DIRECT_CALL\n'; return 0; }
        rollout.strategy.run() { printf 'STRATEGY_CALLED\n'; return 0; }
        local ctx
        ctx="$(context.create "deploy")" 2>/dev/null || ctx="$(mktemp)"
        stages.deploy "$ctx" 2>/dev/null
      }
      When call run_compose_canary
      The output should include "DIRECT_CALL"
      The output should not include "STRATEGY_CALLED"
    End

    It "k8s without strategy -> direct call preserved (regression guard)"
      run_k8s_no_strategy() {
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
        brik.use() { :; }
        deploy.k8s.run() { printf 'DIRECT_CALL\n'; return 0; }
        rollout.strategy.run() { printf 'STRATEGY_CALLED\n'; return 0; }
        local ctx
        ctx="$(context.create "deploy")" 2>/dev/null || ctx="$(mktemp)"
        stages.deploy "$ctx" 2>/dev/null
      }
      When call run_k8s_no_strategy
      The output should include "DIRECT_CALL"
      The output should not include "STRATEGY_CALLED"
    End

    It "k8s + rolling -> deploy_args correctly forwarded through wrapper"
      run_k8s_rolling_args_forwarded() {
        brik.use() { :; }
        deploy.k8s.run() {
          printf '%s\n' "$*"
          return 0
        }
        # Spoof rollout.strategy.run: invoke wrapper directly to test forwarding
        rollout.strategy.run() {
          local deploy_fn_arg=""
          while [[ $# -gt 0 ]]; do
            case "$1" in
              --deploy-fn) deploy_fn_arg="$2"; shift 2 ;;
              *)           shift ;;
            esac
          done
          # Call the wrapper with no extra args (simulates _exec_rolling with empty _cargs)
          "$deploy_fn_arg"
          return 0
        }
        local ctx
        ctx="$(context.create "deploy")" 2>/dev/null || ctx="$(mktemp)"
        stages.deploy "$ctx" 2>/dev/null
      }
      When call run_k8s_rolling_args_forwarded
      The output should include "--target k8s"
      The output should include "--env staging"
      The output should include "--namespace staging-ns"
    End

    It "k8s + rolling -> deploy_args propagate through the REAL rollout.strategy.run (regression guard)"
      run_k8s_rolling_real_strategy() {
        # Source the real rollout.strategy.run instead of stubbing it.
        # Guards against future re-introduction of the dynamic-scoping
        # shadowing bug where a `local deploy_args` inside
        # rollout.strategy.run would mask the outer one in stages.deploy
        # and silently drop the actual deploy arguments.
        unset _BRIK_ROLLOUT_STRATEGY_LOADED
        brik.use() {
          case "$1" in
            rollout.strategy) . "$BRIK_HOME/lib/rollout/strategy.sh" ;;
            *) : ;;
          esac
        }
        deploy.k8s.run() {
          printf '%s\n' "$*"
          return 0
        }
        local ctx
        ctx="$(context.create "deploy")" 2>/dev/null || ctx="$(mktemp)"
        stages.deploy "$ctx" 2>/dev/null
      }
      When call run_k8s_rolling_real_strategy
      The output should include "--target k8s"
      The output should include "--env staging"
      The output should include "--namespace staging-ns"
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
