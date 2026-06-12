#!/usr/bin/env bash
# @module pkg.npm
# @requires npm
# @description Publish a Node.js package to an npm registry.

# Guard against double-sourcing
[[ -n "${_BRIK_PKG_NPM_LOADED:-}" ]] && return 0
_BRIK_PKG_NPM_LOADED=1

# Publish to npm registry.
# Usage: pkg.npm.publish [--registry <url>] [--tag <tag>] [--access <public|restricted>]
#        [--token-var <VAR>] [--dry-run]
# Reads defaults from BRIK_PUBLISH_NPM_* environment variables.
pkg.npm.publish() {
    local registry="${BRIK_PUBLISH_NPM_REGISTRY:-}"
    local tag="${BRIK_PUBLISH_NPM_TAG:-latest}"
    local access="${BRIK_PUBLISH_NPM_ACCESS:-}"
    local token_var="${BRIK_PUBLISH_NPM_TOKEN_VAR:-}"
    local dry_run="${BRIK_DRY_RUN:-}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --registry) registry="$2"; shift 2 ;;
            --tag) tag="$2"; shift 2 ;;
            --access) access="$2"; shift 2 ;;
            --token-var) token_var="$2"; shift 2 ;;
            --dry-run) dry_run="true"; shift ;;
            *) log.error "unknown option: $1"; return "$BRIK_EXIT_INVALID_INPUT" ;;
        esac
    done

    pipeline.require_tool npm || return "$BRIK_EXIT_MISSING_DEP"
    pipeline.require_file "package.json" || return "$BRIK_EXIT_IO_FAILURE"

    # Referential absorption: a declared PackageRegistry endpoint of this
    # format is the single source of truth for the destination and identity;
    # the BRIK_PUBLISH_NPM_* variables remain the legacy path without one.
    brik.use package-managers._endpoint 2>/dev/null || true
    local _ep=""
    if declare -f pkg.endpoint.resolve >/dev/null 2>&1; then
        _ep="$(pkg.endpoint.resolve npm "$registry")" || return "$?"
    fi
    if [[ -n "$_ep" ]]; then
        registry="$(jq -r '.url' <<<"$_ep")"
        case "$(jq -r '.method' <<<"$_ep")" in
            token) token_var="$(jq -r '.token_var' <<<"$_ep")" ;;
            basic)
                # npm's _auth line wants base64(user:password).
                brik.use transverse.env
                BRIK_PKG_NPM_AUTH="$(printf '%s:%s' "$(jq -r '.username' <<<"$_ep")" \
                    "$(transverse.env.resolve_indirect "$(jq -r '.password_var' <<<"$_ep")")" \
                    | base64 | tr -d '\n')"
                export BRIK_PKG_NPM_AUTH
                token_var="BRIK_PKG_NPM_AUTH"
                ;;
            none) token_var="" ;;
        esac
    fi

    # Build npm publish command
    local -a cmd=(npm publish)
    [[ -n "$registry" ]] && cmd+=(--registry "$registry")
    [[ -n "$tag" ]] && cmd+=(--tag "$tag")
    [[ -n "$access" ]] && cmd+=(--access "$access")

    # Set auth token if configured
    if [[ -n "$token_var" ]]; then
        brik.use transverse.secrets
        brik.use transverse.env
        transverse.secrets.require_var "$token_var" "npm token" || return $?
        NPM_TOKEN="$(transverse.env.resolve_indirect "$token_var")"
        export NPM_TOKEN

        # Generate .npmrc for registry auth
        # Write to both project .npmrc and user ~/.npmrc for maximum compatibility
        if [[ -n "$registry" ]]; then
            local registry_path
            registry_path="${registry#http:}"
            registry_path="${registry_path#https:}"
            local npmrc_content
            npmrc_content="${registry_path}:_auth=${NPM_TOKEN}
${registry_path}:always-auth=true"
            echo "$npmrc_content" >> .npmrc
            echo "$npmrc_content" >> "${HOME}/.npmrc"
            log.info "configured .npmrc for registry authentication"
        fi
    fi

    if [[ "$dry_run" == "true" ]]; then
        cmd+=(--dry-run)
        log.info "[dry-run] ${cmd[*]}"
    else
        log.info "publishing npm package: ${cmd[*]}"
    fi

    local rc=0
    "${cmd[@]}" || rc=$?

    # cleanup: always scrub credentials from env
    unset NPM_TOKEN 2>/dev/null || true

    if [[ $rc -ne 0 ]]; then
        log.error "npm publish failed"
        return "$BRIK_EXIT_EXTERNAL_FAIL"
    fi

    log.info "npm publish completed successfully"
    return 0
}
