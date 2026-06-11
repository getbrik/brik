Describe "docker-runner.sh"
  Include "$BRIK_HOME/spec/support/mock_helper.sh"

  # Shared fixture: a committed git project, a node config, a bootstrapped
  # local runtime (log.*, registry.*, BRIK_EXIT_*), and a docker mock that
  # records every invocation to MOCK_LOG.
  #
  # Mock contract:
  #   MOCK_DOCKER_RC          exit code for every docker call (default 0)
  #   MOCK_DOCKER_FAIL_MATCH  substring of "$*"; matching calls exit 1
  #   MOCK_PIPELINE_ENV_FILE  emitted on stdout for pipeline.env reads
  setup_runner() {
    mock.setup
    PROJECT_DIR="$(mktemp -d)"
    git -C "$PROJECT_DIR" init -q
    git -C "$PROJECT_DIR" config user.email "test@test.com"
    git -C "$PROJECT_DIR" config user.name "Test"
    printf 'version: 1\nproject:\n  name: dr-test\n  stack: node\n' \
      > "$PROJECT_DIR/brik.yml"
    git -C "$PROJECT_DIR" add brik.yml
    git -C "$PROJECT_DIR" commit -qm init

    export BRIK_CONFIG_FILE="$PROJECT_DIR/brik.yml"
    export BRIK_PROJECT_DIR="$PROJECT_DIR"
    export BRIK_WORKSPACE="$PROJECT_DIR"
    export BRIK_LOG_DIR
    BRIK_LOG_DIR="$(mktemp -d)"

    brik.local.setup >/dev/null 2>&1 || true

    # Emulate the dotenv channel: init posts BRIK_CI_IMAGE into the volume
    # pipeline.env before any stack-class stage runs. Tests covering the
    # "never posted" path override MOCK_PIPELINE_ENV_FILE with "".
    STACK_ENV_FIXTURE="$(mktemp)"
    printf 'BRIK_CI_IMAGE=ghcr.io/getbrik/brik-runner-node:22\n' > "$STACK_ENV_FIXTURE"
    export MOCK_PIPELINE_ENV_FILE="$STACK_ENV_FIXTURE"

    mock.create_script "docker" "
echo \"docker \$*\" >> \"$MOCK_LOG\"
case \"\$*\" in
  *\"cat /work/.brik-logs/pipeline.env\"*)
    [ -n \"\${MOCK_PIPELINE_ENV_FILE:-}\" ] && cat \"\$MOCK_PIPELINE_ENV_FILE\"
    ;;
esac
if [ -n \"\${MOCK_DOCKER_FAIL_MATCH:-}\" ]; then
  case \"\$*\" in
    *\"\$MOCK_DOCKER_FAIL_MATCH\"*) exit 1 ;;
  esac
fi
exit \"\${MOCK_DOCKER_RC:-0}\"
"
    mock.activate
  }
  cleanup_runner() {
    mock.cleanup
    rm -rf "$PROJECT_DIR" "$BRIK_LOG_DIR"
    rm -f "$STACK_ENV_FIXTURE"
    unset MOCK_DOCKER_RC MOCK_DOCKER_FAIL_MATCH MOCK_PIPELINE_ENV_FILE 2>/dev/null || true
  }

  # =========================================================================
  # brik.local.docker.check_engine
  # =========================================================================
  Describe "brik.local.docker.check_engine"
    Include "$BRIK_HOME/shared-libs/local/scripts/local-wrapper.sh"
    Include "$BRIK_HOME/shared-libs/local/scripts/docker-runner.sh"
    Before 'setup_runner'
    After 'cleanup_runner'

    It "succeeds when the docker daemon responds"
      When call brik.local.docker.check_engine
      The status should be success
    End

    It "queries the daemon (not just the binary) so DOCKER_HOST is honored"
      check_call() {
        brik.local.docker.check_engine >/dev/null 2>&1
        mock.call_args "docker"
      }
      When call check_call
      The output should include "version"
    End

    It "returns MISSING_DEP when docker is not installed"
      no_docker() {
        rm -f "${MOCK_BIN}/docker"
        PATH="$MOCK_BIN" brik.local.docker.check_engine
      }
      When call no_docker
      The status should equal 3
      The error should include "docker"
    End

    It "returns INVALID_ENV when the daemon is unreachable"
      check_daemon_down() {
        MOCK_DOCKER_RC=1 brik.local.docker.check_engine
      }
      When call check_daemon_down
      The status should equal 4
      The error should include "daemon"
    End
  End

  # =========================================================================
  # volume lifecycle
  # =========================================================================
  Describe "volume lifecycle"
    Include "$BRIK_HOME/shared-libs/local/scripts/local-wrapper.sh"
    Include "$BRIK_HOME/shared-libs/local/scripts/docker-runner.sh"
    Before 'setup_runner'
    After 'cleanup_runner'

    It "derives the volume name from the run id"
      When call brik.local.docker.volume_name "123-9"
      The output should equal "brik-run-123-9"
    End

    It "creates the run volume"
      check_create() {
        brik.local.docker.create_volume "123-9" >/dev/null 2>&1
        mock.call_args "docker"
      }
      When call check_create
      The output should include "volume create brik-run-123-9"
    End

    It "destroys the run volume"
      check_destroy() {
        brik.local.docker.destroy_volume "123-9" >/dev/null 2>&1
        mock.call_args "docker"
      }
      When call check_destroy
      The output should include "volume rm"
      The output should include "brik-run-123-9"
    End
  End

  # =========================================================================
  # brik.local.docker.seed_workspace
  # =========================================================================
  Describe "brik.local.docker.seed_workspace"
    Include "$BRIK_HOME/shared-libs/local/scripts/local-wrapper.sh"
    Include "$BRIK_HOME/shared-libs/local/scripts/docker-runner.sh"
    Before 'setup_runner'
    After 'cleanup_runner'

    It "rejects a directory that is not a git work tree"
      check_reject() {
        local plain_dir
        plain_dir="$(mktemp -d)"
        brik.local.docker.seed_workspace "123-9" "$plain_dir"
        local rc=$?
        rm -rf "$plain_dir"
        return "$rc"
      }
      When call check_reject
      The status should equal 2
      The error should include "git"
    End

    It "copies .git into the volume and aligns ownership on the host uid:gid"
      check_seed() {
        brik.local.docker.seed_workspace "123-9" "$PROJECT_DIR" >/dev/null 2>&1
        cat "$MOCK_LOG"
      }
      When call check_seed
      The output should include "-v brik-run-123-9:/work"
      The output should include "chown -R $(id -u):$(id -g) /work"
    End

    It "materializes tracked files with git checkout as the run uid"
      check_checkout() {
        brik.local.docker.seed_workspace "123-9" "$PROJECT_DIR" >/dev/null 2>&1
        grep "checkout" "$MOCK_LOG"
      }
      When call check_checkout
      The output should include "--user $(id -u):$(id -g)"
      The output should include "git -C /work checkout -f HEAD"
    End

    It "prepares the writable HOME and the log dir on the volume"
      check_dirs() {
        brik.local.docker.seed_workspace "123-9" "$PROJECT_DIR" >/dev/null 2>&1
        cat "$MOCK_LOG"
      }
      When call check_dirs
      The output should include ".brik-home"
      The output should include ".brik-logs"
    End

    It "seeds with the base runner-class image"
      check_image() {
        brik.local.docker.seed_workspace "123-9" "$PROJECT_DIR" >/dev/null 2>&1
        cat "$MOCK_LOG"
      }
      When call check_image
      The output should include "ghcr.io/getbrik/brik-runner-base"
    End
  End

  # =========================================================================
  # brik.local.docker.stage_image
  # =========================================================================
  Describe "brik.local.docker.stage_image"
    Include "$BRIK_HOME/shared-libs/local/scripts/local-wrapper.sh"
    Include "$BRIK_HOME/shared-libs/local/scripts/docker-runner.sh"
    Before 'setup_runner'
    After 'cleanup_runner'

    It "resolves a static class straight from the registry"
      When call brik.local.docker.stage_image "123-9" "init"
      The output should include "ghcr.io/getbrik/brik-runner-base"
    End

    It "resolves the stack class from BRIK_CI_IMAGE posted in the volume pipeline.env"
      check_stack() {
        local env_fixture
        env_fixture="$(mktemp)"
        printf 'BRIK_CI_IMAGE=ghcr.io/getbrik/brik-runner-node:22\n' > "$env_fixture"
        MOCK_PIPELINE_ENV_FILE="$env_fixture" \
          brik.local.docker.stage_image "123-9" "build"
        local rc=$?
        rm -f "$env_fixture"
        return "$rc"
      }
      When call check_stack
      The status should be success
      The output should include "ghcr.io/getbrik/brik-runner-node:22"
    End

    It "fails when the stack image was never posted by init"
      check_unposted() {
        MOCK_PIPELINE_ENV_FILE="" brik.local.docker.stage_image "123-9" "build"
      }
      When call check_unposted
      The status should equal 2
      The error should include "BRIK_CI_IMAGE"
    End
  End

  # =========================================================================
  # brik.local.docker.run_stage_container
  # =========================================================================
  Describe "brik.local.docker.run_stage_container"
    Include "$BRIK_HOME/shared-libs/local/scripts/local-wrapper.sh"
    Include "$BRIK_HOME/shared-libs/local/scripts/docker-runner.sh"
    Before 'setup_runner'
    After 'cleanup_runner'

    It "applies the mitigated uid profile: --user, writable HOME, volume at /work"
      check_argv() {
        brik.local.docker.run_stage_container "123-9" "init" >/dev/null 2>&1
        mock.call_args "docker"
      }
      When call check_argv
      The output should include "--user $(id -u):$(id -g)"
      The output should include "-e HOME=/work/.brik-home"
      The output should include "-v brik-run-123-9:/work"
      The output should include "-w /work"
    End

    It "mounts the brik runtime read-only and points BRIK_HOME at it"
      check_brik_home() {
        brik.local.docker.run_stage_container "123-9" "init" >/dev/null 2>&1
        mock.call_args "docker"
      }
      When call check_brik_home
      The output should include "-v ${BRIK_HOME}:/opt/brik:ro"
      The output should include "-e BRIK_HOME=/opt/brik"
    End

    It "injects the container-side BRIK contract (workspace, config, logs, plan)"
      check_env() {
        brik.local.docker.run_stage_container "123-9" "init" >/dev/null 2>&1
        mock.call_args "docker"
      }
      When call check_env
      The output should include "-e BRIK_WORKSPACE=/work"
      The output should include "-e BRIK_PROJECT_DIR=/work"
      The output should include "-e BRIK_CONFIG_FILE=/work/brik.yml"
      The output should include "-e BRIK_LOG_DIR=/work/.brik-logs"
      The output should include "-e BRIK_PLAN_FILE=/work/.brik-logs/plan.json"
    End

    It "runs the container-stage entry with the stage id"
      check_entry() {
        brik.local.docker.run_stage_container "123-9" "init" >/dev/null 2>&1
        mock.call_args "docker"
      }
      When call check_entry
      The output should include "bash /opt/brik/shared-libs/local/scripts/container-stage.sh init"
    End

    It "stamps the launched image into BRIK_RUNNER_IMAGE (runner provenance)"
      check_provenance() {
        brik.local.docker.run_stage_container "123-9" "sast" >/dev/null 2>&1
        mock.call_args "docker"
      }
      When call check_provenance
      The output should include "-e BRIK_RUNNER_IMAGE=ghcr.io/getbrik/brik-runner-analysis"
    End

    It "mounts the infrastructure referential read-only when configured"
      check_infra() {
        local infra_dir
        infra_dir="$(mktemp -d)"
        BRIK_INFRA_DIR="$infra_dir" \
          brik.local.docker.run_stage_container "123-9" "init" >/dev/null 2>&1
        local args
        args="$(mock.call_args "docker")"
        rm -rf "$infra_dir"
        printf '%s' "$args"
      }
      When call check_infra
      The output should include ":/etc/brik/infra:ro"
      The output should include "-e BRIK_INFRA_DIR=/etc/brik/infra"
    End

    It "forwards host env vars referenced as env:// by the referential credentials"
      check_env_refs() {
        local infra_dir
        infra_dir="$(mktemp -d)"
        mkdir -p "$infra_dir/credentials"
        printf 'apiVersion: brik.dev/referential/v1\nkind: Credential\nmethod: basic\nref: env://DR_SPEC_TOKEN\n' \
          > "$infra_dir/credentials/registry.yml"
        BRIK_INFRA_DIR="$infra_dir" DR_SPEC_TOKEN="s3cret" \
          brik.local.docker.run_stage_container "123-9" "init" >/dev/null 2>&1
        local args
        args="$(mock.call_args "docker")"
        rm -rf "$infra_dir"
        printf '%s' "$args"
      }
      When call check_env_refs
      The output should include "-e DR_SPEC_TOKEN"
      # value-less -e: the secret must never appear in the docker argv
      The output should not include "s3cret"
    End

    It "skips env:// refs that are not set in the host environment"
      check_unset_ref() {
        local infra_dir
        infra_dir="$(mktemp -d)"
        mkdir -p "$infra_dir/credentials"
        printf 'ref: env://DR_SPEC_UNSET_TOKEN\n' \
          > "$infra_dir/credentials/registry.yml"
        BRIK_INFRA_DIR="$infra_dir" \
          brik.local.docker.run_stage_container "123-9" "init" >/dev/null 2>&1
        local args
        args="$(mock.call_args "docker")"
        rm -rf "$infra_dir"
        printf '%s' "$args"
      }
      When call check_unset_ref
      The output should not include "DR_SPEC_UNSET_TOKEN"
    End

    It "forwards BRIK_LOG_LEVEL and BRIK_DRY_RUN when set"
      check_passthrough() {
        BRIK_LOG_LEVEL=debug BRIK_DRY_RUN=true \
          brik.local.docker.run_stage_container "123-9" "init" >/dev/null 2>&1
        mock.call_args "docker"
      }
      When call check_passthrough
      The output should include "-e BRIK_LOG_LEVEL"
      The output should include "-e BRIK_DRY_RUN"
    End

    It "rejects a config file living outside the project directory"
      check_outside() {
        local outside_cfg
        outside_cfg="$(mktemp)"
        BRIK_CONFIG_FILE="$outside_cfg" \
          brik.local.docker.run_stage_container "123-9" "init"
        local rc=$?
        rm -f "$outside_cfg"
        return "$rc"
      }
      When call check_outside
      The status should equal 2
      The error should include "outside"
    End

    It "propagates the container exit code"
      check_rc() {
        MOCK_DOCKER_FAIL_MATCH="container-stage.sh init" \
          brik.local.docker.run_stage_container "123-9" "init"
      }
      When call check_rc
      The status should equal 1
    End
  End

  # =========================================================================
  # brik.local.docker.run_pipeline
  # =========================================================================
  Describe "brik.local.docker.run_pipeline"
    Include "$BRIK_HOME/shared-libs/local/scripts/local-wrapper.sh"
    Include "$BRIK_HOME/shared-libs/local/scripts/docker-runner.sh"
    Before 'setup_runner'
    After 'cleanup_runner'

    It "rejects unknown flags"
      When call brik.local.docker.run_pipeline --bad-flag
      The status should equal 2
      The error should include "unknown"
    End

    It "sequences seed, plan, then stages in registry order"
      check_order() {
        brik.local.docker.run_pipeline >/dev/null 2>&1
        local seed_line plan_line init_line notify_line
        seed_line="$(grep -n "chown -R" "$MOCK_LOG" | head -1 | cut -d: -f1)"
        plan_line="$(grep -n -- "--out /work/.brik-logs/plan.json" "$MOCK_LOG" | head -1 | cut -d: -f1)"
        init_line="$(grep -n "container-stage.sh init" "$MOCK_LOG" | head -1 | cut -d: -f1)"
        notify_line="$(grep -n "container-stage.sh notify" "$MOCK_LOG" | head -1 | cut -d: -f1)"
        if [[ -n "$seed_line" && -n "$plan_line" && -n "$init_line" && -n "$notify_line" ]] \
           && [[ "$seed_line" -lt "$plan_line" ]] \
           && [[ "$plan_line" -lt "$init_line" ]] \
           && [[ "$init_line" -lt "$notify_line" ]]; then
          echo "ordered"
        else
          echo "broken: seed=$seed_line plan=$plan_line init=$init_line notify=$notify_line"
        fi
      }
      When call check_order
      The output should equal "ordered"
    End

    It "launches one container per registry stage"
      check_stages() {
        brik.local.docker.run_pipeline >/dev/null 2>&1
        local stage missing=""
        while IFS= read -r stage; do
          grep -q "container-stage.sh ${stage}\$" "$MOCK_LOG" || missing="${missing} ${stage}"
        done < <(registry.stage.list)
        if [[ -z "$missing" ]]; then echo "all_launched"; else echo "missing:${missing}"; fi
      }
      When call check_stages
      The output should equal "all_launched"
    End

    It "passes the opt-in flags to the plan container"
      check_flags() {
        brik.local.docker.run_pipeline --with-release --with-package >/dev/null 2>&1
        grep -- "--out /work/.brik-logs/plan.json" "$MOCK_LOG"
      }
      When call check_flags
      The output should include "--with-release"
      The output should include "--with-package"
    End

    It "destroys the volume after a fully green run"
      check_green() {
        brik.local.docker.run_pipeline >/dev/null 2>&1 && grep "volume rm" "$MOCK_LOG"
      }
      When call check_green
      The status should be success
      The output should include "volume rm"
    End

    It "stops at the first failed stage, still notifies, and keeps the volume"
      check_failure() {
        MOCK_DOCKER_FAIL_MATCH="container-stage.sh build" \
          brik.local.docker.run_pipeline >/dev/null 2>&1
        local rc=$?
        local test_ran="no" notify_ran="no" volume_removed="no"
        grep -q "container-stage.sh test" "$MOCK_LOG" && test_ran="yes"
        grep -q "container-stage.sh notify" "$MOCK_LOG" && notify_ran="yes"
        grep -q "volume rm" "$MOCK_LOG" && volume_removed="yes"
        echo "rc=$rc test=$test_ran notify=$notify_ran removed=$volume_removed"
      }
      When call check_failure
      The output should equal "rc=1 test=no notify=yes removed=no"
    End

    It "keeps running after a failure with --continue-on-error"
      check_continue() {
        MOCK_DOCKER_FAIL_MATCH="container-stage.sh build" \
          brik.local.docker.run_pipeline --continue-on-error >/dev/null 2>&1
        local rc=$?
        local test_ran="no"
        grep -q "container-stage.sh test" "$MOCK_LOG" && test_ran="yes"
        echo "rc=$rc test=$test_ran"
      }
      When call check_continue
      The output should equal "rc=1 test=yes"
    End

    It "extracts the run logs back to the host"
      check_extract() {
        brik.local.docker.run_pipeline >/dev/null 2>&1
        grep "tar" "$MOCK_LOG" | grep -c "brik-logs" | { read -r n; [ "$n" -ge 1 ] && echo "extracted"; }
      }
      When call check_extract
      The output should equal "extracted"
    End

    It "aborts before any container when the daemon is unreachable"
      check_no_daemon() {
        MOCK_DOCKER_RC=1 brik.local.docker.run_pipeline >/dev/null 2>&1
        local rc=$?
        local runs
        runs="$(grep -c "container-stage.sh" "$MOCK_LOG")" || runs=0
        echo "rc=$rc stage_runs=$runs"
      }
      When call check_no_daemon
      The output should equal "rc=4 stage_runs=0"
    End
  End
End
