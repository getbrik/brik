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

    # Pipeline-report enrichment (chantier 20260502 L2.C.3). business.violations
    # parsing and report_path/fix_applied fields require runner-output parsing
    # and are deferred to a follow-up.
    if command -v jq >/dev/null 2>&1; then
        local _checks_arr _tools_obj _commands_obj
        _checks_arr="$(printf '%s\n' "${checks[@]}" | jq -Rsc 'split("\n") | map(select(length > 0))')"
        _tools_obj="$(jq -nc \
            --arg lint        "${BRIK_QUALITY_LINT_TOOL:-}" \
            --arg format      "${BRIK_QUALITY_FORMAT_TOOL:-}" \
            --arg type_check  "${BRIK_QUALITY_TYPE_CHECK_TOOL:-}" \
            '{}
             + ( if $lint       != "" then { lint:       $lint }       else {} end )
             + ( if $format     != "" then { format:     $format }     else {} end )
             + ( if $type_check != "" then { type_check: $type_check } else {} end )')"
        _commands_obj="$(jq -nc \
            --arg lint        "${BRIK_QUALITY_LINT_COMMAND:-}" \
            --arg format      "${BRIK_QUALITY_FORMAT_COMMAND:-}" \
            --arg type_check  "${BRIK_QUALITY_TYPE_CHECK_COMMAND:-}" \
            '{}
             + ( if $lint       != "" then { lint:       $lint }       else {} end )
             + ( if $format     != "" then { format:     $format }     else {} end )
             + ( if $type_check != "" then { type_check: $type_check } else {} end )')"
        report.record_object "lint" "tech" "checks" "$_checks_arr" 2>/dev/null || true
        if [[ "$_tools_obj" != "{}" ]]; then
            report.record_object "lint" "tech" "tools" "$_tools_obj" 2>/dev/null || true
        fi
        if [[ "$_commands_obj" != "{}" ]]; then
            report.record_object "lint" "tech" "commands" "$_commands_obj" 2>/dev/null || true
        fi
    fi

    # pipeline.run records tech.status from our rc (see commit cf719f5).
    verify.run "${BRIK_WORKSPACE}" --checks "$checks_csv"
}
