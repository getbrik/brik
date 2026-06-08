#!/usr/bin/env bash
# @module deployments._image_ref
# @description Single source for building and validating digest-pinned image
#   refs (DRY across the helm/gitops/compose/k8s/ssh targets).
#
# A digest-pinned ref content-addresses the exact image bytes
# (registry/app@sha256:<hex>) so a deployment can never drift to whatever a
# mutable tag points at later. This is the P0 require_digest primitive.

# Guard against double-sourcing.
[[ -n "${_BRIK_MODULE_DEPLOY_IMAGE_REF_LOADED:-}" ]] && return 0
_BRIK_MODULE_DEPLOY_IMAGE_REF_LOADED=1

# A digest-pinned ref: a lowercase repository path (a registry host:port is
# allowed, e.g. nexus.test:8082/app), '@', then a sha256 digest.
_BRIK_IMAGE_REF_PINNED_RE='^[a-z0-9._/:-]+@sha256:[0-9a-f]{64}$'

# deploy.image_ref.is_pinned - test whether a ref is digest-pinned.
# Usage: deploy.image_ref.is_pinned <ref>
# Returns: 0 if pinned, 1 otherwise.
deploy.image_ref.is_pinned() {
    [[ "$1" =~ $_BRIK_IMAGE_REF_PINNED_RE ]]
}

# deploy.image_ref.extract_digest - echo the sha256 digest of a ref.
# Used by the live read-back: a tag-based (non-pinned) running image yields
# "unknown" rather than a fabricated value, so drift stays visible.
# Usage: deploy.image_ref.extract_digest <ref>
# Output: "sha256:<hex>" or "unknown". Always returns 0.
deploy.image_ref.extract_digest() {
    if [[ "$1" =~ @(sha256:[0-9a-f]{64}) ]]; then
        printf '%s' "${BASH_REMATCH[1]}"
    else
        printf 'unknown'
    fi
}

# deploy.image_ref.pinned - build a digest-pinned ref from an image + digest.
# Any existing :tag or @digest on the image is stripped first; the digest is
# normalized to "sha256:<hex>" (a bare 64-hex string is accepted).
# Usage: deploy.image_ref.pinned <image> <digest>
# Output: "<repository>@sha256:<hex>" on stdout.
# Returns: 2 on empty/malformed input.
deploy.image_ref.pinned() {
    local image="$1" digest="$2"
    if [[ -z "$image" || -z "$digest" ]]; then
        log.error "deploy.image_ref.pinned: <image> and <digest> are required"
        return "$BRIK_EXIT_INVALID_INPUT"
    fi

    # Strip an existing @digest, then any :tag on the final path segment only
    # (so a registry host's :port, which precedes a '/', is preserved).
    local base="${image%@*}"
    local prefix seg
    if [[ "$base" == */* ]]; then
        prefix="${base%/*}/"
        seg="${base##*/}"
    else
        prefix=""
        seg="$base"
    fi
    seg="${seg%%:*}"
    base="${prefix}${seg}"

    # Normalize the digest: accept "sha256:<hex>" or a bare 64-hex string.
    [[ "$digest" == sha256:* ]] || digest="sha256:${digest}"

    local ref="${base}@${digest}"
    if ! deploy.image_ref.is_pinned "$ref"; then
        log.error "invalid digest-pinned ref built from image='${image}' digest='${digest}'"
        return "$BRIK_EXIT_INVALID_INPUT"
    fi

    printf '%s' "$ref"
}
