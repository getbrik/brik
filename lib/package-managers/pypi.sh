#!/usr/bin/env bash
# @module pkg.pypi
# @requires twine|uv|poetry
# @description Publish to PyPI or a compatible registry.

# Guard against double-sourcing
[[ -n "${_BRIK_PKG_PYPI_LOADED:-}" ]] && return 0
_BRIK_PKG_PYPI_LOADED=1

# Publish to PyPI.
# Usage: pkg.pypi.publish [--repository <url>] [--token-var <VAR>] [--dry-run]
# Reads defaults from BRIK_PUBLISH_PYPI_* environment variables.
# Auth: uses environment variables (UV_PUBLISH_TOKEN, TWINE_USERNAME/TWINE_PASSWORD,
#        POETRY_PYPI_TOKEN_PYPI) to avoid CLI credential exposure.
pkg.pypi.publish() {
    local repository="${BRIK_PUBLISH_PYPI_REPOSITORY:-}"
    local token_var="${BRIK_PUBLISH_PYPI_TOKEN_VAR:-}"
    local dry_run="${BRIK_DRY_RUN:-}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --repository) repository="$2"; shift 2 ;;
            --token-var) token_var="$2"; shift 2 ;;
            --dry-run) dry_run="true"; shift ;;
            *) log.error "unknown option: $1"; return "$BRIK_EXIT_INVALID_INPUT" ;;
        esac
    done

    # Referential absorption: a declared PackageRegistry endpoint of this
    # format is the single source of truth for the destination and identity;
    # the BRIK_PUBLISH_PYPI_* variables remain the legacy path without one.
    # A basic credential maps to the user:password token form the twine and
    # uv branches already split on.
    brik.use package-managers._endpoint 2>/dev/null || true
    local _ep=""
    if declare -f pkg.endpoint.resolve >/dev/null 2>&1; then
        _ep="$(pkg.endpoint.resolve pypi "$repository")" || return "$?"
    fi
    if [[ -n "$_ep" ]]; then
        repository="$(jq -r '.url' <<<"$_ep")"
        case "$(jq -r '.method' <<<"$_ep")" in
            token) token_var="$(jq -r '.token_var' <<<"$_ep")" ;;
            basic)
                brik.use transverse.env
                BRIK_PKG_PYPI_AUTH="$(printf '%s:%s' "$(jq -r '.username' <<<"$_ep")" \
                    "$(transverse.env.resolve_indirect "$(jq -r '.password_var' <<<"$_ep")")")"
                export BRIK_PKG_PYPI_AUTH
                token_var="BRIK_PKG_PYPI_AUTH"
                ;;
            none) token_var="" ;;
        esac
    fi

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
                return "$BRIK_EXIT_MISSING_DEP"
            }
            export PATH="${HOME}/.local/bin:${PATH}"
            tool="twine"
        else
            log.error "no publish tool found (poetry, uv, or twine)"
            return "$BRIK_EXIT_MISSING_DEP"
        fi
    fi

    # Validate token if provided
    if [[ -n "$token_var" ]]; then
        brik.use transverse.secrets
        brik.use transverse.env
        transverse.secrets.require_var "$token_var" "pypi token" || return $?
    fi

    local -a cmd
    case "$tool" in
        poetry)
            cmd=(poetry publish --build)
            [[ -n "$repository" ]] && cmd+=(--repository "$repository")
            if [[ -n "$token_var" ]]; then
                POETRY_PYPI_TOKEN_PYPI="$(transverse.env.resolve_indirect "$token_var")"
                export POETRY_PYPI_TOKEN_PYPI
            fi
            ;;
        uv)
            cmd=(uv publish)
            [[ -n "$repository" ]] && cmd+=(--publish-url "$repository")
            # Auth via environment variable (not CLI arg)
            if [[ -n "$token_var" ]]; then
                UV_PUBLISH_TOKEN="$(transverse.env.resolve_indirect "$token_var")"
                export UV_PUBLISH_TOKEN
            fi
            ;;
        twine)
            # Build distribution if dist/ is empty
            local -a dist_files=(dist/*)
            if [[ ${#dist_files[@]} -eq 0 ]] || [[ "${dist_files[0]}" == "dist/*" ]]; then
                log.info "building distribution package"
                python -m build --outdir dist/ . 2>&1 || {
                    log.error "failed to build distribution"
                    return "$BRIK_EXIT_EXTERNAL_FAIL"
                }
                dist_files=(dist/*)
                if [[ ${#dist_files[@]} -eq 0 ]] || [[ "${dist_files[0]}" == "dist/*" ]]; then
                    log.error "no distribution files found in dist/ after build"
                    return "$BRIK_EXIT_EXTERNAL_FAIL"
                fi
            fi
            cmd=(twine upload "${dist_files[@]}")
            [[ -n "$repository" ]] && cmd+=(--repository-url "$repository")
            # Auth via environment variables (not CLI args)
            # Support both token auth (PyPI.org) and basic auth (Nexus/Artifactory)
            if [[ -n "$token_var" ]]; then
                local token_value
                token_value="$(transverse.env.resolve_indirect "$token_var")"
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
        _pkg._pypi_cleanup_env "$tool"
        return 0
    fi

    log.info "publishing to pypi via $tool (credentials via environment)"
    local rc=0
    "${cmd[@]}" || rc=$?

    # Cleanup credentials from environment
    _pkg._pypi_cleanup_env "$tool"

    if [[ $rc -ne 0 ]]; then
        log.error "pypi publish failed"
        return "$BRIK_EXIT_EXTERNAL_FAIL"
    fi

    log.info "pypi publish completed successfully"
    return 0
}

# Cleanup PyPI-related credentials from the environment.
# cleanup: always scrub credentials from env
_pkg._pypi_cleanup_env() {
    local tool="$1"
    case "$tool" in
        poetry) unset POETRY_PYPI_TOKEN_PYPI 2>/dev/null || true ;;
        uv)     unset UV_PUBLISH_TOKEN 2>/dev/null || true ;;
        twine)  unset TWINE_USERNAME TWINE_PASSWORD 2>/dev/null || true ;;
    esac
}
