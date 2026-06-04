# L2 edge: Stages -> Deployments (graph edge #4)
#
# The deploy stage reads deploy.environments[].target from brik.yml and
# dispatches to deployments.<target>.run (deploy.<target>.run). This pins the
# dispatch contract -- the right target function gets the right args -- and the
# error path when the target has no module (the gap flagged for this edge).

Describe "L2 stages -> deployments: deploy stage dispatches by target"
  Include "$BRIK_HOME/lib/pipeline/stage.sh"
  Include "$BRIK_HOME/lib/pipeline/loader.sh"
  Include "$BRIK_HOME/lib/pipeline/report.sh"
  Include "$BRIK_HOME/lib/transverse/config.sh"
  Include "$BRIK_HOME/lib/transverse/conditions.sh"
  Include "$BRIK_HOME/lib/transverse/env.sh"
  Include "$BRIK_HOME/lib/stages/deploy.sh"
  Include "$BRIK_HOME/spec/support/mock_helper.sh"

  setup_env() {
    export BRIK_CONFIG_FILE
    BRIK_CONFIG_FILE="$(mktemp)"
    mock.workspace.setup
    export BRIK_LOG_DIR
    BRIK_LOG_DIR="$(mktemp -d)"
    export BRIK_PROJECT_DIR="$BRIK_WORKSPACE"
    export BRIK_PLATFORM="gitlab"
    export BRIK_RUN_ID="stages-x-deploy-fixture"
  }
  cleanup_env() {
    rm -f "$BRIK_CONFIG_FILE"
    rm -rf "$BRIK_LOG_DIR"
    mock.workspace.teardown
    unset BRIK_RUN_ID 2>/dev/null || true
  }
  Before 'setup_env'
  After 'cleanup_env'

  Describe "known target dispatch"
    setup_k8s() {
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
      report.init >/dev/null 2>&1 || true
    }
    Before 'setup_k8s'

    It "calls deploy.k8s.run with --target k8s and the namespace"
      run_dispatch() {
        brik.use() { :; }
        deploy.k8s.run() { printf '%s ' "$@"; return 0; }
        local ctx
        ctx="$(context.create deploy)" 2>/dev/null || ctx="$(mktemp)"
        stages.deploy "$ctx" 2>/dev/null
      }
      When call run_dispatch
      The output should include "--target k8s"
      The output should include "--namespace staging-ns"
    End
  End

  Describe "unknown target rejection"
    setup_bogus() {
      cat > "$BRIK_CONFIG_FILE" <<'YAML'
version: 1
project:
  name: test
  stack: node
deploy:
  environments:
    staging:
      target: bogus-provider
      namespace: x
YAML
      config.read "$BRIK_CONFIG_FILE" >/dev/null 2>&1 || true
      report.init >/dev/null 2>&1 || true
    }
    Before 'setup_bogus'

    It "fails when the deploy target has no module"
      run_unknown() {
        brik.use() { return 1; }
        local ctx
        ctx="$(context.create deploy)" 2>/dev/null || ctx="$(mktemp)"
        stages.deploy "$ctx" 2>&1
      }
      When call run_unknown
      The status should not equal 0
      The output should include "unsupported deploy target"
    End
  End

  # Regression (chantier 25): a workflow profile injects a k8s-centric
  # `namespace` default into every env. When the user overrides `target` to
  # gitops (which has no --namespace option), deploy.sh must NOT leak
  # --namespace to that target -- otherwise deploy.gitops.run aborts with
  # "unknown option: --namespace". deploy.sh filters --namespace to the
  # targets that consume it (k8s/helm/compose).
  Describe "gitops target does not receive --namespace"
    setup_gitops() {
      cat > "$BRIK_CONFIG_FILE" <<'YAML'
version: 1
project:
  name: test
  stack: node
deploy:
  environments:
    staging:
      target: gitops
      namespace: staging-ns
      repo: https://example.test/config.git
      path: k8s
      source: k8s
YAML
      config.read "$BRIK_CONFIG_FILE" >/dev/null 2>&1 || true
      report.init >/dev/null 2>&1 || true
    }
    Before 'setup_gitops'

    It "dispatches deploy.gitops.run without --namespace even when namespace is set"
      run_dispatch() {
        brik.use() { :; }
        deploy.gitops.run() { printf '%s ' "$@"; return 0; }
        local ctx
        ctx="$(context.create deploy)" 2>/dev/null || ctx="$(mktemp)"
        stages.deploy "$ctx" 2>/dev/null
      }
      When call run_dispatch
      The output should include "--target gitops"
      The output should not include "--namespace"
    End
  End
End
