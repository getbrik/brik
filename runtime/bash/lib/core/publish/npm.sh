#!/usr/bin/env bash
# @module publish.npm
# @requires npm
# @description Publish a Node.js package to an npm registry.

# Guard against double-sourcing
[[ -n "${_BRIK_CORE_PUBLISH_NPM_LOADED:-}" ]] && return 0
_BRIK_CORE_PUBLISH_NPM_LOADED=1

# Publish to npm registry.
# Usage: publish.npm.run [--registry <url>] [--tag <tag>] [--access <public|restricted>]
#        [--token-var <VAR>] [--dry-run]
# Reads defaults from BRIK_PUBLISH_NPM_* environment variables.
publish.npm.run() {
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

    runtime.require_tool npm || return "$BRIK_EXIT_MISSING_DEP"
    runtime.require_file "package.json" || return "$BRIK_EXIT_IO_FAILURE"

    # Build npm publish command
    local -a cmd=(npm publish)
    [[ -n "$registry" ]] && cmd+=(--registry "$registry")
    [[ -n "$tag" ]] && cmd+=(--tag "$tag")
    [[ -n "$access" ]] && cmd+=(--access "$access")

    # Set auth token if configured
    if [[ -n "$token_var" ]]; then
        _publish._require_secret_var "$token_var" "npm token" || return $?
        export NPM_TOKEN="${!token_var}"

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

    "${cmd[@]}"
    local rc=$?

    # cleanup: always scrub credentials from env
    unset NPM_TOKEN 2>/dev/null || true

    if [[ $rc -ne 0 ]]; then
        log.error "npm publish failed"
        return "$BRIK_EXIT_EXTERNAL_FAIL"
    fi

    log.info "npm publish completed successfully"
    return 0
}
