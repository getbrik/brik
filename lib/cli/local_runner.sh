#!/usr/bin/env bash
# @module cli.local_runner
# @description Shared local-execution helpers for "brik integrate" and
#   "brik stage". Sources the local wrapper and runs commands with errexit
#   disabled so failures propagate via return code rather than aborting.

# Guard against double-sourcing.
[[ -n "${_BRIK_MODULE_CLI_LOCAL_RUNNER_LOADED:-}" ]] && return 0
_BRIK_MODULE_CLI_LOCAL_RUNNER_LOADED=1

# cli.local_runner.default_infra - on a bare host with no referential
# configured, fall back to the bundled default instance (profile `p-local`,
# shipped at ${BRIK_HOME}/share/infra/p-local) so a plain CI run needs zero
# setup. An explicit BRIK_INFRA_DIR/BRIK_INFRA_REPO always wins, and a
# non-local host (orchestrated CI, or already inside a brik container) never
# falls back. Only the CI verbs (integrate/stage) call this; the CD verbs stay
# strict so a deploy to a declared-nothing infra fails closed with a clear error.
cli.local_runner.default_infra() {
    declare -f brik_host_local >/dev/null 2>&1 || brik.use cli.helpers
    if brik_host_local && [[ -z "${BRIK_INFRA_DIR:-}" && -z "${BRIK_INFRA_REPO:-}" ]]; then
        export BRIK_INFRA_DIR="${BRIK_HOME}/share/infra/p-local"
    fi
    return 0
}

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
