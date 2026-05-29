# L2 edge: Deployments -> Rollout (graph edge #10)
#
# After applying, a deployment relies on the rollout notion to gate on health
# and to orchestrate the rollout strategy. This pins two contracts:
#   - rollout.health.wait polls the endpoint and times out with
#     BRIK_EXIT_TIMEOUT when the app never becomes healthy (curl mocked);
#   - rollout.strategy.run delegates to the deploy function (the path a
#     strategy-driven deployment actually takes).

Describe "L2 deployments -> rollout: health gate + strategy delegation"
  Include "$BRIK_PIPELINE_LIB/logging.sh"
  Include "$BRIK_PIPELINE_LIB/tools.sh"
  Include "$BRIK_PIPELINE_LIB/loader.sh"
  Include "$BRIK_TRANSVERSE_LIB/wait.sh"
  Include "$BRIK_ROLLOUT_LIB/health.sh"
  Include "$BRIK_ROLLOUT_LIB/strategy.sh"
  Include "$BRIK_HOME/spec/support/mock_helper.sh"

  Describe "health gate"
    Describe "healthy endpoint"
      setup_ok() { mock.setup; mock.create_output curl 200; mock.activate; }
      cleanup_ok() { mock.cleanup; }
      Before 'setup_ok'
      After 'cleanup_ok'

      It "returns 0 when the endpoint reports 200"
        run_ok() { rollout.health.wait --url "http://x/health" --timeout 5 --interval 1 2>/dev/null; }
        When call run_ok
        The status should be success
      End
    End

    Describe "unhealthy endpoint"
      setup_to() { mock.setup; mock.create_output curl 503; mock.activate; }
      cleanup_to() { mock.cleanup; }
      Before 'setup_to'
      After 'cleanup_to'

      It "times out with BRIK_EXIT_TIMEOUT when never healthy"
        run_to() { rollout.health.wait --url "http://x/health" --timeout 1 --interval 1; }
        When call run_to
        The status should equal 8
        The stderr should include "timeout"
      End
    End
  End

  Describe "strategy delegation"
    It "invokes the deploy function within a rolling strategy"
      run_strategy() {
        local marker
        marker="$(mktemp -u)"
        my_deploy() { : > "$marker"; return 0; }
        rollout.strategy.run --type rolling --deploy-fn my_deploy >/dev/null 2>&1
        [ -f "$marker" ] && { rm -f "$marker"; return 0; }
        return 1
      }
      When call run_strategy
      The status should be success
    End
  End
End
