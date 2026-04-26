#!/usr/bin/env bash
# @module stages/lint
# @description Lint stage - code quality checks (lint, format, type_check).
# Replaces the former quality stage. Runs in the CI/stack image.

brik.use "_deps"

# Lint stage: run code quality checks (lint, format, type_check) via brik-lib.
# Usage: stages.lint <context_file>
stages.lint() {
    # context_file positionally passed by stage.run; unused here after §4.2
    # migration (report.record replaces context.set for status markers).
    # shellcheck disable=SC2034
    local context_file="$1"

    config.export_quality_vars

    # Status semantics in pipeline-report.json:
    #   - disabled       : explicit opt-out via quality.lint.enabled=false
    #   - not-applicable : no lint/format/type_check tool configured, no
    #                      auto-detect trigger fires either
    #   - skipped        : tool configured but expected config absent (set
    #                      by verify.lint.run on Tier 3 fall-through)
    #   - passed/failed  : recorded by pipeline.run from the verify.run rc
    if [[ "${BRIK_LINT_ENABLED:-true}" != "true" ]]; then
        log.info "lint disabled (quality.lint.enabled=false) - skipping"
        report.record "lint" "tech" "status" "disabled" 2>/dev/null || true
        return 0
    fi

    brik.use verify.verify

    # Ensure project dependencies are available (quality tools may be dev deps).
    stacks.install_deps "${BRIK_WORKSPACE}" dev || return $?

    log.info "lint stage - running checks"

    # Build checks list from lint/format/type_check vars only
    local checks=()
    [[ -n "${BRIK_QUALITY_LINT_TOOL:-}" || -n "${BRIK_QUALITY_LINT_COMMAND:-}" ]] && checks+=(lint)
    [[ -n "${BRIK_QUALITY_FORMAT_TOOL:-}" || -n "${BRIK_QUALITY_FORMAT_COMMAND:-}" ]] && checks+=(format)
    [[ -n "${BRIK_QUALITY_TYPE_CHECK_TOOL:-}" || -n "${BRIK_QUALITY_TYPE_CHECK_COMMAND:-}" ]] && checks+=(type_check)

    if [[ ${#checks[@]} -eq 0 ]]; then
        log.info "no lint checks configured"
        report.record "lint" "tech" "status" "not-applicable" 2>/dev/null || true
        return 0
    fi

    local checks_csv
    checks_csv="$(IFS=','; printf '%s' "${checks[*]}")"

    # pipeline.run records tech.status from our rc (see commit cf719f5).
    verify.run "${BRIK_WORKSPACE}" --checks "$checks_csv"
}
