#!/usr/bin/env bash
# @module planning/plan_writer
# @requires jq, sha256sum
# @description Serializes a plan.compute stream into the canonical
#   plan.json format (schemas/plan/v1/plan.schema.json). Output is
#   deterministic: jq -S sorts keys, the dag.edges array is sorted by
#   compute, and no timestamps are written. fingerprint = sha256 of the
#   serialized object with .fingerprint set to "".

# Guard against double-sourcing.
[[ -n "${_BRIK_PLANNING_PLAN_WRITER_LOADED:-}" ]] && return 0
_BRIK_PLANNING_PLAN_WRITER_LOADED=1

# shellcheck source=plan.sh
. "${BASH_SOURCE[0]%/*}/plan.sh"
# shellcheck source=../pipeline/version-info.sh
. "${BASH_SOURCE[0]%/*}/../pipeline/version-info.sh"

# Read plan.compute stream from stdin, serialize to JSON on stdout.
# Returns non-zero on missing jq.
plan_writer.from_stream() {
    command -v jq >/dev/null 2>&1 || {
        printf '[plan_writer] jq required\n' >&2
        return "${BRIK_EXIT_MISSING_DEP:-69}"
    }

    local workspace="" mode="" context=""
    local source="none" from="" to=""
    local -a stage_rows=()

    local line
    while IFS= read -r line; do
        case "$line" in
            "# workspace="*)       workspace="${line#\# workspace=}" ;;
            "# mode="*)            mode="${line#\# mode=}" ;;
            "# context="*)         context="${line#\# context=}" ;;
            "# stack="*)           : ;;
            "# changes_source="*)  source="${line#\# changes_source=}" ;;
            "# changes_from="*)    from="${line#\# changes_from=}" ;;
            "# changes_to="*)      to="${line#\# changes_to=}" ;;
            "#"*)                  : ;;
            "")                    : ;;
            *)                     stage_rows+=("$line") ;;
        esac
    done

    # Build dag.edges array via plan.dag.edges. The stream itself does
    # not carry edge data; computing them once here keeps plan.compute
    # focused on per-stage decisions.
    local -a edge_rows=()
    local edge_line
    while IFS= read -r edge_line; do
        [[ -z "$edge_line" ]] && continue
        edge_rows+=("$edge_line")
    done < <(plan.dag.edges 2>/dev/null || true)

    # Build stage entries as one JSON object per row, aggregated into
    # an array. matched_globs is comma-separated in the stream; split
    # back to a JSON array. Empty string => empty array.
    local stages_json
    stages_json="$(printf '%s\n' "${stage_rows[@]}" | jq -R -s '
        [ split("\n") | .[] | select(length > 0) | split("\t") |
          {
            id:           .[0],
            decision:     .[1],
            reason:       .[2],
            gate:         { mode: .[3] },
            runner_class: .[4],
            function:     .[5],
            matched_globs: (if .[6] == "" or .[6] == null
                            then []
                            else (.[6] | split(",")) end)
          }
        ]' 2>/dev/null)"

    local edges_json
    edges_json="$(printf '%s\n' "${edge_rows[@]}" | jq -R -s '
        [ split("\n") | .[] | select(length > 0) | split("\t") |
          { from: .[0], to: .[1] }
        ]' 2>/dev/null)"

    # Empty arrays mean "no stages parsed" / "no edges resolved" - both
    # signal a malformed stream. Surface as exit 64 (invalid input)
    # rather than emit an invalid plan.json.
    if [[ -z "$stages_json" || "$stages_json" == "[]" ]]; then
        printf '[plan_writer] no stage records parsed from stream\n' >&2
        return "${BRIK_EXIT_INVALID_INPUT:-64}"
    fi

    local changes_obj
    if [[ "$source" == "none" ]]; then
        changes_obj='{"source":"none","files":[]}'
    else
        changes_obj="$(jq -nc --arg s "$source" --arg f "$from" --arg t "$to" \
            '{source:$s, from_ref:$f, to_ref:$t, files:[]}')"
    fi

    # Self-hash idiom: assemble with fingerprint="", hash the canonical
    # bytes, substitute the real fingerprint. Round-tripping the same
    # plan re-produces the same fingerprint.
    local body
    body="$(jq -nS \
        --arg sv "v1" \
        --arg bv "${BRIK_VERSION:-0.0.0}" \
        --arg ctx "$context" \
        --arg md  "$mode" \
        --arg ws  "$workspace" \
        --argjson stages "$stages_json" \
        --argjson edges  "$edges_json" \
        --argjson chg    "$changes_obj" \
        '{
            schemaVersion: $sv,
            brikVersion:   $bv,
            context:       $ctx,
            mode:          $md,
            workspace:     $ws,
            changes:       $chg,
            stages:        $stages,
            dag:           { edges: $edges },
            fingerprint:   ""
        }')"

    local fp
    fp="$(printf '%s' "$body" | sha256sum | cut -d' ' -f1)"

    printf '%s\n' "$body" | jq -S --arg fp "$fp" '.fingerprint = $fp'
}

# Convenience: run plan.compute with the given args, pipe through the
# serializer, optionally write to --out. Used by lib/cli/plan.sh.
#
# Usage: plan_writer.write [--out <path>] [-- <plan.compute args>...]
plan_writer.write() {
    local out=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --out) out="$2"; shift 2 ;;
            --)    shift; break ;;
            *)     break ;;
        esac
    done

    local tmp
    tmp="$(mktemp -t brik-plan-stream.XXXXXX)"
    if ! plan.compute "$@" >"$tmp"; then
        rm -f "$tmp"
        return "${BRIK_EXIT_INVALID_INPUT:-64}"
    fi

    local json
    if ! json="$(plan_writer.from_stream <"$tmp")"; then
        rm -f "$tmp"
        return "${BRIK_EXIT_INVALID_INPUT:-64}"
    fi
    rm -f "$tmp"

    if [[ -n "$out" ]]; then
        mkdir -p "$(dirname "$out")"
        printf '%s\n' "$json" >"$out"
    else
        printf '%s\n' "$json"
    fi
}
