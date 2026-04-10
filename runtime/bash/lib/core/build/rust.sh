#!/usr/bin/env bash
# @module build.rust
# @requires cargo
# @description Build Rust projects (cargo).

# Guard against double-sourcing
[[ -n "${_BRIK_CORE_BUILD_RUST_LOADED:-}" ]] && return 0
_BRIK_CORE_BUILD_RUST_LOADED=1

# Build a Rust project.
# Usage: build.rust.run <workspace> [--profile <dev|release>]
build.rust.run() {
    local workspace="$1"
    shift
    local profile=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --profile) profile="$2"; shift 2 ;;
            *) log.error "unknown option: $1"; return "$BRIK_EXIT_INVALID_INPUT" ;;
        esac
    done

    runtime.require_dir "$workspace" || return "$BRIK_EXIT_IO_FAILURE"

    if [[ ! -f "${workspace}/Cargo.toml" ]]; then
        log.error "no Cargo.toml found in workspace: $workspace"
        return "$BRIK_EXIT_IO_FAILURE"
    fi

    runtime.require_tool cargo || return "$BRIK_EXIT_MISSING_DEP"

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
