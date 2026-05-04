#!/usr/bin/env bash
# @module junit
# @requires jq
# @description Parse JUnit XML test reports into a normalized JSON object
#   {total, passed, failed, skipped, duration_ms}. Aggregates across
#   <testsuites> with multiple <testsuite> children, and supports the
#   legacy bare-<testsuite> root shape.

# Guard against double-sourcing.
[[ -n "${_BRIK_TRANSVERSE_JUNIT_LOADED:-}" ]] && return 0
_BRIK_TRANSVERSE_JUNIT_LOADED=1

# Sum a numeric attribute across all <testsuite> elements in the file.
# Args: <xml_file> <attr_name>
# Prints the integer sum to stdout. Missing attributes count as 0.
_junit._sum_attr() {
    local _file="$1" _attr="$2"
    grep -oE "<testsuite[^>]*\\b${_attr}=\"[^\"]+\"" "$_file" 2>/dev/null \
      | grep -oE "${_attr}=\"[^\"]+\"" \
      | sed -E "s/${_attr}=\"([^\"]+)\"/\\1/" \
      | awk 'BEGIN{s=0} {s+=$1+0} END{print s}'
}

# Sum the float "time" attribute across all <testsuite> elements,
# converting each to integer milliseconds before summing to avoid
# floating-point drift.
_junit._sum_duration_ms() {
    local _file="$1"
    grep -oE '<testsuite[^>]*\btime="[^"]+"' "$_file" 2>/dev/null \
      | grep -oE 'time="[^"]+"' \
      | sed -E 's/time="([^"]+)"/\1/' \
      | awk 'BEGIN{s=0}
             {
               t=$1+0
               ms=int(t*1000 + 0.5)
               s+=ms
             }
             END{print s}'
}

# Parse a JUnit XML report into a normalized JSON object.
# Usage: junit.parse <xml_file>
# Prints {total, passed, failed, skipped, duration_ms} on stdout.
# Returns non-zero on missing file or missing jq.
junit.parse() {
    if [[ $# -lt 1 ]]; then
        printf 'junit.parse: missing xml file argument\n' >&2
        return 2
    fi
    local _file="$1"
    if [[ ! -f "$_file" ]]; then
        printf 'junit.parse: file does not exist: %s\n' "$_file" >&2
        return 1
    fi
    if ! command -v jq >/dev/null 2>&1; then
        printf 'junit.parse: jq is required\n' >&2
        return 3
    fi

    local _total _failures _errors _skipped _ms _failed _passed
    _total="$(_junit._sum_attr "$_file" "tests")"
    _failures="$(_junit._sum_attr "$_file" "failures")"
    _errors="$(_junit._sum_attr "$_file" "errors")"
    _skipped="$(_junit._sum_attr "$_file" "skipped")"
    _ms="$(_junit._sum_duration_ms "$_file")"

    : "${_total:=0}" "${_failures:=0}" "${_errors:=0}" "${_skipped:=0}" "${_ms:=0}"

    _failed=$((_failures + _errors))
    _passed=$((_total - _failed - _skipped))
    [[ "$_passed" -lt 0 ]] && _passed=0

    jq -nc \
        --argjson total "$_total" \
        --argjson passed "$_passed" \
        --argjson failed "$_failed" \
        --argjson skipped "$_skipped" \
        --argjson duration_ms "$_ms" \
        '{total: $total, passed: $passed, failed: $failed, skipped: $skipped, duration_ms: $duration_ms}'
}
