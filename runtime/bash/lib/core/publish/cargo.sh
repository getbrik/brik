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
            *) log.error "unknown option: $1"; return "$BRIK_EXIT_INVALID_INPUT" ;;
        esac
    done

    runtime.require_tool cargo || return "$BRIK_EXIT_MISSING_DEP"
    runtime.require_file "Cargo.toml" || return "$BRIK_EXIT_IO_FAILURE"

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

    local rc=0
    "${cmd[@]}" || rc=$?

    # cleanup: always scrub credentials from env
    unset CARGO_REGISTRY_TOKEN 2>/dev/null || true

    if [[ $rc -ne 0 ]]; then
        log.error "cargo publish failed"
        return "$BRIK_EXIT_EXTERNAL_FAIL"
    fi

    log.info "cargo publish completed successfully"
    return 0
}
