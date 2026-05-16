#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# @module transverse.binary_path
# @description Resolve an external CLI binary uniformly across the three
#   layers Brik supports:
#
#     1. project   : <BRIK_WORKSPACE>/node_modules/.bin/<tool>
#     2. image     : command -v <tool> ($PATH)
#     3. bundled   : <BRIK_HOME>/tools/<tool>
#     4. missing   : not found anywhere
#
# Today this priority is inlined in every lint/test/format stage. The
# resolver consolidates the chain so business.evaluate (SC16) can read
# `provenance` directly and emit `tech.kind=missing-tool` with
# `fix_classification=has_fix` instead of every stage re-implementing the
# detection.
#
# Public API:
#   binary_path.resolve <tool>
#     -> stdout JSON {"path":"...","version":"...","provenance":"..."}
#        rc=0 except for empty tool name (rc=2)
#   binary_path.is_available <tool>
#     -> stdout "true"|"false", rc=0 except for empty tool name (rc=2)
#
# Version detection is best-effort. The resolver runs `<path> --version`
# (then `-v` as a fallback), strips ANSI sequences, takes the first line,
# and keeps the first dotted numeric token (with optional leading `v`).
# On silence or failure the version is reported as "unknown".

# Guard against double-sourcing
[[ -n "${_BRIK_BINARY_PATH_LOADED:-}" ]] && return 0
_BRIK_BINARY_PATH_LOADED=1

# JSON-escape a string for embedding inside a "..." literal.
_binary_path._json_escape() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    printf '%s' "$s"
}

# Strip ANSI escape sequences from stdin.
_binary_path._strip_ansi() {
    sed -E $'s/\x1b\\[[0-9;]*[A-Za-z]//g'
}

# Print a best-effort version string for the given executable.
# Falls back to "unknown" when the tool is silent or fails both probes.
_binary_path._probe_version() {
    local path="$1"
    [[ -x "$path" ]] || { printf 'unknown'; return; }

    local raw
    raw="$("$path" --version 2>/dev/null | head -1)" || raw=""
    if [[ -z "$raw" ]]; then
        raw="$("$path" -v 2>/dev/null | head -1)" || raw=""
    fi
    if [[ -z "$raw" ]]; then
        printf 'unknown'
        return
    fi

    raw="$(printf '%s' "$raw" | _binary_path._strip_ansi)"

    # Extract the first dotted-numeric token, allow optional leading 'v'.
    local token
    token="$(printf '%s' "$raw" | grep -oE 'v?[0-9]+\.[0-9]+(\.[0-9]+)?(\.[0-9]+)?' | head -1)"
    token="${token#v}"
    if [[ -z "$token" ]]; then
        printf 'unknown'
    else
        printf '%s' "$token"
    fi
}

# Emit the canonical JSON envelope.
_binary_path._emit() {
    local path="$1" version="$2" provenance="$3"
    local p v
    p="$(_binary_path._json_escape "$path")"
    v="$(_binary_path._json_escape "$version")"
    printf '{"path":"%s","version":"%s","provenance":"%s"}' "$p" "$v" "$provenance"
}

# binary_path.resolve <tool>
# Walk project -> image -> bundled and emit the resolved descriptor.
binary_path.resolve() {
    local tool="${1:-}"
    if [[ -z "$tool" ]]; then
        printf 'binary_path.resolve: tool name is required\n' >&2
        return 2
    fi

    local workspace="${BRIK_WORKSPACE:-$(pwd)}"
    local project_bin="${workspace}/node_modules/.bin/${tool}"
    if [[ -x "$project_bin" ]]; then
        local version
        version="$(_binary_path._probe_version "$project_bin")"
        _binary_path._emit "$project_bin" "$version" "project"
        return 0
    fi

    local path_bin
    path_bin="$(command -v "$tool" 2>/dev/null || true)"
    if [[ -n "$path_bin" && -x "$path_bin" ]]; then
        local version
        version="$(_binary_path._probe_version "$path_bin")"
        _binary_path._emit "$path_bin" "$version" "image"
        return 0
    fi

    local bundled_bin="${BRIK_HOME:-}/tools/${tool}"
    if [[ -n "${BRIK_HOME:-}" && -x "$bundled_bin" ]]; then
        local version
        version="$(_binary_path._probe_version "$bundled_bin")"
        _binary_path._emit "$bundled_bin" "$version" "bundled"
        return 0
    fi

    _binary_path._emit "" "unknown" "missing"
    return 0
}

# binary_path.is_available <tool>
# Boolean shortcut over resolve: anything other than "missing" is true.
binary_path.is_available() {
    local tool="${1:-}"
    if [[ -z "$tool" ]]; then
        printf 'binary_path.is_available: tool name is required\n' >&2
        return 2
    fi

    local workspace="${BRIK_WORKSPACE:-$(pwd)}"
    if [[ -x "${workspace}/node_modules/.bin/${tool}" ]]; then
        printf 'true'
        return 0
    fi
    if command -v "$tool" >/dev/null 2>&1; then
        printf 'true'
        return 0
    fi
    if [[ -n "${BRIK_HOME:-}" && -x "${BRIK_HOME}/tools/${tool}" ]]; then
        printf 'true'
        return 0
    fi
    printf 'false'
    return 0
}
