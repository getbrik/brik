#!/usr/bin/env bash
# @module pkg.cargo
# @requires cargo
# @description Publish to crates.io or a compatible Cargo registry (e.g. Nexus).

# Guard against double-sourcing
[[ -n "${_BRIK_PKG_CARGO_LOADED:-}" ]] && return 0
_BRIK_PKG_CARGO_LOADED=1

# Publish to a Cargo registry.
# Usage: pkg.cargo.publish [--registry <name>] [--index <url>] [--token-var <VAR>] [--dry-run]
# Reads defaults from BRIK_PUBLISH_CARGO_* environment variables.
# Auth: uses CARGO_REGISTRY_TOKEN env var (not CLI args) to avoid process listing exposure.
# When --registry and --index are both set, exports CARGO_REGISTRIES_<NAME>_INDEX
# so cargo knows where the sparse index lives (e.g. Nexus, Artifactory).
pkg.cargo.publish() {
    local registry="${BRIK_PUBLISH_CARGO_REGISTRY:-}"
    local index="${BRIK_PUBLISH_CARGO_INDEX:-}"
    local token_var="${BRIK_PUBLISH_CARGO_TOKEN_VAR:-}"
    local dry_run="${BRIK_DRY_RUN:-}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --registry) registry="$2"; shift 2 ;;
            --index) index="$2"; shift 2 ;;
            --token-var) token_var="$2"; shift 2 ;;
            --dry-run) dry_run="true"; shift ;;
            *) log.error "unknown option: $1"; return "$BRIK_EXIT_INVALID_INPUT" ;;
        esac
    done

    pipeline.require_tool cargo || return "$BRIK_EXIT_MISSING_DEP"
    pipeline.require_file "Cargo.toml" || return "$BRIK_EXIT_IO_FAILURE"

    # Set token via environment variable (never passed as CLI arg)
    # When a named registry is used, cargo expects CARGO_REGISTRIES_<NAME>_TOKEN
    # instead of the global CARGO_REGISTRY_TOKEN.
    local token_env_var="CARGO_REGISTRY_TOKEN"
    if [[ -n "$token_var" ]]; then
        brik.use transverse.secrets
        brik.use transverse.env
        transverse.secrets.require_var "$token_var" "cargo token" || return $?
        if [[ -n "$registry" ]]; then
            local upper_name
            upper_name=$(printf '%s' "$registry" | tr '[:lower:]-' '[:upper:]_')
            token_env_var="CARGO_REGISTRIES_${upper_name}_TOKEN"
        fi
        local cargo_token_value
        cargo_token_value="$(transverse.env.resolve_indirect "$token_var")"
        export "$token_env_var=$cargo_token_value"
    fi

    # When registry + index are provided, tell cargo where the index lives
    local index_env_var=""
    if [[ -n "$registry" && -n "$index" ]]; then
        local upper_name
        upper_name=$(printf '%s' "$registry" | tr '[:lower:]-' '[:upper:]_')
        index_env_var="CARGO_REGISTRIES_${upper_name}_INDEX"
        export "$index_env_var"="$index"
    fi

    # --allow-dirty: Jenkins-style runners reuse workspaces across stages, so cargo's git-clean guard always trips in CI.
    local -a cmd=(cargo publish --allow-dirty)
    [[ -n "$registry" ]] && cmd+=(--registry "$registry")

    local target="${registry:-crates.io}"
    if [[ "$dry_run" == "true" ]]; then
        cmd+=(--dry-run)
        log.info "[dry-run] ${cmd[*]}"
    else
        log.info "publishing to ${target}: ${cmd[*]}"
    fi

    local rc=0
    "${cmd[@]}" || rc=$?

    # cleanup: always scrub credentials and index config from env
    unset "$token_env_var" 2>/dev/null || true
    [[ -n "$index_env_var" ]] && unset "$index_env_var" 2>/dev/null || true

    if [[ $rc -ne 0 ]]; then
        log.error "cargo publish failed"
        return "$BRIK_EXIT_EXTERNAL_FAIL"
    fi

    log.info "cargo publish completed successfully"
    return 0
}
