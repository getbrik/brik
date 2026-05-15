#!/usr/bin/env bash
# @module artifacts
# @description Resolve paths under the canonical CI evidence tree
#   `${BRIK_WORKSPACE:-.}/brik-artifacts/<stage>/`. Single source of truth
#   for artifact layout. Side-effecting variants (`dir`, `path`) ensure
#   parent directories exist; `root` is a pure query.

[[ -n "${_BRIK_TRANSVERSE_ARTIFACTS_LOADED:-}" ]] && return 0
_BRIK_TRANSVERSE_ARTIFACTS_LOADED=1

# Echo the artifact tree root path. Pure: never creates the directory.
# Usage: brik.artifacts.root
brik.artifacts.root() {
    printf '%s/brik-artifacts' "${BRIK_WORKSPACE:-.}"
}

# Echo the per-stage artifact directory and ensure it exists.
# Usage: brik.artifacts.dir <stage>
brik.artifacts.dir() {
    if [[ $# -lt 1 || -z "${1:-}" ]]; then
        printf 'brik.artifacts.dir: missing stage argument\n' >&2
        return 2
    fi
    local _stage="$1"
    local _dir="${BRIK_WORKSPACE:-.}/brik-artifacts/${_stage}"
    mkdir -p "$_dir" || return 1
    printf '%s' "$_dir"
}

# Echo a full artifact file path under <stage>/<relpath> and ensure the
# parent directory exists. Does not create the file itself.
# Usage: brik.artifacts.path <stage> <relpath>
brik.artifacts.path() {
    if [[ $# -lt 2 || -z "${1:-}" || -z "${2:-}" ]]; then
        printf 'brik.artifacts.path: requires <stage> and <relpath>\n' >&2
        return 2
    fi
    local _stage="$1"
    local _rel="$2"
    local _full="${BRIK_WORKSPACE:-.}/brik-artifacts/${_stage}/${_rel}"
    mkdir -p "$(dirname "$_full")" || return 1
    printf '%s' "$_full"
}

# ---------------------------------------------------------------------------
# Logs tree (.brik-logs/) - operational data root
# ---------------------------------------------------------------------------
# Mirror of brik.artifacts.* for the operational data tree
# `${BRIK_WORKSPACE:-.}/.brik-logs/`. Holds forensic outputs that are not
# part of the public API (per-stage logs, env file, lock files, policy cache,
# aggregate-report backend before notify copies it). Same depth rule (max
# 2 levels), same API shape.

# Echo the logs tree root path. Pure: never creates the directory.
# Usage: brik.logs.root
brik.logs.root() {
    printf '%s/.brik-logs' "${BRIK_WORKSPACE:-.}"
}

# Echo the per-stage logs directory and ensure it exists.
# Usage: brik.logs.dir <stage>
brik.logs.dir() {
    if [[ $# -lt 1 || -z "${1:-}" ]]; then
        printf 'brik.logs.dir: missing stage argument\n' >&2
        return 2
    fi
    local _stage="$1"
    local _dir="${BRIK_WORKSPACE:-.}/.brik-logs/${_stage}"
    mkdir -p "$_dir" || return 1
    printf '%s' "$_dir"
}

# Echo a full path under .brik-logs/<relpath> and ensure the parent
# directory exists. Does not create the file itself.
# Usage: brik.logs.path <relpath>
brik.logs.path() {
    if [[ $# -lt 1 || -z "${1:-}" ]]; then
        printf 'brik.logs.path: missing relpath argument\n' >&2
        return 2
    fi
    local _rel="$1"
    local _full="${BRIK_WORKSPACE:-.}/.brik-logs/${_rel}"
    mkdir -p "$(dirname "$_full")" || return 1
    printf '%s' "$_full"
}

# _brik.log_dir._resolve lives in lib/pipeline/logging.sh so that every
# runtime module (context, pipeline-env, report, stage, summary, ...) can
# call it without an extra source line. Use it whenever you need to read
# the canonical log dir; do not re-implement the precedence inline.
