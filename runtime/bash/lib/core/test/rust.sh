#!/usr/bin/env bash
# @module test.rust
# @requires cargo
# @description Test commands for Rust projects.

# Guard against double-sourcing
[[ -n "${_BRIK_CORE_TEST_RUST_LOADED:-}" ]] && return 0
_BRIK_CORE_TEST_RUST_LOADED=1

# Build the test command for a given Rust framework.
# Usage: test.rust.cmd <framework> <workspace> <report_dir>
# Frameworks: cargo
test.rust.cmd() {
    local framework="$1"
    local cmd=""

    case "$framework" in
        cargo)
            cmd="cargo test"
            ;;
        *)
            log.error "unsupported Rust test framework: $framework"
            return 7
            ;;
    esac

    printf '%s' "$cmd"
    return 0
}

# Auto-detect and return the test command for a Rust workspace.
# Usage: test.rust.run_cmd <workspace> <report_dir>
test.rust.run_cmd() {
    printf '%s' "cargo test"
}
