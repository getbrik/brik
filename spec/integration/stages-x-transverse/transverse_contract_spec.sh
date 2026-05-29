# L2 edge: Stages -> Transverse (graph edge #5)
#
# Stages consume transverse helpers for cross-cutting concerns. This pins the
# three contracts stages rely on: config.read/config.get (init/notify/promote
# read brik.yml through these), env.resolve_indirect (deploy resolves
# BRIK_DEPLOY_<ENV>_TARGET through this), and wait.until (rollout/deploy poll
# readiness through this). The helpers' internal branches are L1; here we pin
# the behavior stages depend on.

Describe "L2 stages -> transverse: config/env/wait contract"
  Include "$BRIK_HOME/lib/pipeline/logging.sh"
  Include "$BRIK_HOME/lib/transverse/config.sh"
  Include "$BRIK_HOME/lib/transverse/env.sh"
  Include "$BRIK_HOME/lib/transverse/wait.sh"

  Describe "config.read + config.get"
    setup_cfg() {
      CFG_WS="$(mktemp -d)"
      export BRIK_CONFIG_FILE="$CFG_WS/brik.yml"
      printf 'version: 1\nproject:\n  name: edge-proj\n  stack: node\n' > "$BRIK_CONFIG_FILE"
      config.read "$BRIK_CONFIG_FILE" >/dev/null 2>&1 || true
    }
    cleanup_cfg() {
      rm -rf "$CFG_WS"
      unset BRIK_CONFIG_FILE
    }
    Before 'setup_cfg'
    After 'cleanup_cfg'

    It "reads a declared config value"
      get_name() { config.get .project.name missing; }
      When call get_name
      The output should equal "edge-proj"
    End

    It "returns the default for an absent key"
      get_default() { config.get .project.nonexistent fallback; }
      When call get_default
      The output should equal "fallback"
    End
  End

  Describe "env.resolve_indirect (deploy resolves BRIK_DEPLOY_<ENV>_TARGET through this)"
    It "resolves the value of the named variable"
      resolve_set() {
        export BRIK_DEPLOY_STAGING_TARGET=k8s
        transverse.env.resolve_indirect BRIK_DEPLOY_STAGING_TARGET
      }
      When call resolve_set
      The output should equal "k8s"
    End

    It "returns empty for an unset variable"
      resolve_unset() { transverse.env.resolve_indirect BRIK_DEPLOY_NOPE_TARGET; }
      When call resolve_unset
      The output should equal ""
    End
  End

  Describe "wait.until (rollout/deploy poll readiness through this)"
    It "returns 0 immediately when the check passes on the first poll"
      ready_now() { return 0; }
      run_wait() { transverse.wait.until ready_now --timeout 5 --interval 2; }
      When call run_wait
      The status should be success
      The stderr should include "completed"
    End
  End
End
