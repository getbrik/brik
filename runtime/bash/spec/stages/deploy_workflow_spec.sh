Describe "stages.deploy - workflow and new target fields"
  Include "$BRIK_HOME/runtime/bash/lib/runtime/stage.sh"
  Include "$BRIK_HOME/runtime/bash/lib/core/_loader.sh"
  Include "$BRIK_HOME/runtime/bash/lib/core/config.sh"
  Include "$BRIK_HOME/runtime/bash/lib/core/condition.sh"
  Include "$BRIK_HOME/runtime/bash/lib/stages/deploy.sh"

  setup_env() {
    export BRIK_CONFIG_FILE
    BRIK_CONFIG_FILE="$(mktemp)"
    printf 'version: 1\nproject:\n  name: test\n  stack: node\n' > "$BRIK_CONFIG_FILE"
    export BRIK_WORKSPACE
    BRIK_WORKSPACE="$(mktemp -d)"
    export BRIK_PROJECT_DIR="$BRIK_WORKSPACE"
    export BRIK_PLATFORM="gitlab"
    config.read "$BRIK_CONFIG_FILE" >/dev/null 2>&1 || true
  }
  cleanup_env() {
    rm -f "$BRIK_CONFIG_FILE"
    rm -rf "$BRIK_WORKSPACE"
    unset BRIK_DEPLOY_ENVIRONMENTS BRIK_DEPLOY_STAGING_TARGET \
          BRIK_DEPLOY_STAGING_NAMESPACE BRIK_DEPLOY_STAGING_WHEN \
          BRIK_DEPLOY_STAGING_CHART BRIK_DEPLOY_STAGING_RELEASE_NAME \
          BRIK_DEPLOY_STAGING_VALUES BRIK_DEPLOY_STAGING_HOST \
          BRIK_DEPLOY_STAGING_COMPOSE_FILE BRIK_DEPLOY_STAGING_REMOTE_PATH \
          BRIK_DEPLOY_STAGING_RESTART_CMD BRIK_DEPLOY_WORKFLOW 2>/dev/null || true
  }
  Before 'setup_env'
  After 'cleanup_env'

  # =========================================================================
  # New field passthrough: chart, release_name, values
  # =========================================================================
  Describe "passes new helm fields to deploy.run"
    setup_helm() {
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
      chart: ./charts/myapp
      release_name: myapp-staging
      values: charts/values-staging.yaml
YAML
      config.read "$BRIK_CONFIG_FILE" >/dev/null 2>&1 || true
    }
    Before 'setup_helm'

    It "passes --chart to deploy.run"
      run_deploy_chart() {
        brik.use() { :; }
        deploy.run() { printf '%s ' "$@"; printf '\n'; return 0; }
        local ctx
        ctx="$(context.create "deploy")" 2>/dev/null || ctx="$(mktemp)"
        stages.deploy "$ctx" 2>/dev/null
      }
      When call run_deploy_chart
      The output should include "--chart ./charts/myapp"
    End

    It "passes --release-name to deploy.run"
      run_deploy_release() {
        brik.use() { :; }
        deploy.run() { printf '%s ' "$@"; printf '\n'; return 0; }
        local ctx
        ctx="$(context.create "deploy")" 2>/dev/null || ctx="$(mktemp)"
        stages.deploy "$ctx" 2>/dev/null
      }
      When call run_deploy_release
      The output should include "--release-name myapp-staging"
    End

    It "passes --values to deploy.run"
      run_deploy_values() {
        brik.use() { :; }
        deploy.run() { printf '%s ' "$@"; printf '\n'; return 0; }
        local ctx
        ctx="$(context.create "deploy")" 2>/dev/null || ctx="$(mktemp)"
        stages.deploy "$ctx" 2>/dev/null
      }
      When call run_deploy_values
      The output should include "--values charts/values-staging.yaml"
    End
  End

  # =========================================================================
  # New field passthrough: host, remote_path, restart_cmd (ssh)
  # =========================================================================
  Describe "passes new ssh fields to deploy.run"
    setup_ssh() {
      cat > "$BRIK_CONFIG_FILE" <<'YAML'
version: 1
project:
  name: test
  stack: node
deploy:
  environments:
    production:
      target: ssh
      host: prod.example.com
      remote_path: /opt/app
      restart_cmd: systemctl restart myapp
YAML
      config.read "$BRIK_CONFIG_FILE" >/dev/null 2>&1 || true
    }
    Before 'setup_ssh'

    It "passes --host to deploy.run"
      run_deploy_host() {
        brik.use() { :; }
        deploy.run() { printf '%s ' "$@"; printf '\n'; return 0; }
        local ctx
        ctx="$(context.create "deploy")" 2>/dev/null || ctx="$(mktemp)"
        stages.deploy "$ctx" 2>/dev/null
      }
      When call run_deploy_host
      The output should include "--host prod.example.com"
    End

    It "passes --remote-path to deploy.run"
      run_deploy_remote_path() {
        brik.use() { :; }
        deploy.run() { printf '%s ' "$@"; printf '\n'; return 0; }
        local ctx
        ctx="$(context.create "deploy")" 2>/dev/null || ctx="$(mktemp)"
        stages.deploy "$ctx" 2>/dev/null
      }
      When call run_deploy_remote_path
      The output should include "--remote-path /opt/app"
    End

    It "passes --restart-cmd to deploy.run"
      run_deploy_restart() {
        brik.use() { :; }
        deploy.run() { printf '%s ' "$@"; printf '\n'; return 0; }
        local ctx
        ctx="$(context.create "deploy")" 2>/dev/null || ctx="$(mktemp)"
        stages.deploy "$ctx" 2>/dev/null
      }
      When call run_deploy_restart
      The output should include "--restart-cmd"
    End
  End

  # =========================================================================
  # New field passthrough: compose_file
  # =========================================================================
  Describe "passes compose_file to deploy.run"
    setup_compose() {
      cat > "$BRIK_CONFIG_FILE" <<'YAML'
version: 1
project:
  name: test
  stack: node
deploy:
  environments:
    staging:
      target: compose
      compose_file: docker-compose.prod.yml
YAML
      config.read "$BRIK_CONFIG_FILE" >/dev/null 2>&1 || true
    }
    Before 'setup_compose'

    It "passes --compose-file to deploy.run"
      run_deploy_compose() {
        brik.use() { :; }
        deploy.run() { printf '%s ' "$@"; printf '\n'; return 0; }
        local ctx
        ctx="$(context.create "deploy")" 2>/dev/null || ctx="$(mktemp)"
        stages.deploy "$ctx" 2>/dev/null
      }
      When call run_deploy_compose
      The output should include "--compose-file docker-compose.prod.yml"
    End
  End

  # =========================================================================
  # Backward compatibility: existing fields still work
  # =========================================================================
  Describe "backward compatibility: existing fields unchanged"
    setup_backward() {
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
      manifest: k8s/staging.yml
      repo: org/infra-repo
      path: services/myapp
      controller: argocd
      app_name: myapp-staging
YAML
      config.read "$BRIK_CONFIG_FILE" >/dev/null 2>&1 || true
    }
    Before 'setup_backward'

    It "still passes --target to deploy.run"
      run_deploy_target() {
        brik.use() { :; }
        deploy.run() { printf '%s ' "$@"; printf '\n'; return 0; }
        local ctx
        ctx="$(context.create "deploy")" 2>/dev/null || ctx="$(mktemp)"
        stages.deploy "$ctx" 2>/dev/null
      }
      When call run_deploy_target
      The output should include "--target kubernetes"
    End

    It "still passes --env to deploy.run"
      run_deploy_env() {
        brik.use() { :; }
        deploy.run() { printf '%s ' "$@"; printf '\n'; return 0; }
        local ctx
        ctx="$(context.create "deploy")" 2>/dev/null || ctx="$(mktemp)"
        stages.deploy "$ctx" 2>/dev/null
      }
      When call run_deploy_env
      The output should include "--env staging"
    End

    It "still passes --namespace to deploy.run"
      run_deploy_ns() {
        brik.use() { :; }
        deploy.run() { printf '%s ' "$@"; printf '\n'; return 0; }
        local ctx
        ctx="$(context.create "deploy")" 2>/dev/null || ctx="$(mktemp)"
        stages.deploy "$ctx" 2>/dev/null
      }
      When call run_deploy_ns
      The output should include "--namespace staging-ns"
    End

    It "still passes --manifest to deploy.run"
      run_deploy_manifest() {
        brik.use() { :; }
        deploy.run() { printf '%s ' "$@"; printf '\n'; return 0; }
        local ctx
        ctx="$(context.create "deploy")" 2>/dev/null || ctx="$(mktemp)"
        stages.deploy "$ctx" 2>/dev/null
      }
      When call run_deploy_manifest
      The output should include "--manifest k8s/staging.yml"
    End

    It "still passes --repo to deploy.run"
      run_deploy_repo() {
        brik.use() { :; }
        deploy.run() { printf '%s ' "$@"; printf '\n'; return 0; }
        local ctx
        ctx="$(context.create "deploy")" 2>/dev/null || ctx="$(mktemp)"
        stages.deploy "$ctx" 2>/dev/null
      }
      When call run_deploy_repo
      The output should include "--repo org/infra-repo"
    End

    It "still passes --path to deploy.run"
      run_deploy_path() {
        brik.use() { :; }
        deploy.run() { printf '%s ' "$@"; printf '\n'; return 0; }
        local ctx
        ctx="$(context.create "deploy")" 2>/dev/null || ctx="$(mktemp)"
        stages.deploy "$ctx" 2>/dev/null
      }
      When call run_deploy_path
      The output should include "--path services/myapp"
    End

    It "still passes --controller to deploy.run"
      run_deploy_controller() {
        brik.use() { :; }
        deploy.run() { printf '%s ' "$@"; printf '\n'; return 0; }
        local ctx
        ctx="$(context.create "deploy")" 2>/dev/null || ctx="$(mktemp)"
        stages.deploy "$ctx" 2>/dev/null
      }
      When call run_deploy_controller
      The output should include "--controller argocd"
    End

    It "still passes --app-name to deploy.run"
      run_deploy_appname() {
        brik.use() { :; }
        deploy.run() { printf '%s ' "$@"; printf '\n'; return 0; }
        local ctx
        ctx="$(context.create "deploy")" 2>/dev/null || ctx="$(mktemp)"
        stages.deploy "$ctx" 2>/dev/null
      }
      When call run_deploy_appname
      The output should include "--app-name myapp-staging"
    End
  End
End
