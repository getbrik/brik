#!/usr/bin/env bash
# @module publish.cargo
# @requires cargo
# @description Publish to crates.io or a compatible registry.

# Guard against double-sourcing
[[ -n "${_BRIK_CORE_PUBLISH_CARGO_LOADED:-}" ]] && return 0
_BRIK_CORE_PUBLISH_CARGO_LOADED=1

# Publish to crates.io.
# Usage: publish.cargo.run [--registry <name>] [--token-var <VAR>] [--dry-run]
# Reads defaults from BRIK_PUBLISH_CARGO_* environment variables.
# Auth: uses CARGO_REGISTRY_TOKEN env var (not CLI args) to avoid process listing exposure.
publish.cargo.run() {
    local registry="${BRIK_PUBLISH_CARGO_REGISTRY:-}"
    local token_var="${BRIK_PUBLISH_CARGO_TOKEN_VAR:-}"
    local dry_run="${BRIK_DRY_RUN:-}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --registry) registry="$2"; shift 2 ;;
            --token-var) token_var="$2"; shift 2 ;;
            --dry-run) dry_run="true"; shift ;;
            --target) shift 2 ;;
            *) log.error "unknown option: $1"; return 2 ;;
        esac
    done

    runtime.require_tool cargo || return 3
    runtime.require_file "Cargo.toml" || return 6

    # Set token via environment variable (never passed as CLI arg)
    if [[ -n "$token_var" ]]; then
        _publish._require_secret_var "$token_var" "cargo token" || return $?
        export CARGO_REGISTRY_TOKEN="${!token_var}"
    fi

    local -a cmd=(cargo publish)
    [[ -n "$registry" ]] && cmd+=(--registry "$registry")

    if [[ "$dry_run" == "true" ]]; then
        cmd+=(--dry-run)
        log.info "[dry-run] ${cmd[*]}"
    else
        log.info "publishing to crates.io: ${cmd[*]}"
    fi

    "${cmd[@]}"
    local rc=$?

    # Cleanup token from environment
    unset CARGO_REGISTRY_TOKEN 2>/dev/null || true

    if [[ $rc -ne 0 ]]; then
        log.error "cargo publish failed"
        return 5
    fi

    log.info "cargo publish completed successfully"
    return 0
}
