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
    local manifest="" namespace="" context="" image_ref="" dry_run="${BRIK_DRY_RUN:-}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --manifest) manifest="$2"; shift 2 ;;
            --namespace) namespace="$2"; shift 2 ;;
            --context) context="$2"; shift 2 ;;
            --image-ref) image_ref="$2"; shift 2 ;;
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

    # When a digest-pinned ref is supplied, apply a staged copy with the image
    # pinned, never mutating the user's manifest on disk.
    local _staged=""
    if [[ -n "$image_ref" ]]; then
        brik.use deployments._image_ref
        if ! deploy.image_ref.is_pinned "$image_ref"; then
            log.error "refusing a non-digest-pinned image ref: ${image_ref}"
            return "$BRIK_EXIT_INVALID_INPUT"
        fi
        brik.use transverse.yaml
        _staged="$(mktemp -t brik-k8s-manifest.XXXXXX)"
        cp "$manifest" "$_staged"
        transverse.yaml.set_image "$_staged" \
            ".spec.template.spec.containers[]?.image" "$image_ref" 2>/dev/null || true
        transverse.yaml.set_image "$_staged" \
            ".spec.template.spec.initContainers[]?.image" "$image_ref" 2>/dev/null || true
        manifest="$_staged"
    fi

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

    local _apply_rc=0
    "${cmd[@]}" || _apply_rc=$?
    [[ -n "$_staged" ]] && rm -f "$_staged"
    if [[ "$_apply_rc" -ne 0 ]]; then
        log.error "kubectl apply failed"
        return "$BRIK_EXIT_EXTERNAL_FAIL"
    fi

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
