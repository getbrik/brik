#!/usr/bin/env bash
# @module transverse.findings.ingest
# @requires jq, transverse.sarif
# @description Ingest stage of the findings pipeline: validate a tool's
#   SARIF (from_sarif) and convert a non-SARIF tool output to SARIF via a
#   named converter (from_json). Split out of lib/transverse/findings.sh;
#   loaded by the findings.sh facade.

[[ -n "${_BRIK_MODULE_TRANSVERSE_FINDINGS_INGEST_LOADED:-}" ]] && return 0
_BRIK_MODULE_TRANSVERSE_FINDINGS_INGEST_LOADED=1

# shellcheck source=../sarif.sh
[[ -z "${_BRIK_TRANSVERSE_SARIF_LOADED:-}" ]] && [[ -f "${BASH_SOURCE[0]%/*}/../sarif.sh" ]] && . "${BASH_SOURCE[0]%/*}/../sarif.sh"

# Validate a tool's SARIF report. Entry point of the ingest stage of the
# pipeline; downstream callers (apply_policy, aggregate) assume the file
# has already been vetted.
#
# Args:
#   $1 stage     -- stage producing the report (e.g. sast, container_scan).
#   $2 sarif_path -- absolute or workspace-relative path to the SARIF file.
#
# Returns:
#   0                          on a structurally valid SARIF 2.1.0.
#   BRIK_EXIT_INVALID_INPUT(2) on missing or empty arguments.
#   BRIK_EXIT_IO_FAILURE(6)    when the file does not exist.
#   BRIK_EXIT_CONFIG_ERROR(7)  when the file is not a valid SARIF document.
#   BRIK_EXIT_MISSING_DEP(3)   when transverse.sarif is unavailable.
findings.from_sarif() {
    if [[ $# -lt 2 ]]; then
        printf 'findings.from_sarif: missing arguments (expected: stage sarif_path)\n' >&2
        return "$BRIK_EXIT_INVALID_INPUT"
    fi
    local stage="$1" sarif_path="$2"
    if [[ -z "$stage" ]]; then
        printf 'findings.from_sarif: stage must not be empty\n' >&2
        return "$BRIK_EXIT_INVALID_INPUT"
    fi
    if [[ ! -f "$sarif_path" ]]; then
        printf 'findings.from_sarif: SARIF file not found: %s\n' "$sarif_path" >&2
        return "$BRIK_EXIT_IO_FAILURE"
    fi
    if ! declare -f sarif.is_valid >/dev/null 2>&1; then
        printf 'findings.from_sarif: transverse.sarif module not loaded\n' >&2
        return "$BRIK_EXIT_MISSING_DEP"
    fi
    if ! sarif.is_valid "$sarif_path"; then
        printf 'findings.from_sarif: invalid SARIF document: %s\n' "$sarif_path" >&2
        return "$BRIK_EXIT_CONFIG_ERROR"
    fi
    return 0
}

# Convert a non-SARIF tool output to SARIF via a named converter. Each
# tool ships its own jq/xq pipeline under transverse/findings/converters/
# and exposes findings.converters.<tool>.to_sarif <input> <output>. The
# function name keeps "from_json" for backward continuity even though
# some converters (e.g. junit) read XML -- "JSON" stands for the family
# of structured tool outputs, not the wire format.
#
# The dispatcher:
#   1. Validates arguments (tool, input file, output dir creatable).
#   2. Sources the per-tool converter from a path relative to this file
#      so unit tests can Include it without booting brik.use.
#   3. Calls findings.converters.<tool>.to_sarif.
#   4. Validates the resulting SARIF via findings.from_sarif so a buggy
#      converter is caught before downstream policy gating.
#
# Args:
#   $1 tool   -- converter name (ruff, bandit, junit, dockle, ...).
#   $2 input  -- absolute or workspace-relative path to the native output.
#   $3 output -- target SARIF path (parent directories created on demand).
findings.from_json() {
    if [[ $# -lt 3 ]]; then
        printf 'findings.from_json: missing arguments (expected: tool input output)\n' >&2
        return "$BRIK_EXIT_INVALID_INPUT"
    fi
    local tool="$1" input="$2" output="$3"

    if [[ -z "$tool" ]]; then
        printf 'findings.from_json: tool must not be empty\n' >&2
        return "$BRIK_EXIT_INVALID_INPUT"
    fi
    # Tool names interpolate into a path and a function name; constrain to
    # alnum + underscore to keep the dispatcher safe against directory
    # traversal (e.g. "../../sarif") even when tool is supplied dynamically.
    if [[ ! "$tool" =~ ^[A-Za-z][A-Za-z0-9_]*$ ]]; then
        printf 'findings.from_json: invalid tool name (expected ^[A-Za-z][A-Za-z0-9_]*$): %s\n' "$tool" >&2
        return "$BRIK_EXIT_INVALID_INPUT"
    fi
    if [[ ! -f "$input" ]]; then
        printf 'findings.from_json: input not found: %s\n' "$input" >&2
        return "$BRIK_EXIT_IO_FAILURE"
    fi

    local converter_path="${BASH_SOURCE[0]%/*}/converters/${tool}.sh"
    if [[ ! -f "$converter_path" ]]; then
        printf 'findings.from_json: no converter registered for tool %s (expected %s)\n' \
            "$tool" "$converter_path" >&2
        return "$BRIK_EXIT_CONFIG_ERROR"
    fi

    # shellcheck source=/dev/null
    . "$converter_path" || {
        printf 'findings.from_json: failed to source converter %s\n' "$converter_path" >&2
        return "$BRIK_EXIT_FAILURE"
    }

    local fn="findings.converters.${tool}.to_sarif"
    if ! declare -f "$fn" >/dev/null 2>&1; then
        printf 'findings.from_json: converter module did not define %s\n' "$fn" >&2
        return "$BRIK_EXIT_CONFIG_ERROR"
    fi

    local out_dir
    out_dir="$(dirname "$output")"
    mkdir -p "$out_dir" || {
        printf 'findings.from_json: cannot create output directory: %s\n' "$out_dir" >&2
        return "$BRIK_EXIT_IO_FAILURE"
    }

    "$fn" "$input" "$output" || {
        printf 'findings.from_json: converter failed for tool %s\n' "$tool" >&2
        return "$BRIK_EXIT_FAILURE"
    }

    findings.from_sarif "$tool" "$output"
}
