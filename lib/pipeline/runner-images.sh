#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# @module runner-images
# @description Resolve runner image references via the registry.
#
# As of v0.6 (chantier 20260518 D.2.3), language-stack image versions are
# declared in lib/registry/manifests/stacks/*.yml (spec.runner.{image,
# defaultVersion, versions}) and consumed via registry.stack.runner_image
# and registry.stack.runner_versions.
#
# The base runner image (alpine + bash + brik prereqs) is orthogonal to
# language stacks. Its canonical mapping lives in lib/registry/runner_classes.yml
# (the 'base' runner_class), consumed on the normal path via
# registry.runner_class.image. This module only owns the LAST-RESORT base
# fallback (runner.base_image), used before init's dotenv exists or when the
# registry is unavailable. Parity of that fallback tag with runner_classes.yml
# is enforced by spec/unit/pipeline/runner_images_spec.sh.
#
# Usage:
#   . runner-images.sh
#   runner.resolve_image node 22       # -> ghcr.io/getbrik/brik-runner-node:22
#   runner.resolve_image java          # -> ghcr.io/getbrik/brik-runner-java:21 (default)
#   runner.base_image                  # -> ghcr.io/getbrik/brik-runner-base:latest
#   runner.resolve_stack_or_base node  # -> stack image, or base when unknown/auto
#
[[ -n "${_BRIK_RUNNER_IMAGES_LOADED:-}" ]] && return 0
_BRIK_RUNNER_IMAGES_LOADED=1

# shellcheck source=../registry/registry.sh
. "${BASH_SOURCE[0]%/*}/../registry/registry.sh"

BRIK_RUNNER_REGISTRY="${BRIK_RUNNER_REGISTRY:-ghcr.io/getbrik}"

# Single source of truth for the base runner image fallback tag. Mirrors the
# 'base' runner_class tag in lib/registry/runner_classes.yml -- the registry is
# the canonical map on the normal path; this constant is only the fallback.
# Drift is caught by spec/unit/pipeline/runner_images_spec.sh.
BRIK_RUNNER_BASE_DEFAULT_TAG="latest"

# Print the base runner image reference. The ONLY literal site for the base
# image across the Bash runtime: every fallback routes through here so the
# registry prefix and tag stay consistent.
# Usage: runner.base_image
runner.base_image() {
    printf '%s/brik-runner-base:%s' "$BRIK_RUNNER_REGISTRY" "$BRIK_RUNNER_BASE_DEFAULT_TAG"
}

# Resolve a LANGUAGE-STACK runner image URL from a stack id and optional
# version. The base image is not a language stack -- use runner.base_image.
# Usage: runner.resolve_image <stack> [version]
# Returns: image URL on stdout, or BRIK_EXIT_FAILURE if the stack/version is
# unknown.
runner.resolve_image() {
    local stack="$1"
    local version="${2:-}"

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

# Resolve the stack image, falling back to the base image when the stack is
# unset/auto or unknown. Single shared "stack-or-base" resolver consumed by
# init (to compute BRIK_CI_IMAGE) and config.export_runner_vars (to compute
# BRIK_RUNNER_IMAGE), so the policy and the base literal live in one place.
# Usage: runner.resolve_stack_or_base <stack> [version]
runner.resolve_stack_or_base() {
    local stack="${1:-auto}"
    local version="${2:-}"

    if [[ "$stack" == "auto" || -z "$stack" ]]; then
        runner.base_image
        return 0
    fi

    local image
    if image="$(runner.resolve_image "$stack" "$version" 2>/dev/null)"; then
        printf '%s' "$image"
        return 0
    fi

    # Unknown stack/version: surface the misconfiguration when logging is
    # available, then degrade to the base image.
    if declare -f log.warn >/dev/null 2>&1; then
        log.warn "no runner image for stack '$stack' version '${version:-default}', using base"
    fi
    runner.base_image
}
