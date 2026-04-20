#!/usr/bin/env bash
# @module transverse.csv
# @description CSV iteration helper. Reusable foreach over comma-separated values.

# Guard against double-sourcing.
[[ -n "${_BRIK_MODULE_CSV_LOADED:-}" ]] && return 0
_BRIK_MODULE_CSV_LOADED=1

# transverse.csv.foreach - iterate a CSV string, invoking a function per item.
# Items are trimmed of surrounding whitespace; internal whitespace is preserved.
# Empty items (including those produced by adjacent commas) are skipped.
# If the callback returns non-zero, iteration continues; the final return code
# is the LAST non-zero callback code. Callers that need to know "any failure"
# can treat any non-zero return as failure without distinguishing which one.
# Usage: transverse.csv.foreach "a,b,c" my_fn [extra_args...]
transverse.csv.foreach() {
    local csv="$1"
    local fn="$2"
    shift 2

    [[ -z "$csv" ]] && return 0

    local _csv_items=()
    local _csv_last_status=0
    local item trimmed

    IFS=',' read -ra _csv_items <<< "$csv"

    for item in "${_csv_items[@]}"; do
        trimmed="${item#"${item%%[![:space:]]*}"}"
        trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
        [[ -z "$trimmed" ]] && continue
        "$fn" "$trimmed" "$@" || _csv_last_status=$?
    done

    return "$_csv_last_status"
}
