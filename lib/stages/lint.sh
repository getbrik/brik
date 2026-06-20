#!/usr/bin/env bash
# @module stages/lint
# @description Lint stage - code quality checks (lint, format, type_check).
# Replaces the former quality stage. Runs in the CI/stack image.

brik.use "_deps"

# Lint stage: run code quality checks (lint, format, type_check) via brik-lib.
# Usage: stages.lint <context_file>
stages.lint() {
    # context_file positionally passed by stage.run; unused here
    # migration (report.record replaces context.set for status markers).
    # shellcheck disable=SC2034
    local context_file="$1"

    config.export_quality_vars

    # Status semantics in aggregate-report.json:
    #   - skipped + tech.kind=not-applicable : no lint/format/type_check
    #                      tool configured, no auto-detect trigger fires
    #                      either. Auto-skip only; user opt-out via
    #                      *.enabled=false is no longer honoured (init
    #                      emits a deprecation warning if the legacy key
    #                      is present in brik.yml).
    #   - skipped        : tool configured but expected config absent (set
    #                      by verify.lint.run on Tier 3 fall-through).
    #   - passed/failed  : recorded by pipeline.run from the verify.run rc.
    #
    # Shift-left contract: lint always runs. The legacy quality.lint.enabled
    # opt-out is no longer honoured (init surfaces a deprecation warning when
    # it sees the key); opting out is a business-level decision and lives
    # outside the technical layer.

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
        report.record "lint" "tech" "status" "skipped" 2>/dev/null || true
        report.record "lint" "tech" "kind"   "not-applicable" 2>/dev/null || true
        return 0
    fi

    local checks_csv
    checks_csv="$(IFS=','; printf '%s' "${checks[*]}")"

    # Pipeline-report enrichment. business.violations
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
    local _verify_rc=$?

    # Pipeline-report business.* enrichment (absorbed into the L4 backend):
    # aggregate any per-check SARIF outputs the verify helpers
    # produced under ${BRIK_WORKSPACE}/brik-artifacts/lint/<check>.sarif into the canonical
    # business.violations.{total, by_severity, by_check} object.
    _lint._record_business "${checks[@]}" 2>/dev/null || true

    return "$_verify_rc"
}

# Aggregate per-check SARIF outputs into business.violations + business.report
# + business.fix_applied. No-op when the sarif transverse module is missing,
# jq is missing, or no per-check SARIF files exist under ${BRIK_WORKSPACE}/
# brik-artifacts/lint/.
_lint._record_business() {
    local _checks=( "$@" )
    [[ ${#_checks[@]} -gt 0 ]] || return 0
    command -v jq >/dev/null 2>&1 || return 0

    local _artifacts_dir="${BRIK_WORKSPACE:-.}/brik-artifacts/lint"
    [[ -d "$_artifacts_dir" ]] || return 0

    if ! declare -f sarif.count_total >/dev/null 2>&1; then
        brik.use transverse.sarif 2>/dev/null || return 0
    fi

    local _check _file _present_checks=() _present_files=()
    for _check in "${_checks[@]}"; do
        _file="${_artifacts_dir}/${_check}.sarif"
        if [[ -f "$_file" ]]; then
            _present_checks+=( "$_check" )
            _present_files+=( "$_file" )
        fi
    done

    [[ ${#_present_files[@]} -gt 0 ]] || return 0

    local _by_check_json='{}'
    local _total=0 _i=0
    while [[ $_i -lt ${#_present_files[@]} ]]; do
        local _c _t
        _c="${_present_checks[$_i]}"
        _t="$(sarif.count_total "${_present_files[$_i]}" 2>/dev/null || echo 0)"
        _total=$(( _total + _t ))
        _by_check_json="$(jq -nc --argjson acc "$_by_check_json" --arg k "$_c" --argjson v "$_t" \
            '$acc + {($k): $v}')"
        _i=$(( _i + 1 ))
    done

    local _by_severity_json
    _by_severity_json="$(
        for _file in "${_present_files[@]}"; do
            sarif.count_by_severity "$_file" 2>/dev/null
        done | jq -sc 'reduce .[] as $sev (
            {critical:0, high:0, medium:0, low:0, info:0};
            .critical += ($sev.critical // 0)
          | .high     += ($sev.high     // 0)
          | .medium   += ($sev.medium   // 0)
          | .low      += ($sev.low      // 0)
          | .info     += ($sev.info     // 0)
        )'
    )"

    local _violations_obj
    _violations_obj="$(jq -nc \
        --argjson total       "$_total" \
        --argjson by_severity "$_by_severity_json" \
        --argjson by_check    "$_by_check_json" \
        '{total: $total, by_severity: $by_severity, by_check: $by_check}')"
    report.record_object "lint" "business" "violations" "$_violations_obj" 2>/dev/null || true

    report.record_object "lint" "business" "report" \
        '{"format":"sarif","path":"brik-artifacts/lint/lint.sarif"}' 2>/dev/null || true

    local _fix
    case "${BRIK_QUALITY_LINT_FIX:-false}" in
        true|1|yes) _fix=true ;;
        *)          _fix=false ;;
    esac
    report.record_object "lint" "business" "fix_applied" "$_fix" 2>/dev/null || true
}
