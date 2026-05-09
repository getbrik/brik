#!/usr/bin/env bash
# @module artifact
# @requires sha256sum, tar, stat, jq
# @description Summarize a build artifact (file or directory) into a JSON
#   object recordable under a stage's business section.

# Guard against double-sourcing.
[[ -n "${_BRIK_TRANSVERSE_ARTIFACT_LOADED:-}" ]] && return 0
_BRIK_TRANSVERSE_ARTIFACT_LOADED=1

# Compute size in bytes for a path. Cross-platform: GNU stat uses
# `-c %s`, BSD/macOS stat uses `-f %z`. For directories, sum the size
# of regular files via find.
_artifact._size_bytes() {
    local _p="$1"
    if [[ -f "$_p" ]]; then
        if stat -c%s "$_p" >/dev/null 2>&1; then
            stat -c%s "$_p"
        else
            stat -f%z "$_p"  # KCOV_EXCL_LINE -- BSD/macOS fallback, unreachable on GNU stat
        fi
    elif [[ -d "$_p" ]]; then
        local _total=0 _n
        while IFS= read -r -d '' _n; do
            local _s=0
            if stat -c%s "$_n" >/dev/null 2>&1; then
                _s="$(stat -c%s "$_n" 2>/dev/null || printf '0')"
            else
                _s="$(stat -f%z "$_n" 2>/dev/null || printf '0')"  # KCOV_EXCL_LINE -- BSD/macOS fallback
            fi
            _total=$((_total + _s))
        done < <(find "$_p" -type f -print0 2>/dev/null)
        printf '%d' "$_total"
    else
        printf '0'
    fi
}

# Compute sha256 of a file or, for a directory, of a deterministic tar
# stream of its contents (sorted file list + GNU tar metadata-stripping
# when available).
_artifact._sha256() {
    local _p="$1"
    if [[ -f "$_p" ]]; then
        sha256sum "$_p" 2>/dev/null | cut -d' ' -f1
        return 0
    fi
    if [[ -d "$_p" ]]; then
        local _list
        _list="$(cd "$_p" && find . -type f -print | LC_ALL=C sort)"
        if [[ -z "$_list" ]]; then
            : | sha256sum 2>/dev/null | cut -d' ' -f1
            return 0
        fi
        if tar --version 2>/dev/null | grep -q 'GNU tar'; then
            (cd "$_p" && printf '%s\n' "$_list" \
              | tar --owner=0 --group=0 --mtime='1970-01-01 UTC' \
                    --no-recursion -cf - --files-from=- 2>/dev/null) \
              | sha256sum 2>/dev/null | cut -d' ' -f1
        else
            # KCOV_EXCL_START -- BSD tar fallback, unreachable on GNU tar CI
            (cd "$_p" && printf '%s\n' "$_list" | tar -cf - -T - 2>/dev/null) \
              | sha256sum 2>/dev/null | cut -d' ' -f1
            # KCOV_EXCL_STOP
        fi
        return 0
    fi
    return 1  # KCOV_EXCL_LINE -- defensive guard, callers always pass a file or dir
}

# Resolve to an absolute path. realpath when available; pwd fallback
# for macOS without coreutils.
_artifact._abs_path() {
    local _p="$1"
    if command -v realpath >/dev/null 2>&1; then
        realpath "$_p" 2>/dev/null && return 0
    fi
    # KCOV_EXCL_START -- realpath is present on every supported runner; this
    # block is the no-coreutils fallback for stripped-down environments.
    if [[ -d "$_p" ]]; then
        (cd "$_p" 2>/dev/null && pwd)
    elif [[ -f "$_p" ]]; then
        local _d _b
        _d="$(cd "$(dirname "$_p")" 2>/dev/null && pwd)" || return 1
        _b="$(basename "$_p")"
        printf '%s/%s' "$_d" "$_b"
    else
        return 1
    fi
    # KCOV_EXCL_STOP
}

# Summarize an artifact path into a JSON object.
# Usage: artifact.summarize <path>
# Prints {type, name, size_bytes, sha256, path} to stdout.
# Returns non-zero on missing path or missing required tools.
artifact.summarize() {
    if [[ $# -lt 1 ]]; then
        printf 'artifact.summarize: missing path argument\n' >&2
        return 2
    fi
    local _p="$1"
    if [[ ! -e "$_p" ]]; then
        printf 'artifact.summarize: path does not exist: %s\n' "$_p" >&2
        return 1
    fi

    local _type
    if [[ -f "$_p" ]]; then
        _type="file"
    elif [[ -d "$_p" ]]; then
        _type="directory"
    else
        printf 'artifact.summarize: unsupported path type: %s\n' "$_p" >&2
        return 1
    fi

    local _name _size _sha _abs
    _name="$(basename "$_p")"
    _size="$(_artifact._size_bytes "$_p")"
    _sha="$(_artifact._sha256 "$_p")"
    _abs="$(_artifact._abs_path "$_p" || printf '%s' "$_p")"

    if ! command -v jq >/dev/null 2>&1; then
        printf 'artifact.summarize: jq is required\n' >&2
        return 3
    fi

    # KCOV_EXCL_START -- inline jq script body, not bash code
    jq -nc \
        --arg type "$_type" \
        --arg name "$_name" \
        --argjson size "${_size:-0}" \
        --arg sha    "${_sha:-}" \
        --arg path   "$_abs" \
        '{type: $type, name: $name, size_bytes: $size, sha256: $sha, path: $path}'
    # KCOV_EXCL_STOP
}
