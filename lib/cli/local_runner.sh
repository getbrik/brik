#!/usr/bin/env bash
# @module cli.local_runner
# @description Shared local-execution helpers for "brik integrate" and
#   "brik stage". Sources the local wrapper and runs commands with errexit
#   disabled so failures propagate via return code rather than aborting.

# Guard against double-sourcing.
[[ -n "${_BRIK_MODULE_CLI_LOCAL_RUNNER_LOADED:-}" ]] && return 0
_BRIK_MODULE_CLI_LOCAL_RUNNER_LOADED=1

# cli.local_runner.setup_env - source the local wrapper and run
# brik.local.setup with set +e so failures propagate via return code rather
# than aborting the shell.
cli.local_runner.setup_env() {
    local wrapper="${BRIK_HOME}/shared-libs/local/scripts/local-wrapper.sh"
    pipeline.require_file "${wrapper}" || return "$?"
    # shellcheck source=/dev/null
    . "${wrapper}"

    local rc
    set +e
    brik.local.setup
    rc=$?
    set -e
    return "$rc"
}

# cli.local_runner.setup_docker_env - host-side bootstrap of the
# containerized engine: the local wrapper (runtime + registry, no config
# parsing -- that happens inside the stage containers) plus the docker
# runner module.
cli.local_runner.setup_docker_env() {
    local wrapper="${BRIK_HOME}/shared-libs/local/scripts/local-wrapper.sh"
    local runner="${BRIK_HOME}/shared-libs/local/scripts/docker-runner.sh"
    pipeline.require_file "${wrapper}" || return "$?"
    pipeline.require_file "${runner}" || return "$?"
    # shellcheck source=/dev/null
    . "${wrapper}"
    # shellcheck source=/dev/null
    . "${runner}"

    local rc
    set +e
    brik.local.setup_host
    rc=$?
    set -e
    return "$rc"
}

# cli.local_runner.runtime - run a command with set -e disabled; return its
# exit code.
cli.local_runner.runtime() {
    local rc
    set +e
    "$@"
    rc=$?
    set -e
    return "$rc"
}
