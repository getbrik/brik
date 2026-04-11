Describe "config.sh - deploy workflow integration"
  Include "$BRIK_HOME/runtime/bash/lib/core/config.sh"

  # =========================================================================
  # config.stage_enabled - deploy with workflow
  # =========================================================================
  Describe "config.stage_enabled - deploy with workflow only (no explicit environments)"
    setup_workflow_only() {
      TEMP_CONFIG="$(mktemp)"
      cat > "$TEMP_CONFIG" <<'YAML'
version: 1
project:
  name: test
  stack: node
deploy:
  workflow: trunk-based
YAML
      export BRIK_CONFIG_FILE="$TEMP_CONFIG"
    }
    cleanup_workflow_only() { rm -f "$TEMP_CONFIG"; }
    Before 'setup_workflow_only'
    After 'cleanup_workflow_only'

    It "deploy stage is enabled when deploy.workflow is set (even with no explicit environments)"
      When call config.stage_enabled "deploy"
      The status should be success
    End
  End

  Describe "config.stage_enabled - deploy with both workflow and explicit environments"
    setup_both() {
      TEMP_CONFIG="$(mktemp)"
      cat > "$TEMP_CONFIG" <<'YAML'
version: 1
project:
  name: test
  stack: node
deploy:
  workflow: trunk-based
  environments:
    staging:
      namespace: my-ns
YAML
      export BRIK_CONFIG_FILE="$TEMP_CONFIG"
    }
    cleanup_both() { rm -f "$TEMP_CONFIG"; }
    Before 'setup_both'
    After 'cleanup_both'

    It "deploy stage is enabled when both workflow and environments are set"
      When call config.stage_enabled "deploy"
      The status should be success
    End
  End

  Describe "config.stage_enabled - deploy with explicit environments only (backward compat)"
    setup_explicit() {
      TEMP_CONFIG="$(mktemp)"
      cat > "$TEMP_CONFIG" <<'YAML'
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
      export BRIK_CONFIG_FILE="$TEMP_CONFIG"
    }
    cleanup_explicit() { rm -f "$TEMP_CONFIG"; }
    Before 'setup_explicit'
    After 'cleanup_explicit'

    It "deploy stage is still enabled with explicit environments (backward compat)"
      When call config.stage_enabled "deploy"
      The status should be success
    End
  End

  Describe "config.stage_enabled - deploy absent"
    setup_absent() {
      TEMP_CONFIG="$(mktemp)"
      printf 'version: 1\nproject:\n  name: test\n' > "$TEMP_CONFIG"
      export BRIK_CONFIG_FILE="$TEMP_CONFIG"
    }
    cleanup_absent() { rm -f "$TEMP_CONFIG"; }
    Before 'setup_absent'
    After 'cleanup_absent'

    It "deploy stage is disabled when deploy section absent"
      When call config.stage_enabled "deploy"
      The status should equal 1
    End
  End

  # =========================================================================
  # config.export_deploy_vars - explicit environments mode (backward compat)
  # =========================================================================
  Describe "config.export_deploy_vars - explicit environments (existing behavior preserved)"
    setup_explicit_env() {
      TEMP_CONFIG="$(mktemp)"
      cat > "$TEMP_CONFIG" <<'YAML'
version: 1
deploy:
  environments:
    staging:
      target: kubernetes
      namespace: staging-ns
      when: "branch == 'main'"
    production:
      target: kubernetes
      namespace: prod-ns
      manifest: k8s/production.yml
YAML
      export BRIK_CONFIG_FILE="$TEMP_CONFIG"
    }
    cleanup_explicit_env() {
      rm -f "$TEMP_CONFIG"
      unset BRIK_DEPLOY_ENVIRONMENTS BRIK_DEPLOY_STAGING_TARGET \
            BRIK_DEPLOY_STAGING_NAMESPACE BRIK_DEPLOY_PRODUCTION_TARGET \
            BRIK_DEPLOY_PRODUCTION_NAMESPACE BRIK_DEPLOY_PRODUCTION_MANIFEST \
            BRIK_DEPLOY_STAGING_WHEN BRIK_DEPLOY_WORKFLOW 2>/dev/null || true
    }
    Before 'setup_explicit_env'
    After 'cleanup_explicit_env'

    It "still exports BRIK_DEPLOY_ENVIRONMENTS with explicit environments"
      export_and_check() { config.export_deploy_vars; printf '%s' "${BRIK_DEPLOY_ENVIRONMENTS:-}"; }
      When call export_and_check
      The output should include "staging"
      The output should include "production"
    End

    It "still exports BRIK_DEPLOY_STAGING_TARGET with explicit environments"
      export_and_check() { config.export_deploy_vars; printf '%s' "${BRIK_DEPLOY_STAGING_TARGET:-}"; }
      When call export_and_check
      The output should equal "kubernetes"
    End

    It "still exports BRIK_DEPLOY_STAGING_NAMESPACE with explicit environments"
      export_and_check() { config.export_deploy_vars; printf '%s' "${BRIK_DEPLOY_STAGING_NAMESPACE:-}"; }
      When call export_and_check
      The output should equal "staging-ns"
    End

    It "still exports BRIK_DEPLOY_PRODUCTION_MANIFEST with explicit environments"
      export_and_check() { config.export_deploy_vars; printf '%s' "${BRIK_DEPLOY_PRODUCTION_MANIFEST:-}"; }
      When call export_and_check
      The output should equal "k8s/production.yml"
    End

    It "does not export BRIK_DEPLOY_WORKFLOW when deploy.workflow is absent"
      export_and_check() {
        unset BRIK_DEPLOY_WORKFLOW 2>/dev/null || true
        config.export_deploy_vars
        printf '%s' "${BRIK_DEPLOY_WORKFLOW:-absent}"
      }
      When call export_and_check
      The output should equal "absent"
    End
  End

  # =========================================================================
  # config.export_deploy_vars - exports BRIK_DEPLOY_WORKFLOW
  # =========================================================================
  Describe "config.export_deploy_vars - exports BRIK_DEPLOY_WORKFLOW when set"
    setup_workflow() {
      TEMP_CONFIG="$(mktemp)"
      cat > "$TEMP_CONFIG" <<'YAML'
version: 1
project:
  name: test
  stack: node
deploy:
  workflow: trunk-based
  environments:
    staging:
      namespace: my-ns
YAML
      export BRIK_CONFIG_FILE="$TEMP_CONFIG"
    }
    cleanup_workflow() {
      rm -f "$TEMP_CONFIG"
      unset BRIK_DEPLOY_WORKFLOW BRIK_DEPLOY_ENVIRONMENTS \
            BRIK_DEPLOY_STAGING_NAMESPACE 2>/dev/null || true
    }
    Before 'setup_workflow'
    After 'cleanup_workflow'

    It "exports BRIK_DEPLOY_WORKFLOW when deploy.workflow is set"
      export_and_check() { config.export_deploy_vars; printf '%s' "${BRIK_DEPLOY_WORKFLOW:-}"; }
      When call export_and_check
      The output should equal "trunk-based"
    End
  End

  # =========================================================================
  # config.export_deploy_vars - new target-specific fields
  # =========================================================================
  Describe "config.export_deploy_vars - new target-specific fields"
    setup_new_fields() {
      TEMP_CONFIG="$(mktemp)"
      cat > "$TEMP_CONFIG" <<'YAML'
version: 1
deploy:
  environments:
    staging:
      target: helm
      namespace: staging-ns
      chart: ./charts/myapp
      release_name: myapp-staging
      values: charts/values-staging.yaml
      strategy: rolling
    production:
      target: ssh
      host: prod.example.com
      remote_path: /opt/app
      restart_cmd: systemctl restart myapp
    compose_env:
      target: compose
      compose_file: docker-compose.prod.yml
YAML
      export BRIK_CONFIG_FILE="$TEMP_CONFIG"
    }
    cleanup_new_fields() {
      rm -f "$TEMP_CONFIG"
      unset BRIK_DEPLOY_ENVIRONMENTS \
            BRIK_DEPLOY_STAGING_CHART BRIK_DEPLOY_STAGING_RELEASE_NAME \
            BRIK_DEPLOY_STAGING_VALUES BRIK_DEPLOY_STAGING_STRATEGY \
            BRIK_DEPLOY_PRODUCTION_HOST BRIK_DEPLOY_PRODUCTION_REMOTE_PATH \
            BRIK_DEPLOY_PRODUCTION_RESTART_CMD \
            BRIK_DEPLOY_COMPOSE_ENV_COMPOSE_FILE 2>/dev/null || true
    }
    Before 'setup_new_fields'
    After 'cleanup_new_fields'

    It "exports BRIK_DEPLOY_STAGING_CHART"
      export_and_check() { config.export_deploy_vars; printf '%s' "${BRIK_DEPLOY_STAGING_CHART:-}"; }
      When call export_and_check
      The output should equal "./charts/myapp"
    End

    It "exports BRIK_DEPLOY_STAGING_RELEASE_NAME"
      export_and_check() { config.export_deploy_vars; printf '%s' "${BRIK_DEPLOY_STAGING_RELEASE_NAME:-}"; }
      When call export_and_check
      The output should equal "myapp-staging"
    End

    It "exports BRIK_DEPLOY_STAGING_VALUES"
      export_and_check() { config.export_deploy_vars; printf '%s' "${BRIK_DEPLOY_STAGING_VALUES:-}"; }
      When call export_and_check
      The output should equal "charts/values-staging.yaml"
    End

    It "exports BRIK_DEPLOY_STAGING_STRATEGY"
      export_and_check() { config.export_deploy_vars; printf '%s' "${BRIK_DEPLOY_STAGING_STRATEGY:-}"; }
      When call export_and_check
      The output should equal "rolling"
    End

    It "exports BRIK_DEPLOY_PRODUCTION_HOST"
      export_and_check() { config.export_deploy_vars; printf '%s' "${BRIK_DEPLOY_PRODUCTION_HOST:-}"; }
      When call export_and_check
      The output should equal "prod.example.com"
    End

    It "exports BRIK_DEPLOY_PRODUCTION_REMOTE_PATH"
      export_and_check() { config.export_deploy_vars; printf '%s' "${BRIK_DEPLOY_PRODUCTION_REMOTE_PATH:-}"; }
      When call export_and_check
      The output should equal "/opt/app"
    End

    It "exports BRIK_DEPLOY_PRODUCTION_RESTART_CMD"
      export_and_check() { config.export_deploy_vars; printf '%s' "${BRIK_DEPLOY_PRODUCTION_RESTART_CMD:-}"; }
      When call export_and_check
      The output should equal "systemctl restart myapp"
    End

    It "exports BRIK_DEPLOY_COMPOSE_ENV_COMPOSE_FILE"
      export_and_check() { config.export_deploy_vars; printf '%s' "${BRIK_DEPLOY_COMPOSE_ENV_COMPOSE_FILE:-}"; }
      When call export_and_check
      The output should equal "docker-compose.prod.yml"
    End
  End
End
