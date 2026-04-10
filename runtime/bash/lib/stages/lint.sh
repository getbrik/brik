#!/usr/bin/env bash
# @module stages/lint
# @description Lint stage - code quality checks (lint, format, type_check).
# Replaces the former quality stage. Runs in the CI/stack image.

brik.use "_deps"

# Lint stage: run code quality checks (lint, format, type_check) via brik-lib.
# Usage: stages.lint <context_file>
stages.lint() {
    local context_file="$1"

    config.export_quality_vars

    if [[ "${BRIK_LINT_ENABLED:-true}" != "true" ]]; then
        log.info "lint disabled (quality.lint.enabled=false) - skipping"
        context.set "$context_file" "BRIK_LINT_STATUS" "skipped"
        return 0
    fi

    brik.use quality

    # Ensure project dependencies are available (quality tools may be dev deps).
    _brik.install_deps "${BRIK_WORKSPACE}" dev

    log.info "lint stage - running checks"

    # Build checks list from lint/format/type_check vars only
    local checks=()
    [[ -n "${BRIK_QUALITY_LINT_TOOL:-}" || -n "${BRIK_QUALITY_LINT_COMMAND:-}" ]] && checks+=(lint)
    [[ -n "${BRIK_QUALITY_FORMAT_TOOL:-}" || -n "${BRIK_QUALITY_FORMAT_COMMAND:-}" ]] && checks+=(format)
    [[ -n "${BRIK_QUALITY_TYPE_CHECK_TOOL:-}" || -n "${BRIK_QUALITY_TYPE_CHECK_COMMAND:-}" ]] && checks+=(type_check)

    if [[ ${#checks[@]} -eq 0 ]]; then
        log.info "no lint checks configured"
        context.set "$context_file" "BRIK_LINT_STATUS" "skipped"
        return 0
    fi

    local checks_csv
    checks_csv="$(IFS=','; printf '%s' "${checks[*]}")"

    quality.run "${BRIK_WORKSPACE}" --checks "$checks_csv"
    local result=$?

    context.set_result "$context_file" "BRIK_LINT_STATUS" "$result"

    return "$result"
}
