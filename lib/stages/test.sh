#!/usr/bin/env bash
# @module stages/test
# @description Test stage - run tests via stack-specific modules.

brik.use "_deps"

# Test stage: run tests via stack-specific modules.
# Usage: stages.test <context_file>
stages.test() {
    # context_file positionally passed by stage.run; unused here
    # migration (pipeline.run records tech.status from rc).
    # shellcheck disable=SC2034
    local context_file="$1"

    config.export_test_vars

    pipeline.require_dir "${BRIK_WORKSPACE}" || return $?

    stacks.install_deps "${BRIK_WORKSPACE}" test || return $?

    log.info "running tests"

    if [[ -n "${BRIK_TEST_FRAMEWORK:-}" ]]; then
        report.record "test" "tech" "framework" "$BRIK_TEST_FRAMEWORK" 2>/dev/null || true
    fi
    # tool prefers the explicit BRIK_TEST_TOOL; falls back to the framework
    # name so the report still names a runner when the user does not declare
    # one. Stays absent only when both are empty.
    if [[ -n "${BRIK_TEST_TOOL:-}" ]]; then
        report.record "test" "tech" "tool" "$BRIK_TEST_TOOL" 2>/dev/null || true
    elif [[ -n "${BRIK_TEST_FRAMEWORK:-}" ]]; then
        report.record "test" "tech" "tool" "$BRIK_TEST_FRAMEWORK" 2>/dev/null || true
    fi
    if [[ -n "${BRIK_TEST_COVERAGE_FORMAT:-}" ]]; then
        report.record "test" "tech" "coverage_tool" "$BRIK_TEST_COVERAGE_FORMAT" 2>/dev/null || true
    fi

    # Tier 1: explicit test command override bypasses stack resolution.
    if [[ -n "${BRIK_TEST_COMMAND:-}" ]]; then
        log.info "running tests (command override): $BRIK_TEST_COMMAND"
        local exit_code=0
        (cd "${BRIK_WORKSPACE}" && eval "$BRIK_TEST_COMMAND") || exit_code=$?
        if [[ "$exit_code" -ne 0 ]]; then
            log.error "tests failed with exit code $exit_code"
            return "$BRIK_EXIT_CHECK_FAILED"
        fi
        log.info "tests passed"
        return 0
    fi

    # Tier 2/3: resolve stack from framework name or workspace marker files.
    brik.use stacks._detect
    local stack=""
    if [[ -n "${BRIK_TEST_FRAMEWORK:-}" ]]; then
        stack="$(stacks.detect_from_framework "$BRIK_TEST_FRAMEWORK")" || {
            log.error "unsupported test framework: $BRIK_TEST_FRAMEWORK"
            return "$BRIK_EXIT_CONFIG_ERROR"
        }
    else
        stack="$(stacks.detect "${BRIK_WORKSPACE}")" || return "$BRIK_EXIT_MISSING_DEP"
    fi

    if ! brik.use "stacks.${stack}"; then
        log.error "no test module: $stack"
        return "$BRIK_EXIT_CONFIG_ERROR"
    fi

    local test_cmd=""
    if [[ -n "${BRIK_TEST_FRAMEWORK:-}" ]]; then
        test_cmd="$(stacks."${stack}".test_cmd "$BRIK_TEST_FRAMEWORK" "${BRIK_WORKSPACE}" "")" || return $?
    else
        test_cmd="$(stacks."${stack}".test "${BRIK_WORKSPACE}" "")" || return $?
    fi

    log.info "running tests: $test_cmd"

    local exit_code2=0
    (cd "${BRIK_WORKSPACE}" && eval "$test_cmd") || exit_code2=$?

    # When reports.enabled=true, emit a single-line coverage summary that
    # downstream CI templates pick up with a generic regex (the GitLab
    # template ships a coverage: regex matching "[brik] coverage: ...%").
    # Run regardless of test success/failure so a partial report still
    # surfaces a percentage; never gate on the helper itself.
    if [[ "${BRIK_TEST_REPORTS_ENABLED:-false}" == "true" ]]; then
        brik.use transverse.coverage
        (cd "${BRIK_WORKSPACE}" && brik.coverage.summary) || true
        # Record coverage in business section so consumers don't need to
        # re-parse the report file. line_pct only for now; branch_pct is
        # deferred.
        local _cov_dir="${BRIK_TEST_COVERAGE_DIR:-brik-artifacts/test/coverage}"
        [[ "$_cov_dir" != /* ]] && _cov_dir="${BRIK_WORKSPACE:-.}/${_cov_dir}"
        local _cov_pct _cov_branch
        _cov_pct="$(_brik.coverage._parse_pct "$_cov_dir")"
        _cov_branch="$(_brik.coverage._parse_branch_pct "$_cov_dir" 2>/dev/null || true)"
        if [[ -n "$_cov_pct" ]] && command -v jq >/dev/null 2>&1; then
            local _cov_obj
            _cov_obj="$(jq -nc \
                --arg pct    "$_cov_pct" \
                --arg branch "$_cov_branch" \
                '{line_pct: $pct}
                 + ( if $branch != "" then { branch_pct: $branch } else {} end )')"
            report.record_object "test" "business" "coverage" "$_cov_obj" 2>/dev/null || true
        fi
        if [[ -n "${BRIK_TEST_COVERAGE_THRESHOLD:-}" ]]; then
            local gate_rc=0
            (cd "${BRIK_WORKSPACE}" && brik.coverage.gate "$BRIK_TEST_COVERAGE_THRESHOLD") || gate_rc=$?
            # Config errors (invalid threshold string) surface directly so
            # they are not squashed into the test-failure rc at the boundary.
            if [[ "$gate_rc" -eq "$BRIK_EXIT_INVALID_INPUT" ]]; then
                return "$gate_rc"
            fi
            if [[ "$gate_rc" -ne 0 && "$exit_code2" -eq 0 ]]; then
                exit_code2=$gate_rc
            fi

            # SC18: emit the breach as a SARIF result so it flows through the
            # unified findings pipeline (fix_classifier annotates it has_fix
            # per the "test" stage rule, then apply_policy honours DSI
            # opt-out via brik-policy.yml). Non-fatal: business.evaluate
            # owns the snapshot/release decision.
            local _cov_sarif="${BRIK_WORKSPACE:-.}/brik-artifacts/test/coverage.sarif"
            (cd "${BRIK_WORKSPACE}" \
                && brik.coverage.emit_sarif "$BRIK_TEST_COVERAGE_THRESHOLD" \
                       "$_cov_dir" "$_cov_sarif" >/dev/null 2>&1) || true
        fi
    fi

    # Record test counts from JUnit XML (when present). Run regardless of
    # test pass/fail so a partial report still surfaces counts.
    _stages.test._record_junit_business

    # SC18: merge any coverage SARIF into the test stage findings pipeline
    # so the breach is classified + policy-checked alongside JUnit results.
    _stages.test._integrate_coverage_findings

    if [[ "$exit_code2" -ne 0 ]]; then
        log.error "tests failed with exit code $exit_code2"
        return "$BRIK_EXIT_CHECK_FAILED"
    fi
    log.info "tests passed"
    return 0
}

# Look up the configured JUnit path, parse it via transverse.junit, and
# record the resulting counts under business.tests. Silent skip when the
# file is absent (libraries with no test reports, runners that did not
# emit JUnit, or BRIK_TEST_JUNIT_PATH explicitly empty).
_stages.test._record_junit_business() {
    local _junit_path="${BRIK_TEST_JUNIT_PATH:-}"
    [[ -z "$_junit_path" ]] && return 0
    if [[ "$_junit_path" != /* ]]; then
        _junit_path="${BRIK_WORKSPACE:-.}/${_junit_path}"
    fi
    [[ -f "$_junit_path" ]] || return 0

    brik.use transverse.junit 2>/dev/null || return 0
    local _counts
    _counts="$(junit.parse "$_junit_path" 2>/dev/null)" || return 0
    [[ -z "$_counts" ]] && return 0
    report.record_object "test" "business" "tests" "$_counts" 2>/dev/null || true

    # Promote the JUnit XML to a SARIF document via the P5 converter so
    # the test stage participates in the unified findings pipeline. Each
    # failing or erroring testcase becomes a kind=fail SARIF result;
    # skipped and xfail testcases land as kind=review notes. Passing
    # testcases are intentionally omitted (a green suite produces an
    # empty results[]). Failures of the converter are non-fatal -- a
    # missing module or a malformed XML leaves business.tests intact,
    # mirroring the silent-skip pattern of the legacy implementation.
    local _sarif_rel="${BRIK_TEST_FINDINGS_OUTPUT_PATH:-brik-artifacts/test/findings.sarif}"
    local _sarif_abs="$_sarif_rel"
    [[ "$_sarif_abs" != /* ]] && _sarif_abs="${BRIK_WORKSPACE:-.}/${_sarif_abs}"

    brik.use transverse.findings 2>/dev/null || return 0
    if declare -f findings.from_json >/dev/null 2>&1; then
        if findings.from_json junit "$_junit_path" "$_sarif_abs" >/dev/null 2>&1; then
            if declare -f findings.aggregate >/dev/null 2>&1; then
                findings.aggregate "test" "$_sarif_abs" 2>/dev/null || true
            fi
        fi
    fi
}

# Merge the optional coverage SARIF into the test stage findings pipeline.
# Called after _record_junit_business so any JUnit-converted SARIF is
# already on disk and we can concatenate results[] (and the rule entry)
# before re-running the unified findings pipeline. When no JUnit SARIF
# exists, the coverage SARIF flies alone through findings.process.
#
# Silent-skip pattern: missing module, missing coverage SARIF, missing jq,
# or zero coverage results all return 0 with no side-effects.
_stages.test._integrate_coverage_findings() {
    local _cov_sarif="${BRIK_WORKSPACE:-.}/brik-artifacts/test/coverage.sarif"
    [[ -f "$_cov_sarif" ]] || return 0
    command -v jq >/dev/null 2>&1 || return 0

    local cov_count
    cov_count="$(jq -r '(.runs[0].results // []) | length' "$_cov_sarif" 2>/dev/null)" \
        || cov_count="0"
    [[ "$cov_count" =~ ^[0-9]+$ ]] || cov_count="0"
    (( cov_count > 0 )) || return 0

    brik.use transverse.findings 2>/dev/null || return 0
    declare -f findings.process >/dev/null 2>&1 || return 0

    local _sarif_rel="${BRIK_TEST_FINDINGS_OUTPUT_PATH:-brik-artifacts/test/findings.sarif}"
    local _sarif_abs="$_sarif_rel"
    [[ "$_sarif_abs" != /* ]] && _sarif_abs="${BRIK_WORKSPACE:-.}/${_sarif_abs}"

    local target_sarif
    if [[ -f "$_sarif_abs" ]]; then
        # Merge coverage results + rule into the JUnit-converted SARIF.
        local tmp; tmp="$(mktemp)" || return 0
        if jq --slurpfile cov "$_cov_sarif" '
            .runs[0].results = ((.runs[0].results // []) + ($cov[0].runs[0].results // []))
            | .runs[0].tool.driver.rules = ((.runs[0].tool.driver.rules // []) + (($cov[0].runs[0].tool.driver.rules // [])))
        ' "$_sarif_abs" > "$tmp" 2>/dev/null; then
            mv "$tmp" "$_sarif_abs"
            target_sarif="$_sarif_abs"
        else
            rm -f "$tmp"
            target_sarif="$_cov_sarif"
        fi
    else
        target_sarif="$_cov_sarif"
    fi

    findings.process "test" "$target_sarif" 2>/dev/null || true
}
