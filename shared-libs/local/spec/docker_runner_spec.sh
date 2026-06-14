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

    It "marks the container as brik-local execution context"
      check_marker() {
        brik.local.docker.run_stage_container "123-9" "init" >/dev/null 2>&1
        mock.call_args "docker"
      }
      When call check_marker
      The output should include "-e BRIK_LOCAL_CONTAINER=1"
    End
  End

  # =========================================================================
  # Governed docker socket (manifest-scoped, H8)
  # =========================================================================
  Describe "docker socket scoped by the stage manifest"
    Include "$BRIK_HOME/shared-libs/local/scripts/local-wrapper.sh"
    Include "$BRIK_HOME/shared-libs/local/scripts/docker-runner.sh"
    Before 'setup_runner'
    After 'cleanup_runner'

    It "mounts the host socket into a stage whose manifest declares runner.docker"
      check_socket() {
        brik.local.docker.run_stage_container "123-9" "package" >/dev/null 2>&1
        mock.call_args "docker"
      }
      When call check_socket
      The output should include "-v /var/run/docker.sock:/var/run/docker.sock"
    End

    It "does NOT mount the socket into a stage without the declaration"
      check_no_socket() {
        brik.local.docker.run_stage_container "123-9" "init" >/dev/null 2>&1
        mock.call_args "docker"
      }
      When call check_no_socket
      The output should not include "docker.sock"
    End

    It "honors a unix:// DOCKER_HOST as the socket source"
      check_unix_host() {
        DOCKER_HOST="unix:///tmp/custom-docker.sock" \
          brik.local.docker.run_stage_container "123-9" "package" >/dev/null 2>&1
        mock.call_args "docker"
      }
      When call check_unix_host
      The output should include "-v /tmp/custom-docker.sock:/var/run/docker.sock"
    End

    It "forwards a remote DOCKER_HOST instead of mounting a socket"
      check_remote_host() {
        DOCKER_HOST="tcp://10.0.0.5:2376" \
          brik.local.docker.run_stage_container "123-9" "package" >/dev/null 2>&1
        mock.call_args "docker"
      }
      When call check_remote_host
      The output should include "-e DOCKER_HOST"
      The output should not include "docker.sock:"
    End

    It "adds the socket group on a Linux host (root:docker 0660 socket)"
      check_group_add() {
        # H8: on Linux the socket is root:docker 0660, so the arbitrary-uid
        # container user needs the socket's gid as a supplementary group.
        mock.create_script "uname" 'echo Linux'
        mock.create_script "stat" 'echo 999'
        brik.local.docker.run_stage_container "123-9" "package" >/dev/null 2>&1
        mock.call_args "docker"
      }
      When call check_group_add
      The output should include "--group-add 999"
    End

    It "does not add a group on a non-Linux host (Docker Desktop 0666 socket)"
      check_no_group() {
        # Pin the host OS: on a real Linux runner the un-mocked uname would
        # take the group-add branch and the example would test the host, not
        # the contract.
        mock.create_script "uname" 'echo Darwin'
        brik.local.docker.run_stage_container "123-9" "package" >/dev/null 2>&1
        mock.call_args "docker"
      }
      When call check_no_group
      The output should not include "--group-add"
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

    It "runs verify-group siblings independently when one fails (CI parity)"
      # lint, sast, scan, test share placement.group=verify (after: build).
      # A failed lint must NOT skip its siblings, exactly as the parallel CI
      # group behaves; downstream (after the group) still stops; notify runs.
      check_siblings() {
        MOCK_DOCKER_FAIL_MATCH="container-stage.sh lint" \
          brik.local.docker.run_pipeline >/dev/null 2>&1
        local rc=$?
        local sast scan test notify
        grep -q "container-stage.sh sast" "$MOCK_LOG" && sast=yes || sast=no
        grep -q "container-stage.sh scan" "$MOCK_LOG" && scan=yes || scan=no
        grep -q "container-stage.sh test" "$MOCK_LOG" && test=yes || test=no
        grep -q "container-stage.sh notify" "$MOCK_LOG" && notify=yes || notify=no
        echo "rc=$rc sast=$sast scan=$scan test=$test notify=$notify"
      }
      When call check_siblings
      The output should equal "rc=1 sast=yes scan=yes test=yes notify=yes"
    End

    It "logs the real exit code of a failed stage, not rc=0"
      check_rc() {
        MOCK_DOCKER_FAIL_MATCH="container-stage.sh lint" \
          brik.local.docker.run_pipeline 2>&1 \
          | grep -oE "stage lint failed \(rc=[0-9]+\)"
      }
      When call check_rc
      The output should equal "stage lint failed (rc=1)"
    End

    It "threads --platform into every engine run when BRIK_LOCAL_PLATFORM is set"
      check_platform() {
        BRIK_LOCAL_PLATFORM=linux/amd64 \
          brik.local.docker.run_pipeline >/dev/null 2>&1
        local runs untagged
        runs="$(grep -c "docker run" "$MOCK_LOG")"
        untagged="$(grep "docker run" "$MOCK_LOG" | grep -vc -- "--platform linux/amd64")"
        [[ "$runs" -gt 0 && "$untagged" -eq 0 ]] && echo "ok" \
          || echo "runs=$runs untagged=$untagged"
      }
      When call check_platform
      The output should equal "ok"
    End

    It "emits no --platform by default"
      check_no_platform() {
        brik.local.docker.run_pipeline >/dev/null 2>&1
        grep -c -- "--platform" "$MOCK_LOG" || true
      }
      When call check_no_platform
      The output should equal "0"
    End

    It "bind-mounts the project dir instead of a volume when BRIK_LOCAL_BIND_MOUNT=1"
      check_bind() {
        BRIK_LOCAL_BIND_MOUNT=1 \
          brik.local.docker.run_pipeline >/dev/null 2>&1
        local bound created
        grep -q -- "-v ${PROJECT_DIR}:/work" "$MOCK_LOG" && bound=yes || bound=no
        grep -q "volume create" "$MOCK_LOG" && created=yes || created=no
        echo "bound=$bound volume_created=$created"
      }
      When call check_bind
      The output should equal "bound=yes volume_created=no"
    End

    It "uses a volume (not the project dir) by default"
      check_volume_default() {
        brik.local.docker.run_pipeline >/dev/null 2>&1
        local created bound
        grep -q "volume create" "$MOCK_LOG" && created=yes || created=no
        grep -q -- "-v ${PROJECT_DIR}:/work" "$MOCK_LOG" && bound=yes || bound=no
        echo "volume_created=$created project_bound=$bound"
      }
      When call check_volume_default
      The output should equal "volume_created=yes project_bound=no"
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

    It "seeds a caller-provided plan instead of running the planner (--plan)"
      check_seeded_plan() {
        local plan_fixture
        plan_fixture="$(mktemp)"
        printf '{"schema":"plan/v1"}\n' > "$plan_fixture"
        brik.local.docker.run_pipeline --plan "$plan_fixture" >/dev/null 2>&1
        local rc=$?
        rm -f "$plan_fixture"
        local planner_ran="no" seeded="no"
        grep -q -- "--out /work/.brik-logs/plan.json" "$MOCK_LOG" && planner_ran="yes"
        grep -q "cat > /work/.brik-logs/plan.json" "$MOCK_LOG" && seeded="yes"
        echo "rc=$rc planner=$planner_ran seeded=$seeded"
      }
      When call check_seeded_plan
      The output should equal "rc=0 planner=no seeded=yes"
    End

    It "rejects a missing --plan file"
      When call brik.local.docker.run_pipeline --plan /nonexistent/plan.json
      The status should equal 2
      The error should include "plan"
    End
  End

  # =========================================================================
  # brik.local.docker.run_single_stage (the `brik stage` dev verb)
  # =========================================================================
  Describe "brik.local.docker.run_single_stage"
    Include "$BRIK_HOME/shared-libs/local/scripts/local-wrapper.sh"
    Include "$BRIK_HOME/shared-libs/local/scripts/docker-runner.sh"
    Before 'setup_runner'
    After 'cleanup_runner'

    It "seeds, plans, bootstraps init, runs the one stage, destroys the volume"
      check_single() {
        brik.local.docker.run_single_stage build >/dev/null 2>&1
        local rc=$?
        local seeded="no" planned="no" init_ran="no" ran="no" others="no" removed="no"
        grep -q "chown -R" "$MOCK_LOG" && seeded="yes"
        grep -q -- "--out /work/.brik-logs/plan.json" "$MOCK_LOG" && planned="yes"
        # Init bootstraps the run: every CI job consumes its dotenv
        # (BRIK_CI_IMAGE, release metadata), the dev verb replays that.
        grep -q "container-stage.sh init" "$MOCK_LOG" && init_ran="yes"
        grep -q "container-stage.sh build" "$MOCK_LOG" && ran="yes"
        grep -q "container-stage.sh lint" "$MOCK_LOG" && others="yes"
        grep -q "volume rm" "$MOCK_LOG" && removed="yes"
        echo "rc=$rc seed=$seeded plan=$planned init=$init_ran stage=$ran others=$others removed=$removed"
      }
      When call check_single
      The output should equal "rc=0 seed=yes plan=yes init=yes stage=yes others=no removed=yes"
    End

    It "does not run init twice when init IS the requested stage"
      check_init_once() {
        brik.local.docker.run_single_stage init >/dev/null 2>&1
        grep -c "container-stage.sh init" "$MOCK_LOG"
      }
      When call check_init_once
      The output should equal "1"
    End

    It "feeds the stage's own opt-in flag to the planner (explicit ask)"
      check_opt_in() {
        brik.local.docker.run_single_stage deploy >/dev/null 2>&1
        grep -- "--out /work/.brik-logs/plan.json" "$MOCK_LOG"
      }
      When call check_opt_in
      The output should include "--with-deploy"
    End

    It "keeps the volume and extracts the logs when the stage fails"
      check_single_failure() {
        MOCK_DOCKER_FAIL_MATCH="container-stage.sh build" \
          brik.local.docker.run_single_stage build >/dev/null 2>&1
        local rc=$?
        local removed="no" extracted="no"
        grep -q "volume rm" "$MOCK_LOG" && removed="yes"
        grep "tar" "$MOCK_LOG" | grep -q "brik-logs" && extracted="yes"
        echo "rc=$rc removed=$removed extracted=$extracted"
      }
      When call check_single_failure
      The output should equal "rc=1 removed=no extracted=yes"
    End

    It "fails fast on an unknown stage, before any container"
      check_unknown() {
        brik.local.docker.run_single_stage bogus >/dev/null 2>&1
        local rc=$?
        local containers
        containers="$(grep -c "container-stage.sh" "$MOCK_LOG")" || containers=0
        echo "rc=$rc containers=$containers"
      }
      When call check_unknown
      The output should equal "rc=2 containers=0"
    End
  End

  # =========================================================================
  # Host-published endpoints (loopback /etc/hosts entries -> host-gateway)
  # =========================================================================
  Describe "host-published endpoint aliasing"
    Include "$BRIK_HOME/shared-libs/local/scripts/local-wrapper.sh"
    Include "$BRIK_HOME/shared-libs/local/scripts/docker-runner.sh"
    Before 'setup_runner'
    After 'cleanup_runner'

    make_lab_infra() {
      ALIAS_INFRA="$(mktemp -d)"
      mkdir -p "$ALIAS_INFRA/endpoints" "$ALIAS_INFRA/credentials"
      printf 'apiVersion: brik.dev/referential/v1\nkind: Referential\nprofile: p-lab\n' \
        > "$ALIAS_INFRA/referential.yml"
      cat > "$ALIAS_INFRA/endpoints/registry-release.yml" <<'YAML'
apiVersion: brik.dev/referential/v1
kind: Registry
name: registry-release
url: http://lab-registry.test:8082
YAML
      cat > "$ALIAS_INFRA/endpoints/git-host.yml" <<'YAML'
apiVersion: brik.dev/referential/v1
kind: GitHost
name: git-host
product: gitea
api_url: http://lab-git.test:3000
git_url: http://lab-git.test:3000
YAML
      cat > "$ALIAS_INFRA/endpoints/notify.yml" <<'YAML'
apiVersion: brik.dev/referential/v1
kind: Notification
name: notify
url: https://git.example.com
YAML
      ALIAS_HOSTS="$(mktemp)"
      printf '127.0.0.1 localhost lab-registry.test lab-git.test\n::1 localhost\n' > "$ALIAS_HOSTS"
    }
    cleanup_lab_infra() { rm -rf "$ALIAS_INFRA" "$ALIAS_HOSTS"; }

    It "aliases a loopback-published endpoint host to the host gateway"
      check_alias() {
        make_lab_infra
        BRIK_INFRA_DIR="$ALIAS_INFRA" BRIK_LOCAL_HOSTS_FILE="$ALIAS_HOSTS" \
          brik.local.docker.run_stage_container "123-9" "init" >/dev/null 2>&1
        local args
        args="$(mock.call_args "docker")"
        cleanup_lab_infra
        printf '%s\n' "$args"
      }
      When call check_alias
      The output should include "--add-host lab-registry.test:host-gateway"
      The output should include "--add-host lab-git.test:host-gateway"
    End

    It "leaves DNS-resolvable endpoint hosts alone"
      check_dns_host() {
        make_lab_infra
        BRIK_INFRA_DIR="$ALIAS_INFRA" BRIK_LOCAL_HOSTS_FILE="$ALIAS_HOSTS" \
          brik.local.docker.run_stage_container "123-9" "init" >/dev/null 2>&1
        local args
        args="$(mock.call_args "docker")"
        cleanup_lab_infra
        printf '%s\n' "$args"
      }
      When call check_dns_host
      The output should not include "git.example.com"
    End

    It "never aliases localhost itself"
      check_localhost() {
        make_lab_infra
        cat > "$ALIAS_INFRA/endpoints/registry-release.yml" <<'YAML'
apiVersion: brik.dev/referential/v1
kind: Registry
name: registry-release
url: http://localhost:5000
YAML
        BRIK_INFRA_DIR="$ALIAS_INFRA" BRIK_LOCAL_HOSTS_FILE="$ALIAS_HOSTS" \
          brik.local.docker.run_stage_container "123-9" "init" >/dev/null 2>&1
        local args
        args="$(mock.call_args "docker")"
        cleanup_lab_infra
        printf '%s\n' "$args"
      }
      When call check_localhost
      The output should not include "--add-host localhost"
    End
  End

  # =========================================================================
  # Keyless signing cross-validation (local has no OIDC issuer)
  # =========================================================================
  Describe "keyless signing cross-validation"
    Include "$BRIK_HOME/shared-libs/local/scripts/local-wrapper.sh"
    Include "$BRIK_HOME/shared-libs/local/scripts/docker-runner.sh"
    Before 'setup_runner'
    After 'cleanup_runner'

    make_infra() {
      INFRA_FIXTURE="$(mktemp -d)"
      mkdir -p "$INFRA_FIXTURE/endpoints"
      printf 'apiVersion: brik.dev/referential/v1\nkind: Referential\nprofile: p-lab\n' \
        > "$INFRA_FIXTURE/referential.yml"
      cat > "$INFRA_FIXTURE/endpoints/signing.yml" <<YAML
apiVersion: brik.dev/referential/v1
kind: Signing
name: signing
backend: $1
YAML
    }

    It "refuses the CI flow when the referential binds keyless signing"
      check_keyless() {
        make_infra keyless
        BRIK_INFRA_DIR="$INFRA_FIXTURE" brik.local.docker.run_pipeline >/dev/null 2>&1
        local rc=$?
        rm -rf "$INFRA_FIXTURE"
        local containers
        containers="$(grep -c "container-stage.sh" "$MOCK_LOG")" || containers=0
        echo "rc=$rc containers=$containers"
      }
      When call check_keyless
      The output should equal "rc=7 containers=0"
    End

    It "refuses a single stage the same way (no bypass)"
      check_keyless_stage() {
        make_infra keyless
        BRIK_INFRA_DIR="$INFRA_FIXTURE" brik.local.docker.run_single_stage build >/dev/null 2>&1
        local rc=$?
        rm -rf "$INFRA_FIXTURE"
        echo "rc=$rc"
      }
      When call check_keyless_stage
      The output should equal "rc=7"
    End

    It "accepts a key backend"
      check_key() {
        make_infra key
        BRIK_INFRA_DIR="$INFRA_FIXTURE" brik.local.docker.run_pipeline >/dev/null 2>&1
        local rc=$?
        rm -rf "$INFRA_FIXTURE"
        echo "rc=$rc"
      }
      When call check_key
      The output should equal "rc=0"
    End

    It "leaves the CD verb alone (verification is OIDC-free)"
      check_deploy_keyless() {
        make_infra keyless
        BRIK_INFRA_DIR="$INFRA_FIXTURE" brik.local.docker.run_deploy_container \
          --version v1.2.3 --environment staging >/dev/null 2>&1
        local rc=$?
        rm -rf "$INFRA_FIXTURE"
        echo "rc=$rc"
      }
      When call check_deploy_keyless
      The output should equal "rc=0"
    End
  End

  # =========================================================================
  # brik.local.docker.run_deploy_container (the CD verb container)
  # =========================================================================
  Describe "brik.local.docker.run_deploy_container"
    Include "$BRIK_HOME/shared-libs/local/scripts/local-wrapper.sh"
    Include "$BRIK_HOME/shared-libs/local/scripts/docker-runner.sh"
    Before 'setup_runner'
    After 'cleanup_runner'

    It "re-execs the verb in the deploy-class image on the seeded workspace"
      check_deploy() {
        brik.local.docker.run_deploy_container \
          --version v1.2.3 --environment staging >/dev/null 2>&1
        local rc=$?
        local seeded="no" verb="no" image="no" removed="no"
        grep -q "chown -R" "$MOCK_LOG" && seeded="yes"
        grep -q "bin/brik deploy --version v1.2.3 --environment staging" "$MOCK_LOG" && verb="yes"
        grep "bin/brik deploy" "$MOCK_LOG" | grep -q "brik-runner-deploy" && image="yes"
        grep -q "volume rm" "$MOCK_LOG" && removed="yes"
        echo "rc=$rc seed=$seeded verb=$verb image=$image removed=$removed"
      }
      When call check_deploy
      The output should equal "rc=0 seed=yes verb=yes image=yes removed=yes"
    End

    It "grants the engine socket per the deploy stage manifest"
      check_deploy_socket() {
        brik.local.docker.run_deploy_container \
          --version v1.2.3 --environment staging >/dev/null 2>&1
        grep "bin/brik deploy" "$MOCK_LOG"
      }
      When call check_deploy_socket
      The output should include "docker.sock"
    End

    It "maps an explicit --config into the volume"
      check_deploy_config() {
        brik.local.docker.run_deploy_container \
          --version v1.2.3 --environment staging \
          --config "$PROJECT_DIR/brik.yml" >/dev/null 2>&1
        grep "bin/brik deploy" "$MOCK_LOG"
      }
      When call check_deploy_config
      The output should include "--config /work/brik.yml"
    End

    It "keeps the volume and extracts the logs when the deploy fails"
      check_deploy_failure() {
        MOCK_DOCKER_FAIL_MATCH="bin/brik deploy" \
          brik.local.docker.run_deploy_container \
          --version v1.2.3 --environment staging >/dev/null 2>&1
        local rc=$?
        local removed="no" extracted="no"
        grep -q "volume rm" "$MOCK_LOG" && removed="yes"
        grep "tar" "$MOCK_LOG" | grep -q "brik-logs" && extracted="yes"
        echo "rc=$rc removed=$removed extracted=$extracted"
      }
      When call check_deploy_failure
      The output should equal "rc=1 removed=no extracted=yes"
    End
  End
End
