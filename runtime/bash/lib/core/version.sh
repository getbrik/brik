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
    return 2
}

# Bump a version component.
# Usage: version.bump <current> <major|minor|patch|prerelease>
# Prints the new version on stdout.
version.bump() {
    local current="$1"
    local bump_type="$2"

    version.validate "$current" || return 2

    # Strip prerelease and build metadata for splitting
    local base="${current%%[-+]*}"
    local IFS='.'
    local -a parts
    read -ra parts <<< "$base"
    local major="${parts[0]}"
    local minor="${parts[1]}"
    local patch="${parts[2]}"

    case "$bump_type" in
        major)
            major=$(( major + 1 ))
            minor=0
            patch=0
            ;;
        minor)
            minor=$(( minor + 1 ))
            patch=0
            ;;
        patch)
            patch=$(( patch + 1 ))
            ;;
        prerelease)
            # Increment patch and add -rc.1
            patch=$(( patch + 1 ))
            printf '%d.%d.%d-rc.1' "$major" "$minor" "$patch"
            return 0
            ;;
        *)
            log.error "unknown bump type: $bump_type"
            return 2
            ;;
    esac

    printf '%d.%d.%d' "$major" "$minor" "$patch"
    return 0
}

# Compare two semver versions.
# Prints -1, 0, or 1 on stdout.
version.compare() {
    local a="$1"
    local b="$2"

    version.validate "$a" || return 2
    version.validate "$b" || return 2

    local base_a="${a%%[-+]*}"
    local base_b="${b%%[-+]*}"

    local IFS='.'
    local -a parts_a parts_b
    read -ra parts_a <<< "$base_a"
    read -ra parts_b <<< "$base_b"

    local i
    for i in 0 1 2; do
        if [[ "${parts_a[$i]}" -gt "${parts_b[$i]}" ]]; then
            printf '1'
            return 0
        elif [[ "${parts_a[$i]}" -lt "${parts_b[$i]}" ]]; then
            printf -- '-1'
            return 0
        fi
    done

    printf '0'
    return 0
}

# Read current version from a file or git tag.
# Usage: version.current [--from-file <path> | --from-git-tag]
version.current() {
    local source="auto"
    local file_path=""

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
            *)
                log.error "unknown option: $1"
                return 2
                ;;
        esac
    done

    case "$source" in
        file)
            if [[ ! -f "$file_path" ]]; then
                log.error "file not found: $file_path"
                return 6
            fi
            # Try package.json
            if [[ "$file_path" == *package.json ]]; then
                if command -v jq >/dev/null 2>&1; then
                    jq -r '.version // empty' "$file_path" 2>/dev/null || return 2
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
            runtime.require_tool git || return 3
            local tag
            tag="$(git describe --tags --abbrev=0 2>/dev/null)" || {
                log.error "no git tags found"
                return 1
            }
            # Strip leading 'v' if present
            printf '%s' "${tag#v}"
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
                    return 1
                }
                printf '%s' "${tag#v}"
                return 0
            fi
            log.error "cannot determine version: no package.json or git tags"
            return 1
            ;;
    esac
}

# Write a version to a file.
# Usage: version.write <version> [--file <path>]
version.write() {
    local version="$1"
    shift
    local file_path=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --file) file_path="$2"; shift 2 ;;
            *) log.error "unknown option: $1"; return 2 ;;
        esac
    done

    version.validate "$version" || return 2

    if [[ -z "$file_path" ]]; then
        # Default to package.json if it exists
        if [[ -f "package.json" ]] && command -v jq >/dev/null 2>&1; then
            local tmp
            tmp="$(mktemp)" || return 6
            jq --arg v "$version" '.version = $v' package.json > "$tmp" || {
                rm -f "$tmp"
                return 6
            }
            mv "$tmp" package.json || return 6
            return 0
        fi
        log.error "no target file specified and no package.json found"
        return 2
    fi

    printf '%s\n' "$version" > "$file_path" || {
        log.error "cannot write to: $file_path"
        return 6
    }
    return 0
}
