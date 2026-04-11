#!/usr/bin/env bash
# @module security
# @description Security facade. Dispatches scans to dedicated sub-modules.
# Pattern: same as quality.run --checks (parameterized dispatch).

# Guard against double-sourcing
[[ -n "${_BRIK_CORE_SECURITY_LOADED:-}" ]] && return 0
_BRIK_CORE_SECURITY_LOADED=1

# Run security scans on a workspace.
# Usage: security.run <workspace> [--scans <deps,secret,sast,license,iac,container>]
#        [--severity <threshold>] [--image <image>]
# Defaults: --scans deps,secret --severity high
security.run() {
    local workspace="$1"
    shift
    local scans="deps,secret"
    local severity="high" image=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --scans) scans="$2"; shift 2 ;;
            --severity) severity="$2"; shift 2 ;;
            --image) image="$2"; shift 2 ;;
            *) log.error "unknown option: $1"; return "$BRIK_EXIT_INVALID_INPUT" ;;
        esac
    done

    runtime.require_dir "$workspace" || return "$BRIK_EXIT_IO_FAILURE"

    log.info "running security scans: $scans"

    local failed=0 total=0 passed=0
    local scan module_name scan_fn
    local -a _scan_list scan_args
    IFS=',' read -ra _scan_list <<< "$scans"

    for scan in "${_scan_list[@]}"; do
        # Trim whitespace
        scan="$(printf '%s' "$scan" | tr -d '[:space:]')"
        [[ -z "$scan" ]] && continue

        # Map user-facing name to module name
        module_name=""
        case "$scan" in
            deps)      module_name="deps" ;;
            secret)    module_name="secret_scan" ;;
            sast)      module_name="sast" ;;
            license)   module_name="license" ;;
            iac)       module_name="iac" ;;
            container) module_name="container" ;;
            *)
                log.warn "unknown security scan: $scan (skipping)"
                continue
                ;;
        esac

        # Load module if function not already available
        scan_fn="security.${module_name}.run"
        if ! declare -f "$scan_fn" >/dev/null 2>&1; then
            brik.use "security.${module_name}" || true
        fi

        if ! declare -f "$scan_fn" >/dev/null 2>&1; then
            log.warn "security.${module_name} module not available - skipping $scan scan"
            continue
        fi

        total=$((total + 1))

        # Build arguments per scan type
        scan_args=("$workspace")
        case "$scan" in
            deps)
                scan_args+=(--severity "$severity")
                ;;
            container)
                [[ -n "$image" ]] && scan_args+=(--image "$image")
                scan_args+=(--severity "$severity")
                ;;
        esac

        log.info "running security scan: $scan"
        if "$scan_fn" "${scan_args[@]}"; then
            passed=$((passed + 1))
            log.info "security scan passed: $scan"
        else
            failed=$((failed + 1))
            log.warn "security scan failed: $scan"
        fi
    done

    log.info "security summary: $passed/$total scans passed, $failed failed"

    if [[ "$failed" -gt 0 ]]; then
        return "$BRIK_EXIT_CHECK_FAILED"
    fi
    return 0
}
