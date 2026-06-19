#!/usr/bin/env bash
# @module pkg._endpoint
# @description Resolve a publisher's registry endpoint from the referential.
#
# The referential may declare one PackageRegistry endpoint per published
# format (npm|pypi|maven|cargo|nuget). When declared, it is the single
# source of truth for WHERE the publisher ships (url) and with which
# transport posture (declared http:// or tls.trust: insecure -- legal but
# noisy) and identity (a referenced Credential document). The per-manager
# ad-hoc variables remain the legacy path when no endpoint of the format is
# declared.

# Guard against double-sourcing
[[ -n "${_BRIK_PKG_ENDPOINT_LOADED:-}" ]] && return 0
_BRIK_PKG_ENDPOINT_LOADED=1

# _pkg.endpoint._var_of_ref - echo the env var name behind an env:// ref.
# Package-credential references are env:// only in v1: the publishers consume
# variable NAMES (their tools read the values from the environment), and a
# file:// or bao:// secret has no such name to hand over.
_pkg.endpoint._var_of_ref() {
    local ref="$1" field="$2"
    case "$ref" in
        env://*) printf '%s' "${ref#env://}" ;;
        *)
            log.error "package registry credential ${field} must be an env:// reference (got '${ref}')"
            return "$BRIK_EXIT_CONFIG_ERROR"
            ;;
    esac
}

# pkg.endpoint.resolve - echo (as JSON) the publishing contract derived from
# the referential for one format, or nothing when no PackageRegistry of that
# format is declared (legacy path; absence of declaration is a declared
# posture, not an error).
#
# Output JSON: { url, method, insecure,
#                token_var (method=token),
#                username + password_var (method=basic) }
# Fail-closed (CONFIG_ERROR): several endpoints of the format; a brik.yml
# URL that contradicts the declared endpoint; tls.trust: custom-ca (no
# package manager consumes a CA bundle yet -- never silently downgraded);
# a missing or non-env:// credential.
# Usage: ep="$(pkg.endpoint.resolve <format> [<brik_yml_url>])" || return $?
pkg.endpoint.resolve() {
    local format="$1" declared_url="${2:-}"
    if [[ -z "$format" ]]; then
        log.error "pkg.endpoint.resolve: a format is required"
        return "$BRIK_EXIT_INVALID_INPUT"
    fi

    brik.use transverse.infra

    local root
    if ! root="$(infra.root 2>/dev/null)"; then
        return 0
    fi

    local file found=""
    for file in "${root}/endpoints"/*.yml "${root}/endpoints"/*.yaml; do
        [[ -f "$file" ]] || continue
        [[ "$(yq '.kind // ""' "$file")" == "PackageRegistry" ]] || continue
        [[ "$(yq '.format // ""' "$file")" == "$format" ]] || continue
        if [[ -n "$found" ]]; then
            log.error "multiple PackageRegistry endpoints declared for format '${format}' (expected at most one)"
            return "$BRIK_EXIT_CONFIG_ERROR"
        fi
        found="$file"
    done
    [[ -z "$found" ]] && return 0

    local url trust insecure="false"
    url="$(yq '.url // ""' "$found")"
    trust="$(yq '.tls.trust // "system"' "$found")"

    # The endpoint is the single source of truth for the destination: a
    # project config pointing somewhere else is a contradiction, not an
    # override.
    if [[ -n "$declared_url" && "$declared_url" != "$url" ]]; then
        log.error "publish.${format} declares '${declared_url}' but the referential's PackageRegistry endpoint declares '${url}' -- failing closed"
        return "$BRIK_EXIT_CONFIG_ERROR"
    fi

    if [[ "$trust" == "custom-ca" ]]; then
        log.error "PackageRegistry '${format}': tls.trust: custom-ca is not wired for package managers yet -- failing closed (declare system, insecure or an http:// url)"
        return "$BRIK_EXIT_CONFIG_ERROR"
    fi
    if [[ "$url" == http://* ]]; then
        log.warn "package registry for '${format}' is declared over plain http (legal but insecure)"
        insecure="true"
    elif [[ "$trust" == "insecure" ]]; then
        log.warn "package registry for '${format}' is declared with tls.trust: insecure (legal but insecure)"
        insecure="true"
    fi

    local cred_name method="none" token_var="" username="" password_var=""
    cred_name="$(yq '.credential // ""' "$found")"
    if [[ -n "$cred_name" ]]; then
        local cred
        cred="$(infra.credential "$cred_name")" || return "$?"
        method="$(printf '%s' "$cred" | jq -r '.method')"
        case "$method" in
            token)
                token_var="$(_pkg.endpoint._var_of_ref \
                    "$(printf '%s' "$cred" | jq -r '.token')" token)" || return "$?"
                ;;
            basic)
                username="$(printf '%s' "$cred" | jq -r '.username')"
                password_var="$(_pkg.endpoint._var_of_ref \
                    "$(printf '%s' "$cred" | jq -r '.password')" password)" || return "$?"
                ;;
            none) ;;
            *)
                log.error "PackageRegistry '${format}': credential method '${method}' is not usable by a package publisher (expected token, basic or none)"
                return "$BRIK_EXIT_CONFIG_ERROR"
                ;;
        esac
    fi

    jq -nc --arg url "$url" --arg method "$method" --arg insecure "$insecure" \
        --arg token_var "$token_var" --arg username "$username" \
        --arg password_var "$password_var" \
        '{url: $url, method: $method, insecure: ($insecure == "true"),
          token_var: $token_var, username: $username, password_var: $password_var}'
}

# pkg.registry.resolve - echo (as JSON) the container-registry login contract
# derived from the referential for a registry authority, or nothing when no
# Registry endpoint matches that authority (legacy path; absence keeps the
# BRIK_PUBLISH_DOCKER_*_VAR variables). The credential is resolved BY TARGET
# (PD3): infra.credential_for_endpoint, environment-independent, since a CI
# push selects no deploy environment. When the registry IS declared, the
# referential is the source of truth from there on -- an unbound or
# mis-resolved credential fails closed, never a silent legacy fallback.
#
# Output JSON: { method, insecure, username_var, password_var (method=basic) }
# Fail-closed (CONFIG_ERROR): declared-but-unbound/divergent credential; a
# credential method docker login cannot consume; a non-env:// reference.
# Usage: ep="$(pkg.registry.resolve <authority>)" || return $?
pkg.registry.resolve() {
    local host="$1"
    if [[ -z "$host" ]]; then
        log.error "pkg.registry.resolve: a registry host is required"
        return "$BRIK_EXIT_INVALID_INPUT"
    fi

    brik.use transverse.infra

    # Unconfigured referential, or no Registry of this authority: legacy path.
    infra.root >/dev/null 2>&1 || return 0
    local ep
    ep="$(infra.registry_for "$host" 2>/dev/null)" || return 0

    # Re-derive the transport posture so docker logs the same insecure warning
    # the package publishers do (infra.registry_for's own warning was silenced
    # above to keep the no-match path quiet).
    local url trust insecure="false"
    url="$(printf '%s' "$ep" | jq -r '.url // ""')"
    trust="$(printf '%s' "$ep" | jq -r '.tls.trust // "system"')"
    if [[ "$url" == http://* ]]; then
        log.warn "registry '${host}' is declared over plain http (legal but insecure)"
        insecure="true"
    elif [[ "$trust" == "insecure" ]]; then
        log.warn "registry '${host}' is declared with tls.trust: insecure (legal but insecure)"
        insecure="true"
    fi

    local name cred method username_var="" password_var=""
    name="$(printf '%s' "$ep" | jq -r '.name')"
    cred="$(infra.credential_for_endpoint "$name")" || return "$?"
    method="$(printf '%s' "$cred" | jq -r '.method')"
    case "$method" in
        basic)
            username_var="$(_pkg.endpoint._var_of_ref \
                "$(printf '%s' "$cred" | jq -r '.username')" username)" || return "$?"
            password_var="$(_pkg.endpoint._var_of_ref \
                "$(printf '%s' "$cred" | jq -r '.password')" password)" || return "$?"
            ;;
        none) ;;
        *)
            log.error "Registry '${host}': credential method '${method}' is not usable by docker login (expected basic or none)"
            return "$BRIK_EXIT_CONFIG_ERROR"
            ;;
    esac

    jq -nc --arg method "$method" --arg insecure "$insecure" \
        --arg username_var "$username_var" --arg password_var "$password_var" \
        '{method: $method, insecure: ($insecure == "true"),
          username_var: $username_var, password_var: $password_var}'
}
