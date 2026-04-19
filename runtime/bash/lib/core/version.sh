#!/usr/bin/env bash
# @module version
# @description Semantic versioning functions for brik-lib.
# @requires jq (optional, for package.json parsing)

# Guard against double-sourcing
[[ -n "${_BRIK_CORE_VERSION_LOADED:-}" ]] && return 0
_BRIK_CORE_VERSION_LOADED=1

# Validate a semver string.
# Returns 0 if valid, 2 if invalid.
version.validate() {
    local version="$1"
    local pattern='^[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.]+)?(\+[a-zA-Z0-9.]+)?$'
    if [[ "$version" =~ $pattern ]]; then
        return 0
    fi
    log.error "invalid semver: $version"
    return "$BRIK_EXIT_INVALID_INPUT"
}

# Read current version from a file or git tag.
# Usage: version.current [--from-file <path> | --from-git-tag [--prefix <prefix>]]
version.current() {
    local source="auto"
    local file_path=""
    local prefix="v"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --from-file)
                source="file"
                file_path="$2"
                shift 2
                ;;
            --from-git-tag)
                source="git"
                shift
                ;;
            --prefix)
                prefix="$2"
                shift 2
                ;;
            *)
                log.error "unknown option: $1"
                return "$BRIK_EXIT_INVALID_INPUT"
                ;;
        esac
    done

    case "$source" in
        file)
            if [[ ! -f "$file_path" ]]; then
                log.error "file not found: $file_path"
                return "$BRIK_EXIT_IO_FAILURE"
            fi
            # Try package.json
            if [[ "$file_path" == *package.json ]]; then
                if command -v jq >/dev/null 2>&1; then
                    jq -r '.version // empty' "$file_path" 2>/dev/null || return "$BRIK_EXIT_INVALID_INPUT"
                else
                    grep '"version"' "$file_path" | head -1 | sed 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/'
                fi
                return 0
            fi
            # Generic: read first line
            head -1 "$file_path"
            return 0
            ;;
        git)
            runtime.require_tool git || return "$BRIK_EXIT_MISSING_DEP"
            local tag
            tag="$(git describe --tags --abbrev=0 2>/dev/null)" || {
                log.error "no git tags found"
                return "$BRIK_EXIT_FAILURE"
            }
            # Strip tag prefix (default: v)
            printf '%s' "${tag#"$prefix"}"
            return 0
            ;;
        auto)
            # Try package.json in current directory
            if [[ -f "package.json" ]] && command -v jq >/dev/null 2>&1; then
                jq -r '.version // empty' package.json 2>/dev/null
                return 0
            fi
            # Fallback to git tag
            if command -v git >/dev/null 2>&1; then
                local tag
                tag="$(git describe --tags --abbrev=0 2>/dev/null)" || {
                    log.error "cannot determine version"
                    return "$BRIK_EXIT_FAILURE"
                }
                printf '%s' "${tag#"$prefix"}"
                return 0
            fi
            log.error "cannot determine version: no package.json or git tags"
            return "$BRIK_EXIT_FAILURE"
            ;;
    esac
}
