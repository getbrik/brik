#!/usr/bin/env bash
# @module publish.nuget
# @requires dotnet
# @description Publish to NuGet or a compatible feed.

# Guard against double-sourcing
[[ -n "${_BRIK_CORE_PUBLISH_NUGET_LOADED:-}" ]] && return 0
_BRIK_CORE_PUBLISH_NUGET_LOADED=1

# Publish to NuGet.
# Usage: publish.nuget.run [--source <url>] [--api-key-var <VAR>] [--dry-run]
# Reads defaults from BRIK_PUBLISH_NUGET_* environment variables.
publish.nuget.run() {
    local source="${BRIK_PUBLISH_NUGET_SOURCE:-}"
    local api_key_var="${BRIK_PUBLISH_NUGET_API_KEY_VAR:-}"
    local dry_run="${BRIK_DRY_RUN:-}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --source) source="$2"; shift 2 ;;
            --api-key-var) api_key_var="$2"; shift 2 ;;
            --dry-run) dry_run="true"; shift ;;
            --target) shift 2 ;;
            *) log.error "unknown option: $1"; return 2 ;;
        esac
    done

    runtime.require_tool dotnet || return 3

    # Find .nupkg files (enable globstar for recursive search)
    local -a nupkgs
    local prev_globstar
    prev_globstar="$(shopt -p globstar 2>/dev/null)" || true
    shopt -s globstar 2>/dev/null || true
    local f
    for f in ./**/*.nupkg; do
        [[ -f "$f" ]] && nupkgs+=("$f")
    done
    eval "$prev_globstar" 2>/dev/null || true

    if [[ ${#nupkgs[@]} -eq 0 ]]; then
        log.error "no .nupkg files found"
        return 6
    fi

    if [[ -n "$api_key_var" ]]; then
        _publish._require_secret_var "$api_key_var" "nuget api key" || return $?
    fi

    local pkg
    for pkg in "${nupkgs[@]}"; do
        local -a cmd=(dotnet nuget push "$pkg")
        [[ -n "$source" ]] && cmd+=(--source "$source")
        [[ -n "$api_key_var" ]] && cmd+=(--api-key "${!api_key_var}")

        if [[ "$dry_run" == "true" ]]; then
            log.info "[dry-run] ${cmd[*]}"
        else
            log.info "publishing: ${cmd[*]}"
            "${cmd[@]}" || {
                log.error "nuget push failed for $pkg"
                return 5
            }
        fi
    done

    log.info "nuget publish completed successfully"
    return 0
}
