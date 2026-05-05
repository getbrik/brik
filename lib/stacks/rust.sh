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
    local reports_on="${BRIK_TEST_REPORTS_ENABLED:-false}"

    case "$framework" in
        cargo)
            cmd="cargo test"
            if [[ "$reports_on" == "true" ]]; then
                local cov_dir="${BRIK_TEST_COVERAGE_DIR:-brik-artifacts/test/coverage}"
                local has_nextest=0 has_llvm_cov=0
                command -v cargo-nextest >/dev/null 2>&1 && has_nextest=1
                command -v cargo-llvm-cov >/dev/null 2>&1 && has_llvm_cov=1

                if (( has_llvm_cov && has_nextest )); then
                    # llvm-cov delegates execution to nextest: produces
                    # cobertura coverage at ${cov_dir}/coverage.xml plus
                    # JUnit (the latter via the project's nextest.toml ci profile).
                    # Cobertura is the format GitLab can render natively.
                    cmd="mkdir -p '${cov_dir}'; cargo llvm-cov --cobertura --output-path '${cov_dir}/coverage.xml' nextest --profile ci"
                elif (( has_nextest )); then
                    cmd="cargo nextest run --profile ci"
                    log.warn "cargo-llvm-cov not installed; JUnit produced but no coverage. Install via 'cargo install cargo-llvm-cov'."
                elif (( has_llvm_cov )); then
                    cmd="mkdir -p '${cov_dir}'; cargo llvm-cov --cobertura --output-path '${cov_dir}/coverage.xml'"
                    log.warn "cargo-nextest not installed; coverage produced but no JUnit. Install via 'cargo install cargo-nextest'."
                else
                    log.warn "cargo-nextest and cargo-llvm-cov not installed; reports.enabled=true has no effect. Use brik-runner-rust or 'cargo install cargo-nextest cargo-llvm-cov'."
                fi
            fi
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
