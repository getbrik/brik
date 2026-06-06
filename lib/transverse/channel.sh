#!/usr/bin/env bash
# @module transverse.channel
# @description Artifact-channel resolution for the CD flow.
#
# A "channel" (artifacts.channels.<name> in brik.yml) is a named registry
# endpoint an artifact lives in (e.g. candidate, release). The CD flow resolves
# a version to a digest-pinned image ref WITHIN the channel an environment
# accepts, so a deployment pins the exact bytes content-addressed by the
# registry rather than a mutable tag.
#
# This is intentionally NOT in transverse/artifacts.sh: that module owns the
# local build-artifact staging ontology (brik.artifacts.*); channels are a
# distinct, registry-facing notion (one ontology per module).

# Guard against double-sourcing.
[[ -n "${_BRIK_MODULE_TRANSVERSE_CHANNEL_LOADED:-}" ]] && return 0
_BRIK_MODULE_TRANSVERSE_CHANNEL_LOADED=1

# A manifest digest: the sha256 algorithm tag plus 64 lowercase hex chars.
_BRIK_CHANNEL_DIGEST_RE='^sha256:[0-9a-f]{64}$'

# channel.registry - echo the registry endpoint declared for a channel.
# Usage: channel.registry <channel>
# Returns: 0 + endpoint on stdout; 2 if no channel given; 7 if the channel is
#          not declared (or has no registry) in brik.yml.
channel.registry() {
    local channel="$1"
    if [[ -z "$channel" ]]; then
        log.error "channel.registry: a channel name is required"
        return "$BRIK_EXIT_INVALID_INPUT"
    fi

    brik.use transverse.config

    local registry
    registry="$(config.get ".artifacts.channels.${channel}.registry" '' 2>/dev/null)" || registry=""
    if [[ -z "$registry" ]]; then
        log.error "channel '${channel}' has no registry configured under artifacts.channels"
        return "$BRIK_EXIT_CONFIG_ERROR"
    fi

    printf '%s' "$registry"
}

# _channel._crane_digest - resolve a tag to its sha256 digest via crane.
# Isolated so the resolver can grow a registry-API fallback later without
# touching the public entrypoint. Echoes the bare "sha256:<hex>" on success.
# Returns: 3 if crane is not on PATH; 5 if the resolution fails.
_channel._crane_digest() {
    local registry="$1" version="$2"
    if ! command -v crane >/dev/null 2>&1; then
        log.error "no digest resolver available: 'crane' is not on PATH"
        return "$BRIK_EXIT_MISSING_DEP"
    fi

    local digest
    digest="$(crane digest "${registry}:${version}" 2>/dev/null)" || {
        log.error "failed to resolve digest for ${registry}:${version}"
        return "$BRIK_EXIT_EXTERNAL_FAIL"
    }
    printf '%s' "$digest"
}

# channel.resolve_digest - resolve a version to a digest-pinned image ref
# within a channel's registry.
# Usage: channel.resolve_digest <version> <channel>
# Output: "<registry>@sha256:<hex>" on stdout.
# Returns: 2 invalid input; 7 channel/registry missing; 3 resolver missing;
#          5 resolution failed or digest malformed.
channel.resolve_digest() {
    local version="$1" channel="$2"
    if [[ -z "$version" || -z "$channel" ]]; then
        log.error "channel.resolve_digest: <version> and <channel> are required"
        return "$BRIK_EXIT_INVALID_INPUT"
    fi

    local registry
    registry="$(channel.registry "$channel")" || return "$?"

    local digest
    digest="$(_channel._crane_digest "$registry" "$version")" || return "$?"

    if ! [[ "$digest" =~ $_BRIK_CHANNEL_DIGEST_RE ]]; then
        log.error "resolver returned a malformed digest for ${registry}:${version}: ${digest}"
        return "$BRIK_EXIT_EXTERNAL_FAIL"
    fi

    printf '%s@%s' "$registry" "$digest"
}
