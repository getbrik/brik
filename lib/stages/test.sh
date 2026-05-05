#!/usr/bin/env bash
# @module stages/test
# @description Test stage - run tests via stack-specific modules.

brik.use "_deps"

# Test stage: run tests via stack-specific modules.
# Usage: stages.test <context_file>
stages.test() {
    # context_file positionally passed by stage.run; unused here after §4.2
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
        # deferred (chantier 20260502 L2.C.2 follow-up).
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
        fi
    fi

    # Record test counts from JUnit XML (when present). Run regardless of
    # test pass/fail so a partial report still surfaces counts.
    _stages.test._record_junit_business

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
}
