#!/usr/bin/env bash
# @module container-stage
# @description Entry point executed INSIDE a stage container by
#   docker-runner.sh. Replays the CI job contract:
#     1. plan gate -- a stage the plan marks skip exits 0 (the gate records
#        the not-applicable fragment itself); a planner error fails the run
#     2. local wrapper bootstrap + single-stage execution, with report
#        fragments on so notify can aggregate them across containers
#
# Env contract injected by docker-runner.sh: BRIK_HOME (read-only mount),
# BRIK_WORKSPACE / BRIK_PROJECT_DIR (the run volume), BRIK_CONFIG_FILE,
# BRIK_LOG_DIR, BRIK_PLAN_FILE, HOME (writable, on the volume).
#
# Usage: bash container-stage.sh <stage_id>

_brik_container_stage="${1:?container-stage: stage id required}"

# Plan gate, cheap and first: a skip never pays the bootstrap. rc 1 is the
# skip decision; anything above 1 is a planner error and fails the job.
if "${BRIK_HOME}/bin/brik" plan gate "${_brik_container_stage}"; then
    echo "[brik] ${_brik_container_stage}: runs (per plan)"
else
    _brik_container_gate_rc=$?
    if [[ "${_brik_container_gate_rc}" -eq 1 ]]; then
        echo "[brik] [SKIP] ${_brik_container_stage}: per plan"
        exit 0
    fi
    echo "[brik] ${_brik_container_stage}: plan gate error (rc=${_brik_container_gate_rc})" >&2
    exit "${_brik_container_gate_rc}"
fi

# shellcheck source=/dev/null
. "${BRIK_HOME}/shared-libs/local/scripts/local-wrapper.sh"

brik.local.setup || exit "$?"
brik.local.run_stage "${_brik_container_stage}"
