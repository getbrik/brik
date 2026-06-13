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

# channel.scoped_docker_config - materialize an ephemeral Docker config
# directory carrying the registry auth for each <host>, so cosign and oras
# authenticate through the credential store (DOCKER_CONFIG) instead of a
# --password flag visible in the process table on a shared host. The current
# config.json is copied first so a prior `docker login` (inline auth, credsStore
# or credHelpers) keeps working; the BRIK_REGISTRY_USER/PASSWORD fallback is then
# merged inline for the hosts it is scoped to. Echoes the directory; the caller
# runs the tool with DOCKER_CONFIG set to it and removes it afterwards.
# Usage: dir="$(channel.scoped_docker_config <host>...)"
channel.scoped_docker_config() {
    local dir src host
    dir="$(mktemp -d)" || return "$BRIK_EXIT_IO_FAILURE"
    src="${DOCKER_CONFIG:-${HOME}/.docker}/config.json"
    if [[ -f "$src" ]]; then
        cp "$src" "${dir}/config.json" 2>/dev/null || printf '{}' >"${dir}/config.json"
    else
        printf '{}' >"${dir}/config.json"
    fi
    for host in "$@"; do
        if [[ -n "${BRIK_REGISTRY_USER:-}" && -n "${BRIK_REGISTRY_PASSWORD:-}" \
              && ( -z "${BRIK_REGISTRY_HOST:-}" || "${BRIK_REGISTRY_HOST}" == "$host" ) ]]; then
            local b64 merged
            b64="$(printf '%s:%s' "$BRIK_REGISTRY_USER" "$BRIK_REGISTRY_PASSWORD" | base64 | tr -d '\n')"
            merged="$(jq --arg h "$host" --arg a "$b64" \
                '.auths = (.auths // {}) | .auths[$h].auth = $a' "${dir}/config.json" 2>/dev/null)" \
                && printf '%s' "$merged" >"${dir}/config.json"
        fi
    done
    printf '%s' "$dir"
}

# _channel._bearer_token - satisfy a Bearer challenge: GET the realm token
# endpoint (passing the stored Basic credential when present) and echo the
# token. Handles registries like ghcr / Docker Hub that gate manifest reads
# behind a token exchange.
_channel._bearer_token() {
    local headers="$1" basic="$2" ca="${3:-}"
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
    [[ -n "$ca" ]] && auth+=(--cacert "$ca")
    local resp
    resp="$(curl -sS --max-time 30 "${auth[@]}" "${realm}?service=${service}&scope=${scope}" 2>/dev/null)" || return 1
    printf '%s' "$resp" | jq -r '.token // .access_token // empty' 2>/dev/null
}

# _channel._fetch_digest - resolve <name>:<version> on one scheme. Tries an
# anonymous (or Basic, when a credential is stored) manifest GET; on a 401
# Bearer challenge it exchanges a token and retries. An optional CA bundle
# (custom-ca trust) pins the TLS verification of every request of the
# resolution, token exchange included: in a private-PKI posture the auth
# service lives in the same PKI as the registry. Echoes the bare
# "sha256:<hex>" on success; non-zero otherwise.
_channel._fetch_digest() {
    local scheme="$1" host="$2" name="$3" version="$4" ca="${5:-}"
    local url="${scheme}://${host}/v2/${name}/manifests/${version}"

    local -a tls=()
    [[ -n "$ca" ]] && tls=(--cacert "$ca")

    local basic
    basic="$(_channel._basic_credential "$host")" || basic=""
    local -a auth=()
    [[ -n "$basic" ]] && auth=(-H "Authorization: Basic ${basic}")

    local headers
    headers="$(curl -sS -L --max-time 30 -o /dev/null -D - -X GET \
        "${tls[@]}" "${auth[@]}" -H "Accept: ${_BRIK_CHANNEL_ACCEPT}" "$url" 2>/dev/null)" || return 1

    if _channel._is_401 "$headers"; then
        local token
        token="$(_channel._bearer_token "$headers" "$basic" "$ca")" || return 1
        [[ -n "$token" ]] || return 1
        headers="$(curl -sS -L --max-time 30 -o /dev/null -D - -X GET \
            "${tls[@]}" -H "Authorization: Bearer ${token}" -H "Accept: ${_BRIK_CHANNEL_ACCEPT}" "$url" 2>/dev/null)" || return 1
    fi

    local digest
    digest="$(_channel._extract_digest "$headers")"
    [[ -n "$digest" ]] || return 1
    printf '%s' "$digest"
}

# _channel._registry_digest - resolve a tag to its sha256 digest via the OCI
# distribution API (curl). Isolated from the public entrypoint so the resolver
# strategy can evolve without touching it. The registry endpoint must be
# <host>/<repository>. The URL scheme comes from the Registry endpoint the
# referential declares for the host: http:// is a declaration, never a
# fallback, and an undeclared host fails closed. Echoes the bare
# "sha256:<hex>" on success.
# Returns: 3 if curl is not on PATH; 7 when the host is not declared in the
#          referential; 4 when no referential is configured; 5 if the
#          resolution fails.
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

    brik.use transverse.infra
    local endpoint url scheme ca
    endpoint="$(infra.registry_for "$host")" || return "$?"
    url="$(printf '%s' "$endpoint" | jq -r '.url')"
    scheme="${url%%://*}"
    ca="$(infra.tls_ca "$endpoint")" || return "$?"

    local digest
    if ! digest="$(_channel._fetch_digest "$scheme" "$host" "$name" "$version" "$ca")"; then
        log.error "failed to resolve digest for ${registry}:${version} (over ${scheme})"
        return "$BRIK_EXIT_EXTERNAL_FAIL"
    fi
    printf '%s' "$digest"
}

# _channel._oras_side_args - append the oras transport flags one side (from|to)
# of a copy requires, derived from the Registry endpoint the referential declares
# for the host: a declared http:// URL maps to --<side>-plain-http, a
# declared tls.trust: insecure to --<side>-insecure, and an undeclared host
# fails closed. Registry credentials are NOT passed here -- they travel through
# the scoped DOCKER_CONFIG (channel.scoped_docker_config) so a password never
# lands in the process table.
# Usage: _channel._oras_side_args <array_name> <from|to> <host>
_channel._oras_side_args() {
    local -n _oargv="$1"
    local _side="$2" _host="$3"

    brik.use transverse.infra
    local _endpoint _url _ca
    _endpoint="$(infra.registry_for "$_host")" || return "$?"
    _url="$(printf '%s' "$_endpoint" | jq -r '.url')"
    _ca="$(infra.tls_ca "$_endpoint")" || return "$?"
    if [[ "$_url" == http://* ]]; then
        _oargv+=("--${_side}-plain-http")
    elif [[ "$(printf '%s' "$_endpoint" | jq -r '.tls.trust')" == "insecure" ]]; then
        _oargv+=("--${_side}-insecure")
    elif [[ -n "$_ca" ]]; then
        _oargv+=("--${_side}-ca-file" "$_ca")
    fi
    return 0
}

# channel.copy_with_referrers - promote a version from one channel to
# another, carrying its evidence graph along, and prove the move.
#
# The image is copied digest-pinned with its OCI referrers (signed SBOM and
# provenance attestations) via `oras cp -r` -- the only transport proven to
# carry cosign v3 bundles across registries (spike H13: cosign copy recreates
# an EMPTY referrers index at the destination, silently dropping the
# evidence). The copy is then proven fail-closed on the destination:
#   1. the version must resolve to the SAME digest as the source;
#   2. attest.verify must succeed against the profile's trust material.
# An artifact promoted without its verifiable evidence is a failure, never a
# warning.
#
# The destination channel is immutable (release semantics): a version it
# already holds at a DIFFERENT digest is an explicit failure, never an
# overwrite; the SAME digest makes the copy an idempotent no-op whose
# evidence is still verified.
#
# Usage: channel.copy_with_referrers <version> <from> <to>
#                                    [--identity <re>] [--issuer <re>]
# --identity/--issuer are forwarded to the keyless verification (required by
# attest.verify in keyless mode).
# Output: "<dst_registry>@sha256:<hex>" on stdout.
# Returns: 2 invalid input; 3 oras missing; 7 channel/registry undeclared;
#          10 destination holds the version at a different digest;
#          5 copy, digest proof or evidence verification failed.
channel.copy_with_referrers() {
    local version="${1:-}" from="${2:-}" to="${3:-}"
    shift $(( $# < 3 ? $# : 3 ))

    local identity="" issuer=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --identity) identity="$2"; shift 2 ;;
            --issuer)   issuer="$2";   shift 2 ;;
            *) log.error "channel.copy_with_referrers: unknown option: $1"
               return "$BRIK_EXIT_INVALID_INPUT" ;;
        esac
    done

    if [[ -z "$version" || -z "$from" || -z "$to" ]]; then
        log.error "channel.copy_with_referrers: <version>, <from> and <to> are required"
        return "$BRIK_EXIT_INVALID_INPUT"
    fi

    pipeline.require_tool oras || return "$BRIK_EXIT_MISSING_DEP"

    local from_registry to_registry
    from_registry="$(channel.registry "$from")" || return "$?"
    to_registry="$(channel.registry "$to")" || return "$?"

    local src_pinned digest
    src_pinned="$(channel.resolve_digest "$version" "$from")" || return "$?"
    digest="${src_pinned##*@}"

    # Destination immutability, checked before any byte moves: a version the
    # destination already holds at another digest is a refusal, the same
    # digest an idempotent no-op. An absent version (or an unreachable
    # destination -- a real outage surfaces at the copy itself) proceeds.
    local pre_pinned pre_digest=""
    if pre_pinned="$(channel.resolve_digest "$version" "$to" 2>/dev/null)"; then
        pre_digest="${pre_pinned##*@}"
        if [[ "$pre_digest" != "$digest" ]]; then
            log.error "channel '${to}' is immutable: it already holds ${version} at ${pre_digest}, refusing to overwrite with ${digest}"
            return "$BRIK_EXIT_CHECK_FAILED"
        fi
        log.info "channel '${to}' already holds ${version} at ${digest}: copy is a no-op"
    fi

    if [[ -z "$pre_digest" ]]; then
        local -a args=(cp -r)
        _channel._oras_side_args args from "${from_registry%%/*}" || return "$?"
        _channel._oras_side_args args to "${to_registry%%/*}" || return "$?"

        # Credentials travel through a scoped Docker config, never the argv.
        local _dcfg
        _dcfg="$(channel.scoped_docker_config "${from_registry%%/*}" "${to_registry%%/*}")" \
            || return "$?"

        log.info "copying ${src_pinned} -> ${to_registry}:${version} (with referrers)"
        if ! DOCKER_CONFIG="$_dcfg" oras "${args[@]}" "$src_pinned" "${to_registry}:${version}"; then
            rm -rf "$_dcfg"
            log.error "channel.copy_with_referrers: oras cp failed (${from} -> ${to})"
            return "$BRIK_EXIT_EXTERNAL_FAIL"
        fi
        rm -rf "$_dcfg"

        # Prove the bytes: the version in the destination channel must be
        # the exact content the source pinned.
        local dst_pinned dst_digest
        dst_pinned="$(channel.resolve_digest "$version" "$to")" || return "$?"
        dst_digest="${dst_pinned##*@}"
        if [[ "$dst_digest" != "$digest" ]]; then
            log.error "post-copy digest mismatch on '${to}': expected ${digest}, got ${dst_digest}"
            return "$BRIK_EXIT_EXTERNAL_FAIL"
        fi
    fi

    # Prove the evidence: the attestations must verify ON THE DESTINATION
    # against the profile's trust material.
    brik.use transverse.attest
    local -a vargs=()
    [[ -n "$identity" ]] && vargs+=(--identity "$identity")
    [[ -n "$issuer" ]] && vargs+=(--issuer "$issuer")
    if ! attest.verify "${to_registry}@${digest}" "${vargs[@]}"; then
        log.error "channel.copy_with_referrers: '${to}' holds ${version} without verifiable evidence (fail-closed)"
        return "$BRIK_EXIT_EXTERNAL_FAIL"
    fi

    printf '%s@%s' "$to_registry" "$digest"
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
