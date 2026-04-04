#!/usr/bin/env bash
# @module stages/quality
# @description Quality stage - delegates to quality.run() for all checks.

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
