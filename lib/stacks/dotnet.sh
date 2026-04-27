#!/usr/bin/env bash
# @module stacks/dotnet
# @requires dotnet
# @description Build .NET projects (dotnet build).

# Guard against double-sourcing
[[ -n "${_BRIK_STACKS_DOTNET_LOADED:-}" ]] && return 0
_BRIK_STACKS_DOTNET_LOADED=1

# Build a .NET project.
# Usage: stacks.dotnet.build <workspace> [--configuration <Debug|Release>]
stacks.dotnet.build() {
    local workspace="$1"
    shift
    local configuration=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --configuration) configuration="$2"; shift 2 ;;
            *) log.error "unknown option: $1"; return "$BRIK_EXIT_INVALID_INPUT" ;;
        esac
    done

    pipeline.require_dir "$workspace" || return "$BRIK_EXIT_IO_FAILURE"

    # Need at least one .csproj or .sln file
    if ! compgen -G "${workspace}/*.csproj" >/dev/null 2>&1 && \
       ! compgen -G "${workspace}/*.sln" >/dev/null 2>&1; then
        log.error "no .csproj or .sln found in workspace: $workspace"
        return "$BRIK_EXIT_IO_FAILURE"
    fi

    pipeline.require_tool dotnet || return "$BRIK_EXIT_MISSING_DEP"

    log.info "building with dotnet"

    local dotnet_args="build"
    if [[ -n "$configuration" ]]; then
        dotnet_args="build --configuration $configuration"
    fi

    # $dotnet_args intentionally word-splits
    # shellcheck disable=SC2086
    (cd "$workspace" && dotnet $dotnet_args) || {
        log.error "build failed"
        return "$BRIK_EXIT_EXTERNAL_FAIL"
    }

    log.info "build completed successfully"
    return 0
}

# Build the test command for a given .NET framework.
# Usage: stacks.dotnet.test_cmd <framework> <workspace> <report_dir>
# Frameworks: dotnet
stacks.dotnet.test_cmd() {
    local framework="$1"
    local cmd=""
    local reports_on="${BRIK_TEST_REPORTS_ENABLED:-false}"

    case "$framework" in
        dotnet)
            cmd="dotnet test"
            if [[ "$reports_on" == "true" ]]; then
                local cov_dir="${BRIK_TEST_COVERAGE_DIR:-coverage}"
                local junit="${BRIK_TEST_JUNIT_PATH:-reports/junit.xml}"
                # XPlat Code Coverage requires the coverlet.collector nuget
                # package on the test project. The collector writes
                # <test-project>/TestResults/<guid>/coverage.cobertura.xml;
                # we flatten that to ${cov_dir}/coverage.xml post-test.
                # JunitXml.TestLogger (also a nuget on the test project)
                # writes LogFilePath relative to the TEST PROJECT's cwd
                # (e.g. test/Calculator.Tests/reports/junit.xml), not the
                # workspace root, so we also flatten the JUnit XML to
                # the workspace-rooted ${junit} path.
                # We do NOT pass --results-directory because that would
                # redirect the JUnit XML under it too.
                # Use ; (not &&) so the flatten runs even when tests fail;
                # preserve the test exit code via _rc.
                local junit_dir junit_name
                junit_dir="$(dirname "${junit}")"
                junit_name="$(basename "${junit}")"
                cmd="${cmd} --collect:'XPlat Code Coverage'"
                cmd="${cmd} --logger:'junit;LogFilePath=${junit}'"
                cmd="${cmd}; _rc=\$?"
                cmd="${cmd}; mkdir -p '${cov_dir}' '${junit_dir}'"
                cmd="${cmd}; find . -path '*/TestResults/*/coverage.cobertura.xml' -exec cp -f {} '${cov_dir}/coverage.xml' \\; 2>/dev/null"
                cmd="${cmd}; find . -path '*/${junit}' -not -path './${junit}' -exec cp -f {} '${junit}' \\; 2>/dev/null"
                cmd="${cmd}; exit \$_rc"
            fi
            ;;
        *)
            log.error "unsupported .NET test framework: $framework"
            return "$BRIK_EXIT_CONFIG_ERROR"
            ;;
    esac

    printf '%s' "$cmd"
    return 0
}

# Auto-detect and return the test command for a .NET workspace.
# Usage: stacks.dotnet.test <workspace> <report_dir>
stacks.dotnet.test() {
    printf '%s' "dotnet test"
}
