#!/usr/bin/env bash
# @module stages/scan
# @description Scan stage - dependency and secret scanning.
# Runs in the scanner image (Go binaries like osv-scanner, grype, gitleaks).

# Install project dependencies for dependency scanning tools.
# Idempotent: skips if deps are already present.
# Tools like npm audit and pip-audit need the dependency tree.
_scan.install_deps() {
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

# Scan stage: run dependency and secret scans via brik-lib.
# Usage: stages.scan <context_file>
stages.scan() {
    local context_file="$1"

    config.export_security_vars

    log.info "scan stage - running dependency and secret scans"

    local failed=0 total=0 passed=0

    # Dependency scan (non-negotiable: defaults to osv-scanner if not configured)
    export BRIK_SECURITY_DEPS_TOOL="${BRIK_SECURITY_DEPS_TOOL:-osv-scanner}"
    if true; then
        total=$((total + 1))

        _scan.install_deps "${BRIK_WORKSPACE}"

        if ! declare -f security.deps.run >/dev/null 2>&1; then
            local sec_deps_path="${BASH_SOURCE[0]%/*}/../core/security/deps.sh"
            if [[ -f "$sec_deps_path" ]]; then
                # shellcheck source=../core/security/deps.sh
                . "$sec_deps_path"
            fi
        fi

        if declare -f security.deps.run >/dev/null 2>&1; then
            local severity="${BRIK_SECURITY_DEPS_SEVERITY:-${BRIK_SECURITY_SEVERITY_THRESHOLD:-high}}"
            log.info "running dependency scan (tool=${BRIK_SECURITY_DEPS_TOOL}, severity=$severity)"
            if security.deps.run "${BRIK_WORKSPACE}" --severity "$severity"; then
                passed=$((passed + 1))
                log.info "dependency scan passed"
            else
                failed=$((failed + 1))
                log.warn "dependency scan failed"
            fi
        else
            log.warn "security.deps module not available - skipping dependency scan"
        fi
    fi

    # Secret scan (non-negotiable: defaults to gitleaks if not configured)
    export BRIK_SECURITY_SECRETS_TOOL="${BRIK_SECURITY_SECRETS_TOOL:-gitleaks}"
    if true; then
        total=$((total + 1))

        if ! declare -f security.secret_scan.run >/dev/null 2>&1; then
            local sec_secret_path="${BASH_SOURCE[0]%/*}/../core/security/secret_scan.sh"
            if [[ -f "$sec_secret_path" ]]; then
                # shellcheck source=../core/security/secret_scan.sh
                . "$sec_secret_path"
            fi
        fi

        if declare -f security.secret_scan.run >/dev/null 2>&1; then
            log.info "running secret scan (tool=${BRIK_SECURITY_SECRETS_TOOL})"
            if security.secret_scan.run "${BRIK_WORKSPACE}"; then
                passed=$((passed + 1))
                log.info "secret scan passed"
            else
                failed=$((failed + 1))
                log.warn "secret scan failed"
            fi
        else
            log.warn "security.secret_scan module not available - skipping secret scan"
        fi
    fi

    log.info "scan summary: $passed/$total passed, $failed failed"

    if [[ "$failed" -gt 0 ]]; then
        context.set "$context_file" "BRIK_SCAN_STATUS" "failed"
        return 10
    fi

    context.set "$context_file" "BRIK_SCAN_STATUS" "success"
    return 0
}
