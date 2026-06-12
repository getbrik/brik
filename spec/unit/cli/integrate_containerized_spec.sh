Describe "brik integrate / brik stage - containerized local execution"
  Include "$BRIK_HOME/spec/support/mock_helper.sh"

  # On a bare host (no orchestrator signal, not inside a brik container) the
  # local verbs do NOT execute stages in the host shell: they drive the
  # containerized engine, one runner-class container per stage, exactly like
  # the CI adapters. The docker mock records every engine invocation.
  setup() {
    mock.setup
    WORKSPACE="$(mktemp -d)"
    git -C "$WORKSPACE" init -q
    git -C "$WORKSPACE" config user.email "test@test.com"
    git -C "$WORKSPACE" config user.name "Test"
    printf 'version: 1\nproject:\n  name: cli-flip\n  stack: node\n' \
      > "$WORKSPACE/brik.yml"
    git -C "$WORKSPACE" add brik.yml
    git -C "$WORKSPACE" commit -qm init

    STACK_ENV_FIXTURE="$(mktemp)"
    printf 'BRIK_CI_IMAGE=ghcr.io/getbrik/brik-runner-node:22\n' > "$STACK_ENV_FIXTURE"
    export MOCK_PIPELINE_ENV_FILE="$STACK_ENV_FIXTURE"

    # Mock fidelity: the real engine consumes piped stdin (tar streams,
    # seeded plan files); without this, the seed pipe dies on SIGPIPE under
    # bin/brik's pipefail.
    mock.create_script "docker" "
echo \"docker \$*\" >> \"$MOCK_LOG\"
case \"\$*\" in
  *\" -i \"*) cat > /dev/null 2>&1 || true ;;
esac
case \"\$*\" in
  *\"cat /work/.brik-logs/pipeline.env\"*)
    [ -n \"\${MOCK_PIPELINE_ENV_FILE:-}\" ] && cat \"\$MOCK_PIPELINE_ENV_FILE\"
    ;;
esac
exit 0
"
    mock.activate
  }
  cleanup() {
    mock.cleanup
    rm -rf "$WORKSPACE"
    rm -f "$STACK_ENV_FIXTURE"
    unset MOCK_PIPELINE_ENV_FILE 2>/dev/null || true
  }
  Before 'setup'
  After 'cleanup'

  Describe "brik integrate (bare host)"
    It "runs the engine: plan container then one container per stage"
      check_flip() {
        "$BRIK_BIN" integrate --workspace "$WORKSPACE" >/dev/null 2>&1
        local rc=$?
        local planned="no" init_ran="no" notify_ran="no"
        grep -q -- "--out /work/.brik-logs/plan.json" "$MOCK_LOG" && planned="yes"
        grep -q "container-stage.sh init" "$MOCK_LOG" && init_ran="yes"
        grep -q "container-stage.sh notify" "$MOCK_LOG" && notify_ran="yes"
        echo "rc=$rc plan=$planned init=$init_ran notify=$notify_ran"
      }
      When call check_flip
      The output should equal "rc=0 plan=yes init=yes notify=yes"
    End

    It "forwards the opt-in flags to the engine"
      check_flags() {
        "$BRIK_BIN" integrate --workspace "$WORKSPACE" --with-package >/dev/null 2>&1
        grep -- "--out /work/.brik-logs/plan.json" "$MOCK_LOG"
      }
      When call check_flags
      The output should include "--with-package"
    End

    It "seeds a --plan file onto the volume instead of planning"
      check_plan_seed() {
        local plan_fixture
        plan_fixture="$(mktemp)"
        printf '{"schema":"plan/v1"}\n' > "$plan_fixture"
        "$BRIK_BIN" integrate --workspace "$WORKSPACE" --plan "$plan_fixture" >/dev/null 2>&1
        local rc=$?
        rm -f "$plan_fixture"
        local planner_ran="no" seeded="no"
        grep -q -- "--out /work/.brik-logs/plan.json" "$MOCK_LOG" && planner_ran="yes"
        grep -q "cat > /work/.brik-logs/plan.json" "$MOCK_LOG" && seeded="yes"
        echo "rc=$rc planner=$planner_ran seeded=$seeded"
      }
      When call check_plan_seed
      The output should equal "rc=0 planner=no seeded=yes"
    End

    It "still rejects a missing --plan file on the host side"
      When run script "$BRIK_BIN" integrate --workspace "$WORKSPACE" --plan /nonexistent.json
      The status should equal 2
      The stderr should include "plan file not found"
    End

    It "never executes a stage in the host shell"
      check_no_host_exec() {
        "$BRIK_BIN" integrate --workspace "$WORKSPACE" >/dev/null 2>&1
        # The host-shell path would render a Pipeline Summary from
        # report.render_terminal; the engine only talks to docker.
        "$BRIK_BIN" integrate --workspace "$WORKSPACE" 2>&1 | grep -c "Pipeline Summary" || true
      }
      When call check_no_host_exec
      The output should equal "0"
    End
  End

  Describe "brik stage (bare host)"
    It "runs the stage in its runner-class container after a plan"
      check_stage_flip() {
        "$BRIK_BIN" stage build --workspace "$WORKSPACE" >/dev/null 2>&1
        local rc=$?
        local planned="no" ran="no"
        grep -q -- "--out /work/.brik-logs/plan.json" "$MOCK_LOG" && planned="yes"
        grep -q "container-stage.sh build" "$MOCK_LOG" && ran="yes"
        echo "rc=$rc plan=$planned stage=$ran"
      }
      When call check_stage_flip
      The output should equal "rc=0 plan=yes stage=yes"
    End
  End

  Describe "brik deploy (bare host)"
    It "re-execs the CD verb inside the deploy-class container"
      check_deploy_flip() {
        "$BRIK_BIN" deploy --version v1.2.3 --environment staging >/dev/null 2>&1
        local rc=$?
        local verb="no"
        grep -q "bin/brik deploy --version v1.2.3 --environment staging" "$MOCK_LOG" && verb="yes"
        echo "rc=$rc verb=$verb"
      }
      When call check_deploy_flip
      The output should equal "rc=0 verb=yes"
    End

    It "still validates the required arguments on the host side"
      check_args() {
        "$BRIK_BIN" deploy --environment staging >/dev/null 2>&1
        local rc=$?
        local engine_calls
        engine_calls="$(grep -c "bin/brik deploy" "$MOCK_LOG" 2>/dev/null)" || engine_calls=0
        echo "rc=$rc engine_calls=$engine_calls"
      }
      When call check_args
      The output should equal "rc=2 engine_calls=0"
    End
  End

  Describe "in-container execution context (BRIK_LOCAL_CONTAINER)"
    It "keeps the in-process path: the engine is never invoked"
      check_in_container() {
        # The stage executes in-process and hits the mandatory-referential
        # gate (rc 4) -- proof the stage code ran here, not in a container.
        local err
        err="$(BRIK_LOCAL_CONTAINER=1 BRIK_DRY_RUN=true \
          "$BRIK_BIN" stage init --workspace "$WORKSPACE" 2>&1)"
        local rc=$?
        local engine_calls
        engine_calls="$(grep -c "container-stage.sh" "$MOCK_LOG" 2>/dev/null)" || engine_calls=0
        local in_process="no"
        printf '%s' "$err" | grep -q "initializing pipeline" && in_process="yes"
        echo "rc=$rc engine_calls=$engine_calls in_process=$in_process"
      }
      When call check_in_container
      The output should equal "rc=4 engine_calls=0 in_process=yes"
    End
  End
End
