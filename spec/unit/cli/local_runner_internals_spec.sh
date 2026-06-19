#!/usr/bin/env bash
# local_runner_internals_spec.sh - in-process coverage of
# cli.local_runner.setup_docker_env and cli.local_runner.runtime.
#
# setup_docker_env is the host-side bootstrap of the containerized engine:
# it requires the local wrapper and the docker runner, sources both, then
# runs brik.local.setup_host with errexit disabled so the exit code
# propagates as a return value rather than aborting the shell.
#
# These tests redirect BRIK_HOME to a temp tree so the require_file gates,
# the sourcing path, and the rc-propagation branch are all exercised in
# process (kcov does not trace subprocess "$BRIK_BIN" calls).

Describe "cli/local_runner.sh - setup_docker_env + runtime"
  Include "$BRIK_PIPELINE_LIB/logging.sh"
  Include "$BRIK_PIPELINE_LIB/tools.sh"
  Include "$BRIK_CLI_LIB/local_runner.sh"

  # Build a fake BRIK_HOME with the two shell scripts setup_docker_env
  # requires. setup_host_rc decides what the sourced runner makes
  # brik.local.setup_host return.
  make_fake_home() {
    FAKE_HOME="$(mktemp -d)"
    mkdir -p "$FAKE_HOME/shared-libs/local/scripts"
  }

  write_wrapper() {
    printf '%s\n' '#!/usr/bin/env bash' \
      > "$FAKE_HOME/shared-libs/local/scripts/local-wrapper.sh"
  }

  # Runner that defines brik.local.setup_host returning the given code.
  write_runner() {
    {
      printf '%s\n' '#!/usr/bin/env bash'
      printf 'brik.local.setup_host() { return %s; }\n' "${1:-0}"
    } > "$FAKE_HOME/shared-libs/local/scripts/docker-runner.sh"
  }

  # Wrapper that ALSO defines brik.local.setup (for setup_env), returning
  # the given code.
  write_wrapper_with_setup() {
    {
      printf '%s\n' '#!/usr/bin/env bash'
      printf 'brik.local.setup() { return %s; }\n' "${1:-0}"
    } > "$FAKE_HOME/shared-libs/local/scripts/local-wrapper.sh"
  }

  cleanup() {
    [[ -n "${FAKE_HOME:-}" ]] && rm -rf "$FAKE_HOME"
    return 0
  }
  AfterEach 'cleanup'

  Describe "cli.local_runner.setup_docker_env"
    It "returns IO_FAILURE when the local wrapper is missing"
      make_fake_home  # no wrapper, no runner
      BeforeCall 'export BRIK_HOME="$FAKE_HOME"'
      When call cli.local_runner.setup_docker_env
      The status should eq "$BRIK_EXIT_IO_FAILURE"
      The stderr should include "required file not found"
    End

    It "returns IO_FAILURE when the docker runner is missing"
      make_fake_home
      write_wrapper  # wrapper present, runner absent
      BeforeCall 'export BRIK_HOME="$FAKE_HOME"'
      When call cli.local_runner.setup_docker_env
      The status should eq "$BRIK_EXIT_IO_FAILURE"
      The stderr should include "docker-runner.sh"
    End

    It "sources both files and propagates a successful setup_host"
      make_fake_home
      write_wrapper
      write_runner 0
      BeforeCall 'export BRIK_HOME="$FAKE_HOME"'
      When call cli.local_runner.setup_docker_env
      The status should eq 0
    End

    It "propagates a non-zero setup_host exit code without aborting"
      make_fake_home
      write_wrapper
      write_runner 7
      BeforeCall 'export BRIK_HOME="$FAKE_HOME"'
      When call cli.local_runner.setup_docker_env
      The status should eq 7
    End
  End

  Describe "cli.local_runner.setup_env"
    It "returns IO_FAILURE when the local wrapper is missing"
      make_fake_home  # no wrapper
      BeforeCall 'export BRIK_HOME="$FAKE_HOME"'
      When call cli.local_runner.setup_env
      The status should eq "$BRIK_EXIT_IO_FAILURE"
      The stderr should include "required file not found"
    End

    It "sources the wrapper and propagates a successful setup"
      make_fake_home
      write_wrapper_with_setup 0
      BeforeCall 'export BRIK_HOME="$FAKE_HOME"'
      When call cli.local_runner.setup_env
      The status should eq 0
    End

    It "propagates a non-zero setup exit code without aborting"
      make_fake_home
      write_wrapper_with_setup 4
      BeforeCall 'export BRIK_HOME="$FAKE_HOME"'
      When call cli.local_runner.setup_env
      The status should eq 4
    End
  End

  Describe "cli.local_runner.runtime"
    It "returns the command exit code with errexit disabled"
      false_cmd() { return 5; }
      When call cli.local_runner.runtime false_cmd
      The status should eq 5
    End

    It "returns 0 for a successful command"
      true_cmd() { return 0; }
      When call cli.local_runner.runtime true_cmd
      The status should eq 0
    End
  End
End
