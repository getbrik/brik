#!/usr/bin/env bash
# @module stacks/rust
# @requires cargo
# @description Build Rust projects (cargo).

# Guard against double-sourcing
[[ -n "${_BRIK_STACKS_RUST_LOADED:-}" ]] && return 0
_BRIK_STACKS_RUST_LOADED=1

# Build a Rust project.
# Usage: stacks.rust.build <workspace> [--profile <dev|release>]
stacks.rust.build() {
    local workspace="$1"
    shift
    local profile=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --profile) profile="$2"; shift 2 ;;
            *) log.error "unknown option: $1"; return "$BRIK_EXIT_INVALID_INPUT" ;;
        esac
    done

    pipeline.require_dir "$workspace" || return "$BRIK_EXIT_IO_FAILURE"

    if [[ ! -f "${workspace}/Cargo.toml" ]]; then
        log.error "no Cargo.toml found in workspace: $workspace"
        return "$BRIK_EXIT_IO_FAILURE"
    fi

    pipeline.require_tool cargo || return "$BRIK_EXIT_MISSING_DEP"

    log.info "building with cargo"

    local cargo_args="build"
    if [[ "$profile" == "release" ]]; then
        cargo_args="build --release"
    fi

    # $cargo_args intentionally word-splits
    # shellcheck disable=SC2086
    (cd "$workspace" && cargo $cargo_args) || {
        log.error "build failed"
        return "$BRIK_EXIT_EXTERNAL_FAIL"
    }

    log.info "build completed successfully"
    return 0
}

# Build the test command for a given Rust framework.
# Usage: stacks.rust.test_cmd <framework> <workspace> <report_dir>
# Frameworks: cargo
stacks.rust.test_cmd() {
    local framework="$1"
    local cmd=""

    case "$framework" in
        cargo)
            cmd="cargo test"
            ;;
        *)
            log.error "unsupported Rust test framework: $framework"
            return "$BRIK_EXIT_CONFIG_ERROR"
            ;;
    esac

    printf '%s' "$cmd"
    return 0
}

# Auto-detect and return the test command for a Rust workspace.
# Usage: stacks.rust.test <workspace> <report_dir>
stacks.rust.test() {
    printf '%s' "cargo test"
}
