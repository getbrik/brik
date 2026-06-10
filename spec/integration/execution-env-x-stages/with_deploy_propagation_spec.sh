# L2 edge: Execution environment -> Stages (graph edge #1)
#
# Reproduces divergence D1 of e2e-cross-platform-v0.6.0: the BRIK_WITH_DEPLOY
# opt-in must reach the deploy stage's gate. Each CI execution environment
# (GitLab plan.yml, Jenkins brikIntegrate.groovy) translates the env var into
# the `--with-deploy` flag passed to `brik plan`. This spec pins the bash
# boundary of that contract -- `brik plan` MUST gate the deploy stage solely
# on `--with-deploy` -- so the divergence is caught in ~1s without running
# GitLab and Jenkins in parallel.

Describe "L2 execution-env -> stages: --with-deploy propagation (D1)"
  Include "$BRIK_HOME/spec/support/mock_helper.sh"

  setup_ws() {
    mock.infra.setup
    WS="$(mktemp -d)"
    export BRIK_WORKSPACE="$WS"
    export BRIK_LOG_DIR="$WS/.brik-logs"
    mkdir -p "$BRIK_LOG_DIR"
    (
      cd "$WS" || exit 1
      git init -q -b main
      git config user.email "test@brik.dev"
      git config user.name "test"
      printf '{"name":"d1","version":"1.0.0"}\n' > package.json
      printf 'project:\n  name: d1\n  stack: node\n' > brik.yml
      git add -A
      git commit -q -m "baseline"
    )
  }
  cleanup_ws() {
    mock.infra.teardown
    rm -rf "$WS"
    unset BRIK_WORKSPACE BRIK_LOG_DIR
  }
  Before 'setup_ws'
  After 'cleanup_ws'

  deploy_field() {
    # $1 = jq field (decision|reason); remaining args = extra plan flags
    local field="$1"; shift
    "$BRIK_BIN" plan --workspace "$WS" --mode safe "$@" \
      --out "$BRIK_LOG_DIR/plan.json" >/dev/null 2>&1
    jq -r --arg f "$field" '.stages[] | select(.id == "deploy") | .[$f]' \
      "$BRIK_LOG_DIR/plan.json"
  }

  It "skips deploy when the opt-in flag is absent"
    When call deploy_field decision
    The output should equal "skip"
  End

  It "reports opt-in-flag-missing as the skip reason"
    When call deploy_field reason
    The output should equal "opt-in-flag-missing"
  End

  It "runs deploy when --with-deploy is passed (D1 contract)"
    When call deploy_field decision --with-deploy
    The output should equal "run"
  End
End
