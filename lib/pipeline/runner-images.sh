#!/usr/bin/env bash
# shellcheck disable=SC2034
# @module runner-images
# @description Resolve runner image references via the registry.
#
# As of v0.6 (chantier 20260518 D.2.3), language-stack image versions are
# declared in lib/registry/manifests/stacks/*.yml (spec.runner.{image,
# defaultVersion, versions}) and consumed via registry.stack.runner_image
# and registry.stack.runner_versions.
#
# The "base" runner image (alpine + bash + brik prereqs) is still resolved
# locally here as it is orthogonal to language stacks. It can move to a
# dedicated Runner kind manifest in a future iteration (post-D.6).
#
# Usage:
#   . runner-images.sh
#   runner.resolve_image node 22   # -> ghcr.io/getbrik/brik-runner-node:22
#   runner.resolve_image java      # -> ghcr.io/getbrik/brik-runner-java:21 (default)
#   runner.resolve_image base 3.23 # -> ghcr.io/getbrik/brik-runner-base:3.23

[[ -n "${_BRIK_RUNNER_IMAGES_LOADED:-}" ]] && return 0
_BRIK_RUNNER_IMAGES_LOADED=1

# shellcheck source=../registry/registry.sh
. "${BASH_SOURCE[0]%/*}/../registry/registry.sh"

BRIK_RUNNER_REGISTRY="${BRIK_RUNNER_REGISTRY:-ghcr.io/getbrik}"

# Base runner image (not a language stack). Kept inline until a Runner kind
# manifest is introduced.
BRIK_RUNNER_BASE_3_23="${BRIK_RUNNER_REGISTRY}/brik-runner-base:3.23"
BRIK_RUNNER_BASE_DEFAULT="3.23"

# Resolve a runner image URL from a stack id and optional version.
# Usage: runner.resolve_image <stack> [version]
# Returns: image URL on stdout, or BRIK_EXIT_FAILURE if not found.
runner.resolve_image() {
    local stack="$1"
    local version="${2:-}"

    # Base runner: resolved from local constants, honours BRIK_RUNNER_BASE_*.
    if [[ "$stack" == "base" ]]; then
        [[ -z "$version" ]] && version="$BRIK_RUNNER_BASE_DEFAULT"
        local safe_version="${version//./_}"
        local var_name="BRIK_RUNNER_BASE_${safe_version}"
        local image="${!var_name:-}"
        if [[ -n "$image" ]]; then
            printf '%s' "$image"
            return 0
        fi
        return "$BRIK_EXIT_FAILURE"
    fi

    # Language stacks: registry is the source of truth.
    registry.stack.exists "$stack" 2>/dev/null || return "$BRIK_EXIT_FAILURE"

    # Default to the manifest's spec.runner.defaultVersion when unspecified.
    if [[ -z "$version" ]]; then
        version="$(registry.stack.runner_default_version "$stack")"
    fi
    [[ -z "$version" ]] && return "$BRIK_EXIT_FAILURE"

    # Validate that the requested version is in spec.runner.versions.
    local v supported=0
    while IFS= read -r v; do
        [[ -z "$v" ]] && continue
        [[ "$v" == "$version" ]] && { supported=1; break; }
    done < <(registry.stack.runner_versions "$stack")
    [[ $supported -eq 1 ]] || return "$BRIK_EXIT_FAILURE"

    # Build the URL. The manifest stores the canonical image
    # (ghcr.io/getbrik/brik-runner-<stack>); we rebuild with the current
    # BRIK_RUNNER_REGISTRY to honour mirror overrides.
    local manifest_image image_basename
    manifest_image="$(registry.stack.runner_image "$stack")"
    image_basename="${manifest_image##*/}"
    printf '%s/%s:%s' "$BRIK_RUNNER_REGISTRY" "$image_basename" "$version"
}
