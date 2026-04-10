#!/usr/bin/env bash
# @module cache
# @requires tar
# @description Save and restore cached paths by key.

# Guard against double-sourcing
[[ -n "${_BRIK_CORE_CACHE_LOADED:-}" ]] && return 0
_BRIK_CORE_CACHE_LOADED=1

# Default cache directory
_CACHE_BASE_DIR="${BRIK_CACHE_DIR:-.brik/cache}"

# Compute a hash for a cache key string.
# Uses sha256sum if available, falls back to md5, then plain key.
_cache._hash_key() {
    local key="$1"
    if command -v sha256sum >/dev/null 2>&1; then
        printf '%s' "$key" | sha256sum | cut -d' ' -f1
    elif command -v shasum >/dev/null 2>&1; then
        printf '%s' "$key" | shasum -a 256 | cut -d' ' -f1
    elif command -v md5 >/dev/null 2>&1; then
        printf '%s' "$key" | md5
    else
        # Fallback: sanitize key for use as filename
        printf '%s' "$key" | tr -c '[:alnum:]._-' '_'
    fi
}

# Save paths to cache under a given key.
# Usage: cache.save --key <key> --paths <path1> [path2...]
# Returns: 0=success, 2=invalid input, 3=tool missing, 5=command failed, 6=IO error
cache.save() {
    local key=""
    local -a paths=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --key) key="$2"; shift 2 ;;
            --paths) shift; while [[ $# -gt 0 && "$1" != --* ]]; do paths+=("$1"); shift; done ;;
            *) log.error "unknown option: $1"; return 2 ;;
        esac
    done

    if [[ -z "$key" ]]; then
        log.error "cache key is required (--key)"
        return 2
    fi

    if [[ ${#paths[@]} -eq 0 ]]; then
        log.error "no paths specified (--paths)"
        return 2
    fi

    runtime.require_tool tar || return 3

    # Verify all source paths exist
    local p
    for p in "${paths[@]}"; do
        if [[ ! -e "$p" ]]; then
            log.error "cache source path not found: $p"
            return 6
        fi
    done

    local hash
    hash="$(_cache._hash_key "$key")"
    local cache_dir="${_CACHE_BASE_DIR}"
    mkdir -p "$cache_dir" || {
        log.error "cannot create cache directory: $cache_dir"
        return 6
    }

    local archive="${cache_dir}/${hash}.tar.gz"

    log.info "saving cache: key=$key (${#paths[@]} paths)"

    tar -czf "$archive" "${paths[@]}" 2>/dev/null || {
        log.error "cache save failed"
        return 5
    }

    log.info "cache saved: $archive"
    return 0
}

# Restore cached paths from a given key.
# Usage: cache.restore --key <key> [--destination <path>]
# Returns: 0=success, 1=cache miss, 2=invalid input, 3=tool missing, 5=command failed
cache.restore() {
    local key=""
    local destination="."

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --key) key="$2"; shift 2 ;;
            --destination) destination="$2"; shift 2 ;;
            *) log.error "unknown option: $1"; return 2 ;;
        esac
    done

    if [[ -z "$key" ]]; then
        log.error "cache key is required (--key)"
        return 2
    fi

    runtime.require_tool tar || return 3

    local hash
    hash="$(_cache._hash_key "$key")"
    local archive="${_CACHE_BASE_DIR}/${hash}.tar.gz"

    if [[ ! -f "$archive" ]]; then
        log.info "cache miss: key=$key"
        return 1
    fi

    log.info "restoring cache: key=$key"

    # idempotent: directory may already exist or be read-only
    mkdir -p "$destination" 2>/dev/null || true

    tar -xzf "$archive" -C "$destination" 2>/dev/null || {
        log.error "cache restore failed"
        return 5
    }

    log.info "cache restored from $archive"
    return 0
}
