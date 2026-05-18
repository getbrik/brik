#!/usr/bin/env bash
# @module artifact
# @requires sha256sum, tar, stat, jq
# @description Summarize a build artifact (file or directory) into a JSON
#   object recordable under a stage's business section.

# Guard against double-sourcing.
[[ -n "${_BRIK_TRANSVERSE_ARTIFACT_LOADED:-}" ]] && return 0
_BRIK_TRANSVERSE_ARTIFACT_LOADED=1

# Source the registry to read stack-specific artifact patterns from manifests
# (D.2.6 of the architecture refactor chantier). The registry is the source
# of truth for spec.artifacts.{output_dirs, patterns}.
# shellcheck source=../registry/registry.sh
. "${BASH_SOURCE[0]%/*}/../registry/registry.sh"

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

# Find the most representative single file inside a directory.
# Strategy: stack-aware extension priority. Java picks *.jar > *.war > *.ear,
# Python picks *.whl > *.tar.gz, etc. - the file's individual size is
# incidental (a 2 KB JAR can sit next to MBs of build intermediates under
# target/classes/). For rust (binaries have no extension on Unix) the
# fallback is the largest file > 1 byte. For unknown stacks no main_file
# is reported - the directory size is what the consumer gets, which keeps
# the contract for non-Brik-managed paths.
#
# Usage: _artifact._find_main_file <dir> [<stack>]
# Prints the file's path relative to <dir>, or nothing.
_artifact._find_main_file() {
    local _dir="$1"
    local _stack="${2:-${BRIK_BUILD_STACK:-auto}}"
    local _project="${3:-${BRIK_PROJECT_NAME:-}}"
    [[ -d "$_dir" ]] || return 0

    # Patterns sourced from the stack manifest (spec.artifacts.patterns).
    # Adding a new stack with artifact glob patterns means publishing a
    # manifest, no code change here. Falls back to an empty array for stacks
    # with no patterns (rust binaries on Unix) or unknown stacks.
    local -a _patterns=()
    if declare -f registry.stack.artifact_patterns >/dev/null 2>&1; then
        mapfile -t _patterns < <(registry.stack.artifact_patterns "$_stack" 2>/dev/null || true)
    fi

    local _pat _f

    # Project-name-prefixed match first. Some build tools wheel deps into
    # the same dir as the project (e.g. 'pip wheel . -w dist/' produces
    # both python_complete-*.whl AND pytest-*.whl). Without this filter
    # find -head would return whichever happens to come first in the
    # directory entry order. Try kebab and snake-case forms of the
    # project name to cover both filename conventions.
    if [[ -n "$_project" && ${#_patterns[@]} -gt 0 ]]; then
        local _proj_snake="${_project//-/_}"
        local _name
        for _pat in "${_patterns[@]}"; do
            local _ext="${_pat#\*}"
            for _name in "$_project" "$_proj_snake"; do
                _f="$(find "$_dir" -maxdepth 3 -type f -name "${_name}${_ext}" -size +1c 2>/dev/null | head -1)"
                [[ -n "$_f" ]] || _f="$(find "$_dir" -maxdepth 3 -type f -name "${_name}-*${_ext}" -size +1c 2>/dev/null | head -1)"
                if [[ -n "$_f" ]]; then
                    printf '%s' "${_f#"${_dir}"/}"
                    return 0
                fi
            done
        done
    fi

    # Bare extension match: first file with the right extension wins.
    for _pat in "${_patterns[@]}"; do
        _f="$(find "$_dir" -maxdepth 3 -type f -name "$_pat" -size +1c 2>/dev/null | head -1)"
        if [[ -n "$_f" ]]; then
            printf '%s' "${_f#"${_dir}"/}"
            return 0
        fi
    done

    # Rust binary fallback (no extension on Unix) - largest file wins.
    if [[ "$_stack" == "rust" ]]; then
        local _best="" _best_size=0 _sz
        while IFS= read -r -d '' _f; do
            _sz="$(_artifact._size_bytes "$_f" 2>/dev/null)" || continue
            [[ "$_sz" =~ ^[0-9]+$ ]] || continue
            (( _sz <= 1 )) && continue
            if (( _sz > _best_size )); then
                _best_size=$_sz
                _best="$_f"
            fi
        done < <(find "$_dir" -maxdepth 3 -type f -print0 2>/dev/null)
        if [[ -n "$_best" ]]; then
            printf '%s' "${_best#"${_dir}"/}"
            return 0
        fi
    fi

    # Single-file-directory fallback: when a directory holds exactly one
    # non-empty regular file at top level, treat it as the main artifact.
    # Catches bundle outputs like dist/index.js for Node TS projects that
    # don't go through 'npm pack'. Skipped when the dir has 0 or 2+ files
    # to avoid mis-identification in multi-output builds.
    local _count
    _count=$(find "$_dir" -maxdepth 1 -type f -size +1c 2>/dev/null | wc -l | tr -d ' ')
    if [[ "$_count" == "1" ]]; then
        _f="$(find "$_dir" -maxdepth 1 -type f -size +1c 2>/dev/null | head -1)"
        if [[ -n "$_f" ]]; then
            printf '%s' "${_f#"${_dir}"/}"
            return 0
        fi
    fi
    return 0
}

# Summarize an artifact path into a JSON object.
# Usage: artifact.summarize <path> [<stack>]
# Prints {type, name, size_bytes, sha256, path[, main_file]} to stdout.
# main_file is added when path is a directory and a stack-aware extension
# match (or rust binary heuristic) identified a representative file inside
# it - in that case size_bytes and sha256 describe THAT file, not the
# directory total (which would include build intermediates).
# Returns non-zero on missing path or missing required tools.
artifact.summarize() {
    if [[ $# -lt 1 ]]; then
        printf 'artifact.summarize: missing path argument\n' >&2
        return 2
    fi
    local _p="$1"
    local _stack="${2:-${BRIK_BUILD_STACK:-auto}}"
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

    local _name _size _sha _abs _main_file=""
    _name="$(basename "$_p")"
    _abs="$(_artifact._abs_path "$_p" || printf '%s' "$_p")"
    if [[ "$_type" == "directory" ]]; then
        _main_file="$(_artifact._find_main_file "$_p" "$_stack" "${BRIK_PROJECT_NAME:-}" 2>/dev/null)"
    fi
    # When a representative file was identified inside the directory, size
    # and sha describe THAT file - the directory total would include build
    # intermediates (target/classes/, pom.xml, .pyc files, ...) that are not
    # part of the shipped artifact. Without a main file, fall back to the
    # whole directory.
    if [[ -n "$_main_file" && -f "$_p/$_main_file" ]]; then
        _size="$(_artifact._size_bytes "$_p/$_main_file")"
        _sha="$(_artifact._sha256 "$_p/$_main_file")"
    else
        _size="$(_artifact._size_bytes "$_p")"
        _sha="$(_artifact._sha256 "$_p")"
    fi

    if ! command -v jq >/dev/null 2>&1; then
        printf 'artifact.summarize: jq is required\n' >&2
        return 3
    fi

    # KCOV_EXCL_START -- inline jq script body, not bash code
    jq -nc \
        --arg type      "$_type" \
        --arg name      "$_name" \
        --argjson size  "${_size:-0}" \
        --arg sha       "${_sha:-}" \
        --arg path      "$_abs" \
        --arg main_file "$_main_file" \
        '{type: $type, name: $name, size_bytes: $size, sha256: $sha, path: $path}
         + ( if $main_file != "" then { main_file: $main_file } else {} end )'
    # KCOV_EXCL_STOP
}
