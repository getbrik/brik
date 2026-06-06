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

# Manifest media types accepted when resolving a tag: OCI image + index and
# the legacy Docker v2 manifest + list. A registry replies to a manifest
# request with the immutable digest in the Docker-Content-Digest header.
_BRIK_CHANNEL_ACCEPT='application/vnd.oci.image.index.v1+json,application/vnd.oci.image.manifest.v1+json,application/vnd.docker.distribution.manifest.list.v2+json,application/vnd.docker.distribution.manifest.v2+json'

# _channel._extract_digest - echo the Docker-Content-Digest header value from a
# raw HTTP header block (CRLF tolerated). Empty when the header is absent.
_channel._extract_digest() {
    printf '%s\n' "$1" \
        | tr -d '\r' \
        | grep -i '^Docker-Content-Digest:' \
        | tail -1 \
        | sed 's/^[^:]*:[[:space:]]*//; s/[[:space:]]*$//'
}

# _channel._is_401 - true when the header block carries a 401 status line.
_channel._is_401() {
    printf '%s\n' "$1" | tr -d '\r' | grep -qiE '^HTTP/[0-9.]+ +401'
}

# _channel._auth_param - extract a key="value" token from a WWW-Authenticate
# Bearer challenge line.
_channel._auth_param() {
    printf '%s' "$1" | sed -n "s/.*${2}=\"\([^\"]*\)\".*/\1/p"
}

# _channel._docker_auth - echo the base64 user:pass for <host> from the Docker
# config (the credential store that `docker login` writes and that the publish
# stage already populates). Empty/non-zero when no credential is stored.
_channel._docker_auth() {
    local host="$1"
    local cfg="${DOCKER_CONFIG:-${HOME}/.docker}/config.json"
    [[ -f "$cfg" ]] || return 1
    command -v jq >/dev/null 2>&1 || return 1
    local b64
    b64="$(jq -r --arg h "$host" '.auths[$h].auth // empty' "$cfg" 2>/dev/null)"
    [[ -n "$b64" ]] || return 1
    printf '%s' "$b64"
}

# _channel._basic_credential - echo the base64 user:pass to authenticate to
# <host>. Prefers the Docker credential store (what `docker login` writes);
# falls back to the BRIK_REGISTRY_USER/PASSWORD convention already used by the
# deploy targets (lib/deployments/compose.sh), gated on BRIK_REGISTRY_HOST so
# those creds never reach an unrelated registry. Non-zero when none is found.
_channel._basic_credential() {
    local host="$1" b64
    if b64="$(_channel._docker_auth "$host")"; then
        printf '%s' "$b64"
        return 0
    fi
    if [[ -n "${BRIK_REGISTRY_USER:-}" && -n "${BRIK_REGISTRY_PASSWORD:-}" \
          && ( -z "${BRIK_REGISTRY_HOST:-}" || "${BRIK_REGISTRY_HOST}" == "$host" ) ]]; then
        printf '%s:%s' "$BRIK_REGISTRY_USER" "$BRIK_REGISTRY_PASSWORD" | base64 | tr -d '\n'
        return 0
    fi
    return 1
}

# _channel._bearer_token - satisfy a Bearer challenge: GET the realm token
# endpoint (passing the stored Basic credential when present) and echo the
# token. Handles registries like ghcr / Docker Hub that gate manifest reads
# behind a token exchange.
_channel._bearer_token() {
    local headers="$1" basic="$2"
    local challenge
    challenge="$(printf '%s\n' "$headers" | tr -d '\r' | grep -i '^WWW-Authenticate:' | head -1)"
    [[ -n "$challenge" ]] || return 1
    local realm service scope
    realm="$(_channel._auth_param "$challenge" realm)"
    service="$(_channel._auth_param "$challenge" service)"
    scope="$(_channel._auth_param "$challenge" scope)"
    [[ -n "$realm" ]] || return 1
    local -a auth=()
    [[ -n "$basic" ]] && auth=(-H "Authorization: Basic ${basic}")
    local resp
    resp="$(curl -sS --max-time 30 "${auth[@]}" "${realm}?service=${service}&scope=${scope}" 2>/dev/null)" || return 1
    printf '%s' "$resp" | jq -r '.token // .access_token // empty' 2>/dev/null
}

# _channel._fetch_digest - resolve <name>:<version> on one scheme. Tries an
# anonymous (or Basic, when a credential is stored) manifest GET; on a 401
# Bearer challenge it exchanges a token and retries. Echoes the bare
# "sha256:<hex>" on success; non-zero otherwise.
_channel._fetch_digest() {
    local scheme="$1" host="$2" name="$3" version="$4"
    local url="${scheme}://${host}/v2/${name}/manifests/${version}"

    local basic
    basic="$(_channel._basic_credential "$host")" || basic=""
    local -a auth=()
    [[ -n "$basic" ]] && auth=(-H "Authorization: Basic ${basic}")

    local headers
    headers="$(curl -sS -L --max-time 30 -o /dev/null -D - -X GET \
        "${auth[@]}" -H "Accept: ${_BRIK_CHANNEL_ACCEPT}" "$url" 2>/dev/null)" || return 1

    if _channel._is_401 "$headers"; then
        local token
        token="$(_channel._bearer_token "$headers" "$basic")" || return 1
        [[ -n "$token" ]] || return 1
        headers="$(curl -sS -L --max-time 30 -o /dev/null -D - -X GET \
            -H "Authorization: Bearer ${token}" -H "Accept: ${_BRIK_CHANNEL_ACCEPT}" "$url" 2>/dev/null)" || return 1
    fi

    local digest
    digest="$(_channel._extract_digest "$headers")"
    [[ -n "$digest" ]] || return 1
    printf '%s' "$digest"
}

# _channel._registry_digest - resolve a tag to its sha256 digest via the OCI
# distribution API (curl). Isolated from the public entrypoint so the resolver
# strategy can evolve without touching it. The registry endpoint must be
# <host>/<repository>. HTTPS is tried first, then HTTP, so internal/air-gapped
# registries served over plain HTTP resolve without a flag. Echoes the bare
# "sha256:<hex>" on success.
# Returns: 3 if curl is not on PATH; 5 if the resolution fails.
_channel._registry_digest() {
    local registry="$1" version="$2"
    if ! command -v curl >/dev/null 2>&1; then
        log.error "no digest resolver available: 'curl' is not on PATH"
        return "$BRIK_EXIT_MISSING_DEP"
    fi

    local host="${registry%%/*}" name="${registry#*/}"
    if [[ "$host" == "$registry" || -z "$name" ]]; then
        log.error "channel registry '${registry}' is not of the form <host>/<repository>"
        return "$BRIK_EXIT_EXTERNAL_FAIL"
    fi

    local scheme digest
    for scheme in https http; do
        if digest="$(_channel._fetch_digest "$scheme" "$host" "$name" "$version")"; then
            printf '%s' "$digest"
            return 0
        fi
    done
    log.error "failed to resolve digest for ${registry}:${version}"
    return "$BRIK_EXIT_EXTERNAL_FAIL"
}

# channel.resolve_digest - resolve a version to a digest-pinned image ref
# within a channel's registry.
# Usage: channel.resolve_digest <version> <channel>
# Output: "<registry>@sha256:<hex>" on stdout.
# Returns: 2 invalid input; 7 channel/registry missing; 3 resolver missing
#          (curl not on PATH); 5 resolution failed or digest malformed.
channel.resolve_digest() {
    local version="$1" channel="$2"
    if [[ -z "$version" || -z "$channel" ]]; then
        log.error "channel.resolve_digest: <version> and <channel> are required"
        return "$BRIK_EXIT_INVALID_INPUT"
    fi

    local registry
    registry="$(channel.registry "$channel")" || return "$?"

    local digest
    digest="$(_channel._registry_digest "$registry" "$version")" || return "$?"

    if ! [[ "$digest" =~ $_BRIK_CHANNEL_DIGEST_RE ]]; then
        log.error "resolver returned a malformed digest for ${registry}:${version}: ${digest}"
        return "$BRIK_EXIT_EXTERNAL_FAIL"
    fi

    printf '%s@%s' "$registry" "$digest"
}
