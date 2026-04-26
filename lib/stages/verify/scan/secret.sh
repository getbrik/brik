#!/usr/bin/env bash
# @module verify.scan.secret
# @uses transverse.tools verify._scan
# @description Security-focused secret scanning.

# Guard against double-sourcing
[[ -n "${_BRIK_VERIFY_SCAN_SECRET_LOADED:-}" ]] && return 0
_BRIK_VERIFY_SCAN_SECRET_LOADED=1

# Load tool registry and common scan helper
brik.use transverse.tools
brik.use verify.scan._scan

# Register security secret scanners. The {platform} placeholder is filled
# at exec time so gitleaks emits links to the right SCM in its findings
# instead of warning "Unknown SCM platform".
transverse.tools.register sec_secret gitleaks  gitleaks  "gitleaks detect --source . --platform {platform}"  10
transverse.tools.register sec_secret trufflehog trufflehog "trufflehog filesystem ."   20

# Resolve the gitleaks --platform value from BRIK_PLATFORM. Jenkins
# consumes webhooks from Gitea (or another git host) so we map it to a
# git-host name the gitleaks CLI accepts. Project-level override:
# BRIK_GITLEAKS_PLATFORM.
_verify.scan.secret._gitleaks_platform() {
    if [[ -n "${BRIK_GITLEAKS_PLATFORM:-}" ]]; then
        printf '%s' "$BRIK_GITLEAKS_PLATFORM"
        return
    fi
    case "${BRIK_PLATFORM:-}" in
        gitlab)  printf 'gitlab' ;;
        jenkins) printf 'gitea' ;;
        *)       printf 'gitlab' ;;
    esac
}

# Run security secret scan on a workspace.
# Usage: verify.scan.secret.run <workspace>
verify.scan.secret.run() {
    local workspace="$1"
    pipeline.require_dir "$workspace" || return "$BRIK_EXIT_IO_FAILURE"

    # Tier 1: BRIK_SECURITY_SECRETS_COMMAND override.
    if [[ -n "${BRIK_SECURITY_SECRETS_COMMAND:-}" ]]; then
        log.info "security secret scan (command override): $BRIK_SECURITY_SECRETS_COMMAND"
        (cd "$workspace" && eval "$BRIK_SECURITY_SECRETS_COMMAND") || {
            log.error "security secret scan findings detected"
            return "$BRIK_EXIT_CHECK_FAILED"
        }
        log.info "security secret scan passed"
        return 0
    fi

    # Tier 2+3: resolve via tool registry.
    local tool="${BRIK_SECURITY_SECRETS_TOOL:-}"
    local resolve_args=(sec_secret)
    [[ -n "$tool" ]] && resolve_args+=(--tool "$tool")

    local resolved rc=0
    resolved="$(transverse.tools.resolve "${resolve_args[@]}")" || rc=$?
    if [[ "$rc" -ne 0 ]]; then
        if [[ $rc -eq 3 ]]; then
            log.error "${tool} not found"
            return "$BRIK_EXIT_MISSING_DEP"
        elif [[ $rc -eq 7 ]]; then
            log.error "unknown security secret scan tool: $tool"
            return "$BRIK_EXIT_CONFIG_ERROR"
        fi
        log.warn "no security secret scan tool available - skipping"
        return 0
    fi

    log.info "security secret scan with $resolved"
    local platform
    platform="$(_verify.scan.secret._gitleaks_platform)"
    (cd "$workspace" && transverse.tools.exec sec_secret "$resolved" \
        workspace="$workspace" platform="$platform") || {
        log.error "security secret scan findings detected"
        return "$BRIK_EXIT_CHECK_FAILED"
    }
    log.info "security secret scan passed"
    return 0
}
