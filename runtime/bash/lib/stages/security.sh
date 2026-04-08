#!/usr/bin/env bash
# @module stages/security
# @description Security stage - dependency, secret, and container scanning.

# Install project dependencies for dependency scanning tools.
# Idempotent: skips if deps are already present.
# Tools like npm audit and pip-audit need the dependency tree.
_security.install_deps() {
    local workspace="$1"
    local stack="${BRIK_BUILD_STACK:-}"

    case "$stack" in
        node)
            if [[ ! -d "${workspace}/node_modules" ]]; then
                log.info "installing node dependencies for security scanning"
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
                # shellcheck disable=SC2086
                (cd "$workspace" && pip install . $pip_flags 2>/dev/null) || true
            elif [[ -f "${workspace}/requirements.txt" ]]; then
                # shellcheck disable=SC2086
                (cd "$workspace" && pip install -r requirements.txt $pip_flags 2>/dev/null) || true
            fi
            ;;
    esac
}

# Security stage: run configured security scans via brik-lib.
# Usage: stages.security <context_file>
stages.security() {
    local context_file="$1"

    config.export_security_vars

    if [[ "${BRIK_SECURITY_ENABLED:-false}" != "true" ]]; then
        log.info "security stage disabled - skipping"
        context.set "$context_file" "BRIK_SECURITY_STATUS" "skipped"
        return 0
    fi

    brik.use security

    _security.install_deps "${BRIK_WORKSPACE}"

    log.info "security stage - running scans"

    local scan_args=()
    [[ -n "${BRIK_SECURITY_DEPENDENCY_SCAN:-}" ]] && scan_args+=(--dependency-scan "$BRIK_SECURITY_DEPENDENCY_SCAN")
    [[ -n "${BRIK_SECURITY_SECRET_SCAN:-}" ]] && scan_args+=(--secret-scan "$BRIK_SECURITY_SECRET_SCAN")
    [[ -n "${BRIK_SECURITY_CONTAINER_SCAN:-}" ]] && scan_args+=(--container-scan "$BRIK_SECURITY_CONTAINER_SCAN")
    [[ -n "${BRIK_SECURITY_SEVERITY_THRESHOLD:-}" ]] && scan_args+=(--severity "$BRIK_SECURITY_SEVERITY_THRESHOLD")

    security.run "${BRIK_WORKSPACE}" "${scan_args[@]}"
    local result=$?

    if [[ $result -eq 0 ]]; then
        context.set "$context_file" "BRIK_SECURITY_STATUS" "success"
    else
        context.set "$context_file" "BRIK_SECURITY_STATUS" "failed"
    fi

    return "$result"
}
