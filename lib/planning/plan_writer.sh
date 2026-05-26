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
        return "$BRIK_EXIT_MISSING_DEP"
    }

    local workspace="" mode="" context=""
    local source="none" from="" to=""
    local release_profile="none" release_version="0.0.0" is_candidate="0"
    local -a stage_rows=()
    local -a changes_files_rows=()

    local line
    while IFS= read -r line; do
        case "$line" in
            "# workspace="*)         workspace="${line#\# workspace=}" ;;
            "# mode="*)              mode="${line#\# mode=}" ;;
            "# context="*)           context="${line#\# context=}" ;;
            "# stack="*)             : ;;
            "# changes_source="*)    source="${line#\# changes_source=}" ;;
            "# changes_from="*)      from="${line#\# changes_from=}" ;;
            "# changes_to="*)        to="${line#\# changes_to=}" ;;
            "# changes_file="*)      changes_files_rows+=("${line#\# changes_file=}") ;;
            "# release_profile="*)   release_profile="${line#\# release_profile=}" ;;
            "# release_version="*)   release_version="${line#\# release_version=}" ;;
            "# is_candidate="*)      is_candidate="${line#\# is_candidate=}" ;;
            "#"*)                    : ;;
            "")                      : ;;
            *)                       stage_rows+=("$line") ;;
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
        # KCOV_EXCL_START -- inline jq script body, not bash code
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
        ]
        # KCOV_EXCL_STOP
        ' 2>/dev/null)"

    local edges_json
    edges_json="$(printf '%s\n' "${edge_rows[@]}" | jq -R -s '
        # KCOV_EXCL_START -- inline jq script body, not bash code
        [ split("\n") | .[] | select(length > 0) | split("\t") |
          { from: .[0], to: .[1] }
        ]
        # KCOV_EXCL_STOP
        ' 2>/dev/null)"

    # Empty arrays mean "no stages parsed" / "no edges resolved" - both
    # signal a malformed stream. Surface as exit 64 (invalid input)
    # rather than emit an invalid plan.json.
    if [[ -z "$stages_json" || "$stages_json" == "[]" ]]; then
        printf '[plan_writer] no stage records parsed from stream\n' >&2
        return "$BRIK_EXIT_INVALID_INPUT"
    fi

    # changes.files: jq -R -s split correctly handles the empty array
    # case (0 rows fed in). Path newlines are not supported (Brik
    # workspaces are source repositories where this is effectively
    # guaranteed; plan.compute strips NULs but keeps content as-is).
    local files_array
    files_array="$(printf '%s\n' "${changes_files_rows[@]:-}" \
        | jq -R -s 'split("\n") | map(select(length > 0))')"

    local changes_obj
    if [[ "$source" == "none" ]]; then
        changes_obj="$(jq -nc --argjson f "$files_array" \
            '{source:"none", files:$f}')"
    else
        changes_obj="$(jq -nc --arg s "$source" --arg fr "$from" --arg t "$to" --argjson f "$files_array" \
            '{source:$s, from_ref:$fr, to_ref:$t, files:$f}')"
    fi

    # Phase 9.A release block. is_candidate is "0"/"1" in the stream so
    # it survives the TAB-delimited transport; jq normalizes it back to
    # a JSON boolean here so the schema enforces type=boolean.
    local release_obj
    release_obj="$(jq -nc \
        --arg p  "$release_profile" \
        --arg v  "$release_version" \
        --argjson c "$([[ "$is_candidate" == "1" ]] && printf 'true' || printf 'false')" \
        '{profile:$p, version:$v, is_candidate:$c}')"

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
        --argjson stages  "$stages_json" \
        --argjson edges   "$edges_json" \
        --argjson chg     "$changes_obj" \
        --argjson release "$release_obj" \
        '
        # KCOV_EXCL_START -- inline jq object literal, not bash code
        {
            schemaVersion: $sv,
            brikVersion:   $bv,
            context:       $ctx,
            mode:          $md,
            workspace:     $ws,
            changes:       $chg,
            release:       $release,
            stages:        $stages,
            dag:           { edges: $edges },
            fingerprint:   ""
        }
        # KCOV_EXCL_STOP
        ')"

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
        return "$BRIK_EXIT_INVALID_INPUT"
    fi

    local json
    if ! json="$(plan_writer.from_stream <"$tmp")"; then
        rm -f "$tmp"
        return "$BRIK_EXIT_INVALID_INPUT"
    fi
    rm -f "$tmp"

    if [[ -n "$out" ]]; then
        mkdir -p "$(dirname "$out")"
        printf '%s\n' "$json" >"$out"
    else
        printf '%s\n' "$json"
    fi
}
