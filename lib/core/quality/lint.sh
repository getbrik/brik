#!/usr/bin/env bash
# @module quality.lint
# @description Lint code using stack-appropriate linters.
# 3-tier resolution: BRIK_QUALITY_LINT_COMMAND > BRIK_QUALITY_LINT_TOOL > auto-detect

# Guard against double-sourcing
[[ -n "${_BRIK_CORE_QUALITY_LINT_LOADED:-}" ]] && return 0
_BRIK_CORE_QUALITY_LINT_LOADED=1

# Run linting on a workspace.
# Usage: quality.lint.run <workspace> [--fix]
quality.lint.run() {
    local workspace="$1"
    shift
    local fix=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --fix) fix="true"; shift ;;
            *) log.error "unknown option: $1"; return "$BRIK_EXIT_INVALID_INPUT" ;;
        esac
    done

    runtime.require_dir "$workspace" || return "$BRIK_EXIT_IO_FAILURE"

    # Tier 1: explicit command override
    if [[ -n "${BRIK_QUALITY_LINT_COMMAND:-}" ]]; then
        log.info "linting (command override): $BRIK_QUALITY_LINT_COMMAND"
        (cd "$workspace" && eval "$BRIK_QUALITY_LINT_COMMAND") || {
            log.error "lint violations found"
            return "$BRIK_EXIT_CHECK_FAILED"
        }
        log.info "lint passed"
        return 0
    fi

    local lint_cmd=""
    local tool="${BRIK_QUALITY_LINT_TOOL:-}"

    # Tier 2: explicit tool selection
    if [[ -n "$tool" ]]; then
        case "$tool" in
            eslint)
                if command -v npx >/dev/null 2>&1; then
                    if ! compgen -G "${workspace}/eslint.config.*" >/dev/null 2>&1 \
                        && ! compgen -G "${workspace}/.eslintrc*" >/dev/null 2>&1; then
                        log.warn "no eslint config found - skipping lint"
                        return 0
                    fi
                    lint_cmd="npx eslint ."
                    [[ "$fix" == "true" ]] && lint_cmd="$lint_cmd --fix"
                else
                    log.error "npx not found for eslint"
                    return "$BRIK_EXIT_MISSING_DEP"
                fi
                ;;
            biome)
                if command -v npx >/dev/null 2>&1; then
                    lint_cmd="npx biome check ."
                    [[ "$fix" == "true" ]] && lint_cmd="$lint_cmd --fix"
                else
                    log.error "npx not found for biome"
                    return "$BRIK_EXIT_MISSING_DEP"
                fi
                ;;
            ruff)
                if command -v ruff >/dev/null 2>&1; then
                    lint_cmd="ruff check ."
                    [[ "$fix" == "true" ]] && lint_cmd="$lint_cmd --fix"
                else
                    log.error "ruff not found for linting"
                    return "$BRIK_EXIT_MISSING_DEP"
                fi
                ;;
            clippy)
                if command -v cargo >/dev/null 2>&1; then
                    lint_cmd="cargo clippy"
                else
                    log.error "cargo not found for clippy"
                    return "$BRIK_EXIT_MISSING_DEP"
                fi
                ;;
            checkstyle)
                if command -v mvn >/dev/null 2>&1; then
                    lint_cmd="mvn -B checkstyle:check"
                elif command -v gradle >/dev/null 2>&1; then
                    lint_cmd="gradle checkstyleMain"
                else
                    log.error "mvn or gradle not found for checkstyle"
                    return "$BRIK_EXIT_MISSING_DEP"
                fi
                ;;
            dotnet-format)
                if command -v dotnet >/dev/null 2>&1; then
                    lint_cmd="dotnet format --verify-no-changes"
                else
                    log.error "dotnet not found for formatting"
                    return "$BRIK_EXIT_MISSING_DEP"
                fi
                ;;
            *)
                if command -v "$tool" >/dev/null 2>&1; then
                    lint_cmd="$tool"
                else
                    log.error "unknown lint tool: $tool"
                    return "$BRIK_EXIT_CONFIG_ERROR"
                fi
                ;;
        esac
    fi

    # Tier 3: auto-detect from workspace files
    if [[ -z "$lint_cmd" ]]; then
        if [[ -f "${workspace}/package.json" ]]; then
            if ! compgen -G "${workspace}/eslint.config.*" >/dev/null 2>&1 \
                && ! compgen -G "${workspace}/.eslintrc*" >/dev/null 2>&1; then
                log.warn "no eslint config found - skipping lint"
                return 0
            fi
            if command -v npx >/dev/null 2>&1; then
                lint_cmd="npx eslint ."
                [[ "$fix" == "true" ]] && lint_cmd="$lint_cmd --fix"
            else
                log.error "npx not found for JavaScript/TypeScript linting"
                return "$BRIK_EXIT_MISSING_DEP"
            fi
        elif [[ -f "${workspace}/pyproject.toml" || -f "${workspace}/setup.py" ]]; then
            if command -v ruff >/dev/null 2>&1; then
                lint_cmd="ruff check ."
                [[ "$fix" == "true" ]] && lint_cmd="$lint_cmd --fix"
            else
                log.error "ruff not found for Python linting"
                return "$BRIK_EXIT_MISSING_DEP"
            fi
        elif [[ -f "${workspace}/Cargo.toml" ]]; then
            if command -v cargo >/dev/null 2>&1; then
                lint_cmd="cargo clippy"
            else
                log.error "cargo not found for Rust linting"
                return "$BRIK_EXIT_MISSING_DEP"
            fi
        elif [[ -f "${workspace}/pom.xml" ]]; then
            if command -v mvn >/dev/null 2>&1; then
                lint_cmd="mvn -B checkstyle:check"
            else
                log.warn "mvn not found for Java linting - skipping"
                return 0
            fi
        elif [[ -f "${workspace}/build.gradle" || -f "${workspace}/build.gradle.kts" ]]; then
            if command -v gradle >/dev/null 2>&1; then
                lint_cmd="gradle checkstyleMain"
            else
                log.warn "gradle not found for Java linting - skipping"
                return 0
            fi
        elif compgen -G "${workspace}/*.csproj" >/dev/null 2>&1 || compgen -G "${workspace}/*.sln" >/dev/null 2>&1; then
            if command -v dotnet >/dev/null 2>&1; then
                lint_cmd="dotnet format --verify-no-changes"
            else
                log.error "dotnet not found for .NET linting"
                return "$BRIK_EXIT_MISSING_DEP"
            fi
        else
            log.error "cannot detect stack for linting in workspace: $workspace"
            return "$BRIK_EXIT_MISSING_DEP"
        fi
    fi

    log.info "linting: $lint_cmd"
    (cd "$workspace" && eval "$lint_cmd") || {
        log.error "lint violations found"
        return "$BRIK_EXIT_CHECK_FAILED"
    }

    log.info "lint passed"
    return 0
}
