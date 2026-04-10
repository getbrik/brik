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
# Auth: uses NUGET_API_KEY env var to avoid CLI credential exposure.
publish.nuget.run() {
    local source="${BRIK_PUBLISH_NUGET_SOURCE:-}"
    local api_key_var="${BRIK_PUBLISH_NUGET_API_KEY_VAR:-}"
    local dry_run="${BRIK_DRY_RUN:-}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --source) source="$2"; shift 2 ;;
            --api-key-var) api_key_var="$2"; shift 2 ;;
            --dry-run) dry_run="true"; shift ;;
            *) log.error "unknown option: $1"; return 2 ;;
        esac
    done

    runtime.require_tool dotnet || return 3

    # Find .nupkg files (enable globstar for recursive search)
    local -a nupkgs
    local prev_globstar
    # defensive: globstar may not be available in all bash versions
    prev_globstar="$(shopt -p globstar 2>/dev/null)" || true
    shopt -s globstar 2>/dev/null || true
    local f
    for f in ./**/*.nupkg; do
        [[ -f "$f" ]] && nupkgs+=("$f")
    done
    eval "$prev_globstar" 2>/dev/null || true  # restore previous globstar state

    if [[ ${#nupkgs[@]} -eq 0 ]]; then
        # Auto-pack if no .nupkg files found
        log.info "no .nupkg files found, running dotnet pack"
        dotnet pack --configuration Release --output ./nupkg 2>&1 || {
            log.error "dotnet pack failed"
            return 6
        }
        for f in ./nupkg/*.nupkg; do
            [[ -f "$f" ]] && nupkgs+=("$f")
        done
        if [[ ${#nupkgs[@]} -eq 0 ]]; then
            log.error "no .nupkg files found after dotnet pack"
            return 6
        fi
    fi

    if [[ -n "$api_key_var" ]]; then
        _publish._require_secret_var "$api_key_var" "nuget api key" || return $?
        # Set API key via environment variable (not CLI arg)
        export NUGET_API_KEY="${!api_key_var}"
    fi

    # Create temporary NuGet.Config for HTTP sources (NuGet requires HTTPS by default)
    # Also supports basic auth for Nexus/Artifactory when api_key is in "user:password" format
    local tmp_nuget_config=""
    local use_config_auth=""
    if [[ -n "$source" ]] && [[ "$source" == http://* ]]; then
        tmp_nuget_config="$(mktemp)"
        local nuget_username="" nuget_password=""
        if [[ -n "$api_key_var" ]] && [[ "${!api_key_var}" == *:* ]]; then
            # Basic auth format (user:password) for Nexus/Artifactory
            nuget_username="${!api_key_var%%:*}"
            nuget_password="${!api_key_var#*:}"
            use_config_auth="true"
        fi
        # Build NuGet.Config with source and optional credentials
        {
            echo '<?xml version="1.0" encoding="utf-8"?>'
            echo '<configuration>'
            echo '  <packageSources>'
            echo '    <clear />'
            echo "    <add key=\"brik\" value=\"${source}\" allowInsecureConnections=\"true\" />"
            echo '  </packageSources>'
            if [[ -n "$use_config_auth" ]]; then
                echo '  <packageSourceCredentials>'
                echo '    <brik>'
                echo "      <add key=\"Username\" value=\"${nuget_username}\" />"
                echo "      <add key=\"ClearTextPassword\" value=\"${nuget_password}\" />"
                echo '    </brik>'
                echo '  </packageSourceCredentials>'
            fi
            echo '</configuration>'
        } > "$tmp_nuget_config"
        chmod 600 "$tmp_nuget_config"
    fi

    local pkg
    for pkg in "${nupkgs[@]}"; do
        local -a cmd=(dotnet nuget push "$pkg")
        if [[ -n "$tmp_nuget_config" ]]; then
            cmd+=(--configfile "$tmp_nuget_config" --source "brik")
            # Skip --api-key when using config-based auth
            [[ -z "$use_config_auth" ]] && [[ -n "$api_key_var" ]] && cmd+=(--api-key "$NUGET_API_KEY")
        elif [[ -n "$source" ]]; then
            cmd+=(--source "$source")
            [[ -n "$api_key_var" ]] && cmd+=(--api-key "$NUGET_API_KEY")
        else
            [[ -n "$api_key_var" ]] && cmd+=(--api-key "$NUGET_API_KEY")
        fi

        if [[ "$dry_run" == "true" ]]; then
            log.info "[dry-run] dotnet nuget push $pkg${source:+ --source $source} --api-key ***"
        else
            log.info "publishing: dotnet nuget push $pkg${source:+ --source $source} --api-key ***"
            "${cmd[@]}" || {
                log.error "nuget push failed for $pkg"
                # cleanup: always scrub credentials on error path
                unset NUGET_API_KEY 2>/dev/null || true
                rm -f "$tmp_nuget_config" 2>/dev/null || true
                return 5
            }
        fi
    done

    # cleanup: always scrub credentials from env
    unset NUGET_API_KEY 2>/dev/null || true
    rm -f "$tmp_nuget_config" 2>/dev/null || true

    log.info "nuget publish completed successfully"
    return 0
}
