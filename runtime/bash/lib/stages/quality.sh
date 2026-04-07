#!/usr/bin/env bash
# @module stages/quality
# @description Quality stage - delegates to quality.run() for all checks.

# Install project dependencies so quality tools are available.
# Idempotent: skips if deps are already present.
_quality.install_deps() {
    local workspace="$1"
    local stack="${BRIK_BUILD_STACK:-}"

    case "$stack" in
        node)
            if [[ ! -d "${workspace}/node_modules" ]]; then
                log.info "installing node dependencies for quality tools"
                (cd "$workspace" && npm ci --ignore-scripts 2>/dev/null) || true
            fi
            ;;
        python)
            local pip_flags="--quiet"
            if pip install --help 2>&1 | grep -q -- '--break-system-packages'; then
                pip_flags="$pip_flags --break-system-packages"
            fi
            if [[ -f "${workspace}/pyproject.toml" ]]; then
                log.info "installing python dev dependencies for quality tools"
                # shellcheck disable=SC2086
                (cd "$workspace" && pip install -e ".[dev]" $pip_flags 2>/dev/null) || true
            elif [[ -f "${workspace}/requirements-dev.txt" ]]; then
                log.info "installing python dev dependencies for quality tools"
                # shellcheck disable=SC2086
                (cd "$workspace" && pip install -r requirements-dev.txt $pip_flags 2>/dev/null) || true
            fi
            ;;
        rust)
            if command -v rustup >/dev/null 2>&1; then
                if ! command -v cargo-clippy >/dev/null 2>&1; then
                    log.info "installing rustup component: clippy"
                    rustup component add clippy 2>/dev/null || true
                fi
                if ! command -v rustfmt >/dev/null 2>&1; then
                    log.info "installing rustup component: rustfmt"
                    rustup component add rustfmt 2>/dev/null || true
                fi
            fi
            ;;
    esac
}

# Quality stage: run configured quality checks via brik-lib.
# Usage: stages.quality <context_file>
stages.quality() {
    local context_file="$1"

    config.export_quality_vars

    if [[ "${BRIK_QUALITY_ENABLED:-true}" != "true" ]]; then
        log.info "quality stage disabled - skipping"
        context.set "$context_file" "BRIK_QUALITY_STATUS" "skipped"
        return 0
    fi

    brik.use quality

    # Ensure project dependencies are available (quality tools may be dev deps).
    # On CI platforms like GitLab, each stage runs in a fresh container and
    # node_modules/.venv are not carried over from the build stage.
    _quality.install_deps "${BRIK_WORKSPACE}"

    log.info "quality stage - running checks"

    # Build checks list from configured quality vars
    local checks=()
    [[ -n "${BRIK_QUALITY_LINT_TOOL:-}" || -n "${BRIK_QUALITY_LINT_COMMAND:-}" ]] && checks+=(lint)
    [[ -n "${BRIK_QUALITY_FORMAT_TOOL:-}" || -n "${BRIK_QUALITY_FORMAT_COMMAND:-}" ]] && checks+=(format)
    [[ -n "${BRIK_QUALITY_SAST_TOOL:-}" || -n "${BRIK_QUALITY_SAST_COMMAND:-}" ]] && checks+=(sast)
    [[ -n "${BRIK_QUALITY_DEPS_TOOL:-}" || -n "${BRIK_QUALITY_DEPS_COMMAND:-}" ]] && checks+=(deps)
    [[ -n "${BRIK_QUALITY_TYPE_CHECK_TOOL:-}" || -n "${BRIK_QUALITY_TYPE_CHECK_COMMAND:-}" ]] && checks+=(type_check)
    [[ -n "${BRIK_QUALITY_COVERAGE_THRESHOLD:-}" ]] && checks+=(coverage)
    [[ -n "${BRIK_QUALITY_LICENSE_ALLOWED:-}" || -n "${BRIK_QUALITY_LICENSE_DENIED:-}" ]] && checks+=(license)
    [[ -n "${BRIK_QUALITY_CONTAINER_IMAGE:-}" ]] && checks+=(container)

    if [[ ${#checks[@]} -eq 0 ]]; then
        log.info "no quality checks configured"
        context.set "$context_file" "BRIK_QUALITY_STATUS" "skipped"
        return 0
    fi

    local checks_csv
    checks_csv="$(IFS=','; printf '%s' "${checks[*]}")"

    quality.run "${BRIK_WORKSPACE}" --checks "$checks_csv"
    local result=$?

    if [[ $result -eq 0 ]]; then
        context.set "$context_file" "BRIK_QUALITY_STATUS" "success"
    else
        context.set "$context_file" "BRIK_QUALITY_STATUS" "failed"
    fi

    return "$result"
}
