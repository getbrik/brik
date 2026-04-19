#!/usr/bin/env bash
# shellcheck disable=SC2034
# @module runner-images
# @description Runner image registry and resolution.
#
# Source of truth in brik for available brik-runner Docker images.
# Maintained manually -- update when adding stacks/versions in brik-images.
#
# Usage:
#   . runner-images.sh
#   runner.resolve_image node 22   # -> ghcr.io/getbrik/brik-runner-node:22
#   runner.resolve_image java      # -> ghcr.io/getbrik/brik-runner-java:21 (default)

# Guard against double-sourcing
[[ -n "${_BRIK_RUNNER_IMAGES_LOADED:-}" ]] && return 0
_BRIK_RUNNER_IMAGES_LOADED=1

BRIK_RUNNER_REGISTRY="${BRIK_RUNNER_REGISTRY:-ghcr.io/getbrik}"

# ---------------------------------------------------------------------------
# Available images: BRIK_RUNNER_<STACK>_<VERSION>
# Used via indirect variable reference in runner.resolve_image()
# ---------------------------------------------------------------------------
BRIK_RUNNER_BASE_3_23="${BRIK_RUNNER_REGISTRY}/brik-runner-base:3.23"

BRIK_RUNNER_NODE_22="${BRIK_RUNNER_REGISTRY}/brik-runner-node:22"
BRIK_RUNNER_NODE_24="${BRIK_RUNNER_REGISTRY}/brik-runner-node:24"

BRIK_RUNNER_PYTHON_3_13="${BRIK_RUNNER_REGISTRY}/brik-runner-python:3.13"
BRIK_RUNNER_PYTHON_3_14="${BRIK_RUNNER_REGISTRY}/brik-runner-python:3.14"

BRIK_RUNNER_JAVA_21="${BRIK_RUNNER_REGISTRY}/brik-runner-java:21"
BRIK_RUNNER_JAVA_25="${BRIK_RUNNER_REGISTRY}/brik-runner-java:25"

BRIK_RUNNER_RUST_1="${BRIK_RUNNER_REGISTRY}/brik-runner-rust:1"

BRIK_RUNNER_DOTNET_9_0="${BRIK_RUNNER_REGISTRY}/brik-runner-dotnet:9.0"
BRIK_RUNNER_DOTNET_10_0="${BRIK_RUNNER_REGISTRY}/brik-runner-dotnet:10.0"

# ---------------------------------------------------------------------------
# Default version per stack
# ---------------------------------------------------------------------------
BRIK_RUNNER_BASE_DEFAULT="3.23"
BRIK_RUNNER_NODE_DEFAULT="22"
BRIK_RUNNER_PYTHON_DEFAULT="3.13"
BRIK_RUNNER_JAVA_DEFAULT="21"
BRIK_RUNNER_RUST_DEFAULT="1"
BRIK_RUNNER_DOTNET_DEFAULT="9.0"

# ---------------------------------------------------------------------------
# Resolve runner image URL from stack + version.
# Usage: runner.resolve_image <stack> [version]
# Returns: image URL on stdout, or exits 1 if not found.
# ---------------------------------------------------------------------------
runner.resolve_image() {
    local stack="$1"
    local version="${2:-}"

    # Use default version if not specified
    if [[ -z "$version" ]]; then
        local default_var="BRIK_RUNNER_${stack^^}_DEFAULT"
        version="${!default_var:-}"
    fi

    [[ -z "$version" ]] && return "$BRIK_EXIT_FAILURE"

    # Normalize version for variable name (dots -> underscores)
    local safe_version="${version//./_}"
    local var_name="BRIK_RUNNER_${stack^^}_${safe_version}"
    local image="${!var_name:-}"

    [[ -n "$image" ]] && printf '%s' "$image" && return 0
    return "$BRIK_EXIT_FAILURE"
}
