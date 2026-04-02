#!/usr/bin/env bash
# @module config.rust
# @description Rust stack defaults and version export.
#
# Loaded via: brik.use config.rust

# Guard against double-sourcing
[[ -n "${_BRIK_CORE_CONFIG_RUST_LOADED:-}" ]] && return 0
_BRIK_CORE_CONFIG_RUST_LOADED=1

# Return the default value for a Rust setting.
# Usage: config.rust.default <setting>
config.rust.default() {
    local setting="$1"

    case "$setting" in
        build_command)  printf 'cargo build' ;;
        test_framework) printf 'cargo test' ;;
        lint_tool)      printf 'clippy' ;;
        format_tool)    printf 'rustfmt' ;;
        *) return 1 ;;
    esac
    return 0
}

# Export Rust version pinning.
# Sets: BRIK_BUILD_RUST_VERSION (if configured)
config.rust.export_build_vars() {
    local rust_version
    rust_version="$(config.get '.build.rust_version' '')"
    [[ -n "$rust_version" ]] && export BRIK_BUILD_RUST_VERSION="$rust_version"
    return 0
}
