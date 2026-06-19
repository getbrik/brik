#!/usr/bin/env bash
# stage_internals_spec.sh - in-process coverage of cli.stage.run.
#
# `brik stage <name>` parses options then dispatches to the local runner.
# The integration spec (stage_integration_spec.sh) drives the verb through
# "$BRIK_BIN", which kcov cannot trace (subprocess). These examples Include
# stage.sh and call cli.stage.run directly so the option-parsing, error,
# help, and host-dispatch branches are exercised in process.
#
# Targets the previously-uncovered branches:
#   - empty args / unknown option  -> BRIK_EXIT_INVALID_INPUT
#   - -h/--help (first arg and mid-loop)
#   - --platform (sets BRIK_LOCAL_PLATFORM) and its missing-value guard
#   - --bind-mount (sets BRIK_LOCAL_BIND_MOUNT)
#   - brik_host_local true  -> containerized dispatch (default_infra +
#     setup_docker_env + runtime)
#   - brik_host_local false -> in-process dispatch (setup_env + runtime)

Describe "cli/stage.sh - cli.stage.run internals"
  Include "$BRIK_PIPELINE_LIB/logging.sh"
  Include "$BRIK_PIPELINE_LIB/tools.sh"
  Include "$BRIK_PIPELINE_LIB/loader.sh"
  Include "$BRIK_CLI_LIB/helpers.sh"
  Include "$BRIK_CLI_LIB/local_runner.sh"
  Include "$BRIK_CLI_LIB/stage.sh"

  # Stub the local_runner dispatch so the verb's branches run without a
  # real docker engine or wrapper. Each stub records its invocation so the
  # dispatch path can be asserted. The guards above ensure brik.use inside
  # cli.stage.run is a no-op (modules already loaded).
  stub_runner() {
    cli.local_runner.default_infra()    { printf 'default_infra\n'; }
    cli.local_runner.setup_docker_env() { printf 'setup_docker_env\n'; return 0; }
    cli.local_runner.setup_env()        { printf 'setup_env\n'; return 0; }
    # runtime <cmd> <args...> -- echo the dispatched command instead of running it.
    cli.local_runner.runtime()          { printf 'runtime: %s\n' "$*"; return 0; }
  }

  setup_workspace() {
    WORKSPACE="$(mktemp -d)"
    export BRIK_LOG_DIR="${WORKSPACE}/.brik-logs"
    printf 'version: 1\nproject:\n  name: cli-test\n  stack: node\n' \
      > "${WORKSPACE}/brik.yml"
    stub_runner
  }
  cleanup_workspace() {
    rm -rf "$WORKSPACE"
    unset BRIK_LOG_DIR BRIK_LOCAL_PLATFORM BRIK_LOCAL_BIND_MOUNT BRIK_DRY_RUN
  }
  BeforeEach 'setup_workspace'
  AfterEach 'cleanup_workspace'

  Describe "argument validation"
    It "requires a stage name when called with no args"
      When call cli.stage.run
      The status should eq "$BRIK_EXIT_INVALID_INPUT"
      The stderr should include "requires a stage name"
    End

    It "rejects an unknown option"
      When call cli.stage.run build --workspace "$WORKSPACE" --bogus
      The status should eq "$BRIK_EXIT_INVALID_INPUT"
      The stderr should include "unknown option: --bogus"
      The stderr should include "Run 'brik help' for usage."
    End

    It "rejects --platform with no value"
      When call cli.stage.run build --workspace "$WORKSPACE" --platform
      The status should eq "$BRIK_EXIT_INVALID_INPUT"
      The stderr should include "--platform requires a value"
    End
  End

  Describe "help"
    It "prints verb help when -h is the first argument"
      When call cli.stage.run -h
      The status should eq 0
      The output should include "stage"
    End

    It "prints verb help when --help appears mid-loop"
      When call cli.stage.run build --workspace "$WORKSPACE" --help
      The status should eq 0
      The output should include "stage"
    End
  End

  Describe "containerized dispatch (brik_host_local true)"
    # No orchestrator signal and not inside a brik container -> the verb
    # drives the containerized engine: default_infra, setup_docker_env, then
    # runtime brik.local.docker.run_single_stage <stage>.
    host_local() {
      unset GITLAB_CI JENKINS_URL BRIK_LOCAL_CONTAINER
    }
    BeforeCall 'host_local'

    It "runs default_infra + setup_docker_env + the single-stage runtime"
      When call cli.stage.run build --workspace "$WORKSPACE"
      The status should eq 0
      The output should include "default_infra"
      The output should include "setup_docker_env"
      The output should include "runtime: brik.local.docker.run_single_stage build"
    End

    It "accepts --platform and --bind-mount and exports them"
      When call cli.stage.run build --workspace "$WORKSPACE" --platform linux/arm64 --bind-mount
      The status should eq 0
      The variable BRIK_LOCAL_PLATFORM should eq "linux/arm64"
      The variable BRIK_LOCAL_BIND_MOUNT should eq 1
      The output should include "runtime: brik.local.docker.run_single_stage build"
    End

    It "propagates a non-zero setup_docker_env exit code"
      cli.local_runner.setup_docker_env() { return 7; }
      When call cli.stage.run build --workspace "$WORKSPACE"
      The status should eq 7
      The output should include "default_infra"
    End
  End

  Describe "in-process dispatch (brik_host_local false)"
    # Inside a brik container the caller IS the execution environment, so the
    # verb runs in process: setup_env, then runtime brik.local.run_stage.
    in_container() {
      unset GITLAB_CI JENKINS_URL
      export BRIK_LOCAL_CONTAINER=1
    }
    BeforeCall 'in_container'
    After 'unset BRIK_LOCAL_CONTAINER'

    It "runs setup_env + the in-process run_stage runtime"
      When call cli.stage.run test --workspace "$WORKSPACE" --config "${WORKSPACE}/brik.yml"
      The status should eq 0
      The output should include "setup_env"
      The output should include "runtime: brik.local.run_stage test"
      The output should not include "setup_docker_env"
    End

    It "activates dry-run when --dry-run is passed"
      When call cli.stage.run build --workspace "$WORKSPACE" --dry-run
      The status should eq 0
      The variable BRIK_DRY_RUN should eq "true"
      The output should include "runtime: brik.local.run_stage build"
    End

    It "propagates a non-zero setup_env exit code"
      cli.local_runner.setup_env() { return 5; }
      When call cli.stage.run build --workspace "$WORKSPACE"
      The status should eq 5
    End
  End
End
