#!/usr/bin/env bash
# @module publish.pypi
# @requires twine|uv|poetry
# @description Publish to PyPI or a compatible registry.

# Guard against double-sourcing
[[ -n "${_BRIK_CORE_PUBLISH_PYPI_LOADED:-}" ]] && return 0
_BRIK_CORE_PUBLISH_PYPI_LOADED=1

# Publish to PyPI.
# Usage: publish.pypi.run [--repository <url>] [--token-var <VAR>] [--dry-run]
# Reads defaults from BRIK_PUBLISH_PYPI_* environment variables.
# Auth: uses environment variables (UV_PUBLISH_TOKEN, TWINE_USERNAME/TWINE_PASSWORD,
#        POETRY_PYPI_TOKEN_PYPI) to avoid CLI credential exposure.
publish.pypi.run() {
    local repository="${BRIK_PUBLISH_PYPI_REPOSITORY:-}"
    local token_var="${BRIK_PUBLISH_PYPI_TOKEN_VAR:-}"
    local dry_run="${BRIK_DRY_RUN:-}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --repository) repository="$2"; shift 2 ;;
            --token-var) token_var="$2"; shift 2 ;;
            --dry-run) dry_run="true"; shift ;;
            *) log.error "unknown option: $1"; return 2 ;;
        esac
    done

    # Detect publish tool
    local tool=""
    if [[ -f "pyproject.toml" ]] && grep -q '\[tool\.poetry\]' pyproject.toml 2>/dev/null; then
        tool="poetry"
    elif command -v uv >/dev/null 2>&1; then
        tool="uv"
    elif command -v twine >/dev/null 2>&1; then
        tool="twine"
    else
        # Auto-install twine + build in CI environments
        if [[ -n "${CI:-}" ]]; then
            log.info "installing twine and build tools"
            pip install --quiet twine build 2>/dev/null || {
                log.error "failed to install twine"
                return 3
            }
            export PATH="${HOME}/.local/bin:${PATH}"
            tool="twine"
        else
            log.error "no publish tool found (poetry, uv, or twine)"
            return 3
        fi
    fi

    # Validate token if provided
    if [[ -n "$token_var" ]]; then
        _publish._require_secret_var "$token_var" "pypi token" || return $?
    fi

    local -a cmd
    case "$tool" in
        poetry)
            cmd=(poetry publish --build)
            [[ -n "$repository" ]] && cmd+=(--repository "$repository")
            [[ -n "$token_var" ]] && export POETRY_PYPI_TOKEN_PYPI="${!token_var}"
            ;;
        uv)
            cmd=(uv publish)
            [[ -n "$repository" ]] && cmd+=(--publish-url "$repository")
            # Auth via environment variable (not CLI arg)
            [[ -n "$token_var" ]] && export UV_PUBLISH_TOKEN="${!token_var}"
            ;;
        twine)
            # Build distribution if dist/ is empty
            local -a dist_files=(dist/*)
            if [[ ${#dist_files[@]} -eq 0 ]] || [[ "${dist_files[0]}" == "dist/*" ]]; then
                log.info "building distribution package"
                python -m build --outdir dist/ . 2>&1 || {
                    log.error "failed to build distribution"
                    return 5
                }
                dist_files=(dist/*)
                if [[ ${#dist_files[@]} -eq 0 ]] || [[ "${dist_files[0]}" == "dist/*" ]]; then
                    log.error "no distribution files found in dist/ after build"
                    return 5
                fi
            fi
            cmd=(twine upload "${dist_files[@]}")
            [[ -n "$repository" ]] && cmd+=(--repository-url "$repository")
            # Auth via environment variables (not CLI args)
            # Support both token auth (PyPI.org) and basic auth (Nexus/Artifactory)
            if [[ -n "$token_var" ]]; then
                local token_value="${!token_var}"
                if [[ "$token_value" == *:* ]]; then
                    # Format user:password - basic auth (Nexus, Artifactory)
                    export TWINE_USERNAME="${token_value%%:*}"
                    export TWINE_PASSWORD="${token_value#*:}"
                else
                    # Token auth (PyPI.org)
                    export TWINE_USERNAME="__token__"
                    export TWINE_PASSWORD="$token_value"
                fi
            fi
            ;;
    esac

    if [[ "$dry_run" == "true" ]]; then
        log.info "[dry-run] ${cmd[*]}"
        _publish._pypi_cleanup_env "$tool"
        return 0
    fi

    log.info "publishing to pypi via $tool (credentials via environment)"
    "${cmd[@]}"
    local rc=$?

    # Cleanup credentials from environment
    _publish._pypi_cleanup_env "$tool"

    if [[ $rc -ne 0 ]]; then
        log.error "pypi publish failed"
        return 5
    fi

    log.info "pypi publish completed successfully"
    return 0
}

# Cleanup PyPI-related credentials from the environment.
# cleanup: always scrub credentials from env
_publish._pypi_cleanup_env() {
    local tool="$1"
    case "$tool" in
        poetry) unset POETRY_PYPI_TOKEN_PYPI 2>/dev/null || true ;;
        uv)     unset UV_PUBLISH_TOKEN 2>/dev/null || true ;;
        twine)  unset TWINE_USERNAME TWINE_PASSWORD 2>/dev/null || true ;;
    esac
}
