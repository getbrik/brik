#!/usr/bin/env bash
# @module stacks._detect
# @description Stack detection from workspace markers and framework names.
# As of v0.6 (chantier 20260518 D.2.1), the detection rules are read from
# the registry (lib/registry/manifests/stacks/*.yml) rather than hardcoded.
# Public API and behavior are strictly identical to v0.5.0:
#   stacks.detect <workspace>           -> prints stack id, rc=0 on match,
#                                          BRIK_EXIT_FAILURE + log.error otherwise.
#   stacks.detect_from_framework <name> -> prints stack id, rc=0 on match,
#                                          BRIK_EXIT_FAILURE silently otherwise.

# Guard against double-sourcing.
[[ -n "${_BRIK_MODULE_STACKS_DETECT_LOADED:-}" ]] && return 0
_BRIK_MODULE_STACKS_DETECT_LOADED=1

# Source the registry directly via path resolution. Avoids depending on
# brik.use being already loaded (the spec context includes _detect.sh
# without first loading the runtime loader).
# shellcheck source=../registry/registry.sh
. "${BASH_SOURCE[0]%/*}/../registry/registry.sh"

# Detect the project stack from marker files in the workspace.
stacks.detect() {
    local workspace="$1"
    local stack
    if stack="$(registry.stack.detect "$workspace")"; then
        printf '%s' "$stack"
        return 0
    fi
    log.error "cannot detect stack in workspace: $workspace"
    return "$BRIK_EXIT_FAILURE"
}

# Map a framework name (jest, pytest, ...) to its owning stack.
stacks.detect_from_framework() {
    local framework="$1"
    local stack
    if stack="$(registry.stack.detect_from_framework "$framework")"; then
        printf '%s' "$stack"
        return 0
    fi
    return "$BRIK_EXIT_FAILURE"
}
