#!/usr/bin/env bash
# @module stages/quality
# @description Quality stage - lint, SAST, dependency, coverage, license, and container checks.

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

    log.info "quality stage - running checks"

    local checks_run=0
    local checks_failed=0

    # Lint check
    if [[ -n "${BRIK_QUALITY_LINT_TOOL:-}" ]]; then
        log.info "running lint: $BRIK_QUALITY_LINT_TOOL"
        brik.use quality.lint 2>/dev/null || true
        if declare -f quality.lint.run >/dev/null 2>&1; then
            local lint_args=("${BRIK_WORKSPACE}")
            [[ "${BRIK_QUALITY_LINT_FIX:-}" == "true" ]] && lint_args+=(--fix)
            quality.lint.run "${lint_args[@]}" || ((checks_failed++))
            ((checks_run++))
        else
            log.warn "quality.lint module not available - skipping"
        fi
    fi

    # SAST check
    if [[ -n "${BRIK_QUALITY_SAST_TOOL:-}" ]]; then
        log.info "running SAST: $BRIK_QUALITY_SAST_TOOL"
        brik.use quality.sast 2>/dev/null || true
        if declare -f quality.sast.run >/dev/null 2>&1; then
            local sast_args=("${BRIK_WORKSPACE}" --tool "$BRIK_QUALITY_SAST_TOOL")
            quality.sast.run "${sast_args[@]}" || ((checks_failed++))
            ((checks_run++))
        else
            log.warn "quality.sast module not available - skipping"
        fi
    fi

    # Dependency check
    if [[ -n "${BRIK_QUALITY_DEPS_TOOL:-}" ]]; then
        log.info "running dependency check: $BRIK_QUALITY_DEPS_TOOL"
        brik.use quality.deps 2>/dev/null || true
        if declare -f quality.deps.run >/dev/null 2>&1; then
            local deps_args=("${BRIK_WORKSPACE}")
            [[ -n "${BRIK_QUALITY_DEPS_SEVERITY:-}" ]] && deps_args+=(--severity "$BRIK_QUALITY_DEPS_SEVERITY")
            quality.deps.run "${deps_args[@]}" || ((checks_failed++))
            ((checks_run++))
        else
            log.warn "quality.deps module not available - skipping"
        fi
    fi

    # Coverage check
    if [[ -n "${BRIK_QUALITY_COVERAGE_THRESHOLD:-}" ]]; then
        log.info "checking coverage threshold: $BRIK_QUALITY_COVERAGE_THRESHOLD"
        brik.use quality.coverage 2>/dev/null || true
        if declare -f quality.coverage.run >/dev/null 2>&1; then
            local cov_args=("${BRIK_WORKSPACE}" --threshold "$BRIK_QUALITY_COVERAGE_THRESHOLD")
            [[ -n "${BRIK_QUALITY_COVERAGE_REPORT:-}" ]] && cov_args+=(--report "$BRIK_QUALITY_COVERAGE_REPORT")
            quality.coverage.run "${cov_args[@]}" || ((checks_failed++))
            ((checks_run++))
        else
            log.warn "quality.coverage module not available - skipping"
        fi
    fi

    # License check
    if [[ -n "${BRIK_QUALITY_LICENSE_ALLOWED:-}" || -n "${BRIK_QUALITY_LICENSE_DENIED:-}" ]]; then
        log.info "running license check"
        brik.use quality.license 2>/dev/null || true
        if declare -f quality.license.run >/dev/null 2>&1; then
            local lic_args=("${BRIK_WORKSPACE}")
            [[ -n "${BRIK_QUALITY_LICENSE_ALLOWED:-}" ]] && lic_args+=(--allowed "$BRIK_QUALITY_LICENSE_ALLOWED")
            [[ -n "${BRIK_QUALITY_LICENSE_DENIED:-}" ]] && lic_args+=(--denied "$BRIK_QUALITY_LICENSE_DENIED")
            quality.license.run "${lic_args[@]}" || ((checks_failed++))
            ((checks_run++))
        else
            log.warn "quality.license module not available - skipping"
        fi
    fi

    # Container check
    if [[ -n "${BRIK_QUALITY_CONTAINER_IMAGE:-}" ]]; then
        log.info "running container check: $BRIK_QUALITY_CONTAINER_IMAGE"
        brik.use quality.container 2>/dev/null || true
        if declare -f quality.container.run >/dev/null 2>&1; then
            local ct_args=("${BRIK_WORKSPACE}" --image "$BRIK_QUALITY_CONTAINER_IMAGE")
            [[ -n "${BRIK_QUALITY_CONTAINER_SEVERITY:-}" ]] && ct_args+=(--severity "$BRIK_QUALITY_CONTAINER_SEVERITY")
            quality.container.run "${ct_args[@]}" || ((checks_failed++))
            ((checks_run++))
        else
            log.warn "quality.container module not available - skipping"
        fi
    fi

    if [[ $checks_run -eq 0 ]]; then
        log.info "no quality checks configured"
        context.set "$context_file" "BRIK_QUALITY_STATUS" "skipped"
        return 0
    fi

    if [[ $checks_failed -gt 0 ]]; then
        log.error "$checks_failed/$checks_run quality checks failed"
        context.set "$context_file" "BRIK_QUALITY_STATUS" "failed"
        return 1
    fi

    log.info "$checks_run quality checks passed"
    context.set "$context_file" "BRIK_QUALITY_STATUS" "success"
    return 0
}
