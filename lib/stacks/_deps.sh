#!/usr/bin/env bash
# @module _deps
# @description Centralized dependency installation for stages.
# Provides stacks.install_deps to avoid duplicating install logic in each stage.

# Guard against double-sourcing
[[ -n "${_BRIK_STACKS_DEPS_LOADED:-}" ]] && return 0
_BRIK_STACKS_DEPS_LOADED=1

# Source the registry to aggregate cache paths from stack manifests
# (D.2.2 of the architecture refactor chantier). The registry is the
# source of truth for spec.cache.paths per stack.
# shellcheck source=../registry/registry.sh
. "${BASH_SOURCE[0]%/*}/../registry/registry.sh"

# Stack-specific cache paths -- aggregated from the registry.
#
# Three consumers query this rather than maintain their own copy:
#   1. GitLab job templates (build/lint/package/sast/scan/test.yml) declare
#      these under cache.paths so dependency downloads survive across runs.
#      The inline YAML list is kept in sync via spec/integration/cache_paths_parity_spec.sh.
#   2. Jenkins brikIntegrate.groovy maps each path to a "<top-level>/**"
#      EXCLUDE pattern for cleanWs, so cached deps survive cross-build cleanups.
#   3. shared-libs/gitlab/scripts/gitlab-wrapper.sh pre-creates each path
#      with a .brik-keep marker so GitLab's cache step never logs
#      "no matching files" for stacks the active build doesn't populate.
#
# Iteration order is the canonical language-stack order: node, python, java,
# rust, dotnet. Docker is excluded - it has a build cache (buildx) but the
# CI cache mechanism this list feeds is meant for language package managers
# (npm, pip, maven, gradle, cargo, nuget). Adding a new language stack means
# appending its id to this array AND declaring spec.cache.paths in its
# manifest.
#
# Output: one path per line, in stable order. Paths are relative to BRIK_WORKSPACE.
_STACKS_CACHE_PATHS_ORDER=(node python java rust dotnet)

stacks.cache_paths() {
    local s
    for s in "${_STACKS_CACHE_PATHS_ORDER[@]}"; do
        registry.stack.cache_paths "$s" 2>/dev/null || true
    done
}

# Install project dependencies for a given stage mode.
# Usage: stacks.install_deps <workspace> <mode>
# Modes:
#   test - dev extras with fallback to runtime deps (for test stage)
#   dev  - dev dependencies only (for lint/format tools)
#   scan - runtime dependencies only (for security scanning)
stacks.install_deps() {
    local workspace="$1"
    local mode="${2:-scan}"
    local stack="${BRIK_BUILD_STACK:-}"

    case "$stack" in
        node)
            _brik._install_deps_node "$workspace" || return $?
            ;;
        python)
            _brik._install_deps_python "$workspace" "$mode" || return $?
            ;;
        rust)
            [[ "$mode" == "dev" ]] && { _brik._install_deps_rust || return $?; }
            ;;
        dotnet)
            [[ "$mode" == "test" ]] && { _brik._install_deps_dotnet "$workspace" || return $?; }
            ;;
    esac
    return 0
}

# Per-stack helpers below propagate exit codes:
#   - skip silently (return 0) when there is nothing to install (no package
#     manifest, mode irrelevant, etc.).
#   - return BRIK_EXIT_MISSING_DEP when the install command itself fails so
#     the caller (lint/test/scan) surfaces a real failure instead of
#     continuing with broken dependencies.
# Output (stdout/stderr) of the install command is left visible so the user
# sees the native error message; we do not redirect it to /dev/null.

_brik._install_deps_node() {
    local workspace="$1"
    [[ -f "${workspace}/package.json" ]] || return 0
    # Some runner images (scanner, analysis) do not ship npm. Skip silently
    # when the tool is missing -- those stages do not need installed deps.
    command -v npm >/dev/null 2>&1 || return 0

    # Skip the install only when node_modules is in sync with the current
    # package-lock.json. npm ci writes node_modules/.package-lock.json as
    # a copy of the project's lockfile after a successful install; if the
    # two files match byte-for-byte we know the deps on disk are current.
    # This keeps the helper idempotent when called multiple times in one
    # build -- the parallel Jenkins verify stages (lint, sast, scan, test)
    # share a workspace via --volumes-from and would otherwise race on
    # npm ci. The first caller in the pipeline (brik-build) does the real
    # install; the rest fast-path through the sync check.
    if [[ -d "${workspace}/node_modules/.bin" ]] \
        && [[ -f "${workspace}/package-lock.json" ]] \
        && [[ -f "${workspace}/node_modules/.package-lock.json" ]] \
        && cmp -s "${workspace}/package-lock.json" \
                  "${workspace}/node_modules/.package-lock.json"; then
        return 0
    fi
    # Projects without a package-lock.json keep the legacy "skip if
    # node_modules exists" behaviour; we have no signal to detect drift.
    if [[ -d "${workspace}/node_modules/.bin" ]] \
        && [[ ! -f "${workspace}/package-lock.json" ]]; then
        return 0
    fi

    log.info "installing node dependencies"
    if (cd "$workspace" && npm ci --ignore-scripts); then
        return 0
    fi
    log.error "npm ci failed in $workspace"
    return "$BRIK_EXIT_MISSING_DEP"
}

_brik._install_deps_python() {
    local workspace="$1" mode="$2"
    # Some runner images (scanner, analysis) do not ship pip. Skip silently
    # when the tool is missing -- those stages do not need installed deps.
    command -v pip >/dev/null 2>&1 || return 0

    # Per-stage PYTHONUSERBASE so parallel verify branches (lint, test) do
    # not race on the same site-packages directory. On Jenkins the parallel
    # branches share $WORKSPACE via --volumes-from, so two concurrent
    # `pip install -e ".[dev]"` calls writing to $HOME/.local can lose
    # files mid-extraction. GitLab gets each branch its own ephemeral
    # workspace already; the per-stage isolation is harmless there but
    # gives both platforms identical install layout.
    local stage_scope="${BRIK_LOG_SCOPE:-default}"
    export PYTHONUSERBASE="${workspace}/.brik-stage/${stage_scope}/python"
    mkdir -p "$PYTHONUSERBASE" 2>/dev/null || true
    export PATH="${PYTHONUSERBASE}/bin:${HOME}/.local/bin:${PATH}"

    local pip_flags="--quiet"
    if pip install --help 2>&1 | grep -q -- '--break-system-packages'; then
        pip_flags="$pip_flags --break-system-packages"
    fi

    case "$mode" in
        test)
            if [[ -f "${workspace}/pyproject.toml" ]]; then
                log.info "installing python dependencies for test"
                # Try dev extras first; fall back to plain install when [dev]
                # is not declared. Only the second attempt failing is fatal.
                # shellcheck disable=SC2086
                (cd "$workspace" && pip install -e ".[dev]" $pip_flags) && return 0
                # shellcheck disable=SC2086
                if (cd "$workspace" && pip install -e . $pip_flags); then
                    return 0
                fi
                log.error "pip install failed in $workspace"
                return "$BRIK_EXIT_MISSING_DEP"
            elif [[ -f "${workspace}/requirements.txt" ]]; then
                log.info "installing python dependencies for test"
                # shellcheck disable=SC2086
                if (cd "$workspace" && pip install -r requirements.txt $pip_flags); then
                    return 0
                fi
                log.error "pip install -r requirements.txt failed in $workspace"
                return "$BRIK_EXIT_MISSING_DEP"
            fi
            return 0
            ;;
        dev)
            if [[ -f "${workspace}/pyproject.toml" ]]; then
                log.info "installing python dev dependencies"
                # shellcheck disable=SC2086
                if (cd "$workspace" && pip install -e ".[dev]" $pip_flags); then
                    return 0
                fi
                log.error "pip install -e .[dev] failed in $workspace"
                return "$BRIK_EXIT_MISSING_DEP"
            elif [[ -f "${workspace}/requirements-dev.txt" ]]; then
                log.info "installing python dev dependencies"
                # shellcheck disable=SC2086
                if (cd "$workspace" && pip install -r requirements-dev.txt $pip_flags); then
                    return 0
                fi
                log.error "pip install -r requirements-dev.txt failed in $workspace"
                return "$BRIK_EXIT_MISSING_DEP"
            fi
            return 0
            ;;
        scan)
            if [[ -f "${workspace}/pyproject.toml" ]]; then
                # shellcheck disable=SC2086
                if (cd "$workspace" && pip install . $pip_flags); then
                    return 0
                fi
                log.error "pip install . failed in $workspace"
                return "$BRIK_EXIT_MISSING_DEP"
            elif [[ -f "${workspace}/requirements.txt" ]]; then
                # shellcheck disable=SC2086
                if (cd "$workspace" && pip install -r requirements.txt $pip_flags); then
                    return 0
                fi
                log.error "pip install -r requirements.txt failed in $workspace"
                return "$BRIK_EXIT_MISSING_DEP"
            fi
            return 0
            ;;
    esac
    return 0
}

_brik._install_deps_rust() {
    command -v rustup >/dev/null 2>&1 || return 0
    local rc=0
    if ! command -v cargo-clippy >/dev/null 2>&1; then
        log.info "installing rustup component: clippy"
        rustup component add clippy || rc="$BRIK_EXIT_MISSING_DEP"
    fi
    if ! command -v rustfmt >/dev/null 2>&1; then
        log.info "installing rustup component: rustfmt"
        rustup component add rustfmt || rc="$BRIK_EXIT_MISSING_DEP"
    fi
    if [[ "$rc" -ne 0 ]]; then
        log.error "rustup component add failed"
        return "$rc"
    fi
    return 0
}

_brik._install_deps_dotnet() {
    local workspace="$1"
    log.info "restoring dotnet dependencies"
    if (cd "$workspace" && dotnet restore --verbosity quiet); then
        return 0
    fi
    log.error "dotnet restore failed in $workspace"
    return "$BRIK_EXIT_MISSING_DEP"
}
