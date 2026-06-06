#!/usr/bin/env bash
# @module deploy.k8s
# @requires kubectl
# @description Deploy to Kubernetes via kubectl apply.

# Guard against double-sourcing
[[ -n "${_BRIK_DEPLOYMENTS_K8S_LOADED:-}" ]] && return 0
_BRIK_DEPLOYMENTS_K8S_LOADED=1

# Deploy manifests to Kubernetes.
# Usage: deploy.k8s.run [--manifest <path>] [--namespace <ns>]
#        [--context <ctx>] [--dry-run]
deploy.k8s.run() {
    local manifest="" namespace="" context="" dry_run="${BRIK_DRY_RUN:-}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --manifest) manifest="$2"; shift 2 ;;
            --namespace) namespace="$2"; shift 2 ;;
            --context) context="$2"; shift 2 ;;
            --dry-run) dry_run="true"; shift ;;
            # Ignore deploy.run passthrough options
            --target|--env) shift 2 ;;
            *) log.error "unknown option: $1"; return "$BRIK_EXIT_INVALID_INPUT" ;;
        esac
    done

    if [[ -z "$manifest" ]]; then
        log.error "manifest path is required (--manifest)"
        return "$BRIK_EXIT_INVALID_INPUT"
    fi

    pipeline.require_file "$manifest" || return "$BRIK_EXIT_IO_FAILURE"
    pipeline.require_tool kubectl || return "$BRIK_EXIT_MISSING_DEP"

    # Build kubectl command
    local -a cmd=(kubectl apply -f "$manifest")
    [[ -n "$namespace" ]] && cmd+=(--namespace "$namespace")
    [[ -n "$context" ]] && cmd+=(--context "$context")
    # Allow extra kubectl options via env (e.g. --validate=false for self-signed certs)
    # shellcheck disable=SC2206
    [[ -n "${BRIK_KUBECTL_OPTS:-}" ]] && cmd+=($BRIK_KUBECTL_OPTS)

    if [[ "$dry_run" == "true" ]]; then
        cmd+=(--dry-run=client)
        log.info "[dry-run] ${cmd[*]}"
    else
        log.info "applying manifest: ${cmd[*]}"
    fi

    "${cmd[@]}" || {
        log.error "kubectl apply failed"
        return "$BRIK_EXIT_EXTERNAL_FAIL"
    }

    log.info "deployment completed successfully"
    return 0
}

# Read back the digest of the image currently running in a Deployment.
# Usage: deploy.k8s.get_deployed_digest --deployment <name> [--namespace <ns>]
#        [--context <ctx>]
# Output: "sha256:<hex>" when the live image is digest-pinned, else "unknown".
# Returns: 2 invalid input; 3 kubectl missing; 5 kubectl query failed.
deploy.k8s.get_deployed_digest() {
    local deployment="" namespace="" context=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --deployment) deployment="$2"; shift 2 ;;
            --namespace)  namespace="$2";  shift 2 ;;
            --context)    context="$2";    shift 2 ;;
            *) log.error "unknown option: $1"; return "$BRIK_EXIT_INVALID_INPUT" ;;
        esac
    done

    if [[ -z "$deployment" ]]; then
        log.error "deployment name is required (--deployment)"
        return "$BRIK_EXIT_INVALID_INPUT"
    fi
    pipeline.require_tool kubectl || return "$BRIK_EXIT_MISSING_DEP"
    brik.use deployments._image_ref

    local -a cmd=(kubectl get deployment "$deployment"
                  -o "jsonpath={.spec.template.spec.containers[0].image}")
    [[ -n "$namespace" ]] && cmd+=(--namespace "$namespace")
    [[ -n "$context" ]]   && cmd+=(--context "$context")

    local image
    image="$("${cmd[@]}" 2>/dev/null)" || {
        log.error "kubectl get deployment failed for: ${deployment}"
        return "$BRIK_EXIT_EXTERNAL_FAIL"
    }
    deploy.image_ref.extract_digest "$image"
}
