#!/usr/bin/env bash
# @module stages/test
# @description Test stage - run tests via brik-lib.

# Install project dependencies so test tools are available.
# Idempotent: skips if deps are already present.
# On CI platforms like GitLab, each stage runs in a fresh container and
# deps from the build stage may not be present without cache.
# With warm cache, these installs are fast (local cache hit).
_test.install_deps() {
    local workspace="$1"
    local stack="${BRIK_BUILD_STACK:-}"

    case "$stack" in
        node)
            if [[ ! -d "${workspace}/node_modules" ]]; then
                log.info "installing node dependencies for test"
                (cd "$workspace" && npm ci --ignore-scripts 2>/dev/null) || true
            fi
            ;;
        python)
            export PATH="${HOME}/.local/bin:${PATH}"
            local pip_flags="--quiet"
            if pip install --help 2>&1 | grep -q -- '--break-system-packages'; then
                pip_flags="$pip_flags --break-system-packages"
            fi
            if [[ -f "${workspace}/pyproject.toml" ]]; then
                log.info "installing python dependencies for test"
                # shellcheck disable=SC2086
                (cd "$workspace" && pip install -e ".[dev]" $pip_flags 2>/dev/null) || \
                (cd "$workspace" && pip install -e . $pip_flags 2>/dev/null) || true
            elif [[ -f "${workspace}/requirements.txt" ]]; then
                log.info "installing python dependencies for test"
                # shellcheck disable=SC2086
                (cd "$workspace" && pip install -r requirements.txt $pip_flags 2>/dev/null) || true
            fi
            ;;
        java|rust)
            # Maven/Gradle and Cargo download deps as part of their test commands.
            ;;
        dotnet)
            log.info "restoring dotnet dependencies for test"
            (cd "$workspace" && dotnet restore --verbosity quiet 2>/dev/null) || true
            ;;
    esac
}

# Test stage: run tests via brik-lib.
# Usage: stages.test <context_file>
stages.test() {
    local context_file="$1"

    config.export_test_vars

    brik.use test

    _test.install_deps "${BRIK_WORKSPACE}"

    log.info "running tests"

    local test_args=("${BRIK_WORKSPACE}")

    if [[ -n "${BRIK_TEST_FRAMEWORK:-}" ]]; then
        test_args+=(--framework "$BRIK_TEST_FRAMEWORK")
    fi

    if [[ -n "${BRIK_TEST_COMMAND_UNIT:-}" ]]; then
        log.info "unit test command: $BRIK_TEST_COMMAND_UNIT"
    fi
    if [[ -n "${BRIK_TEST_COMMAND_INTEGRATION:-}" ]]; then
        log.info "integration test command: $BRIK_TEST_COMMAND_INTEGRATION"
    fi
    if [[ -n "${BRIK_TEST_COMMAND_E2E:-}" ]]; then
        log.info "e2e test command: $BRIK_TEST_COMMAND_E2E"
    fi

    test.run "${test_args[@]}"
    local result=$?

    if [[ $result -eq 0 ]]; then
        context.set "$context_file" "BRIK_TEST_STATUS" "success"
    else
        context.set "$context_file" "BRIK_TEST_STATUS" "failed"
    fi

    return "$result"
}
