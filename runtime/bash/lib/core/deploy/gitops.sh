#!/usr/bin/env bash
# @module deploy.gitops
# @requires git
# @description Deploy via GitOps: clone a config repo, update the image tag, and push.

# Guard against double-sourcing
[[ -n "${_BRIK_CORE_DEPLOY_GITOPS_LOADED:-}" ]] && return 0
_BRIK_CORE_DEPLOY_GITOPS_LOADED=1

# Deploy by updating manifests in a GitOps repository.
# Usage: deploy.gitops.run --repo <url> [--path <subdir>] [--namespace <ns>]
#        [--manifest <file>] [--controller <argocd|fluxcd>] [--app-name <name>]
#        [--dry-run]
deploy.gitops.run() {
    local repo="" path="" _namespace="" manifest="" controller="" app_name=""
    local dry_run="${BRIK_DRY_RUN:-}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --repo)        repo="$2";        shift 2 ;;
            --path)        path="$2";        shift 2 ;;
            --namespace)   _namespace="$2";  shift 2 ;;
            --manifest)    manifest="$2";    shift 2 ;;
            --controller)  controller="$2";  shift 2 ;;
            --app-name)    app_name="$2";    shift 2 ;;
            --dry-run)     dry_run="true";   shift ;;
            # Ignore deploy.run passthrough options
            --target|--env) shift 2 ;;
            *) log.error "unknown option: $1"; return "$BRIK_EXIT_INVALID_INPUT" ;;
        esac
    done

    if [[ -z "$repo" ]]; then
        log.error "repo is required (--repo)"
        return "$BRIK_EXIT_INVALID_INPUT"
    fi

    runtime.require_tool git || return "$BRIK_EXIT_MISSING_DEP"

    # Resolve image tag from environment
    local tag="${BRIK_DEPLOY_IMAGE_TAG:-${BRIK_TAG:-${BRIK_COMMIT_SHA:-}}}"

    # Validate path to prevent traversal
    if [[ "$path" =~ \.\. ]]; then
        log.error "path must not contain '..': $path"
        return "$BRIK_EXIT_INVALID_INPUT"
    fi

    # Clone config repo into a temp directory
    local tmpdir
    tmpdir="$(mktemp -d)"
    local safe_repo
    safe_repo="$(printf '%s' "$repo" | sed 's|://[^@]*@|://***@|')"
    log.info "cloning gitops repo: $safe_repo"
    GIT_TERMINAL_PROMPT=0 git clone --depth 1 "$repo" "$tmpdir" || {
        log.error "git clone failed"
        rm -rf "$tmpdir"
        return "$BRIK_EXIT_EXTERNAL_FAIL"
    }

    # Navigate to subdirectory if --path is set
    local workdir="$tmpdir"
    if [[ -n "$path" ]]; then
        workdir="${tmpdir}/${path}"
        if [[ ! -d "$workdir" ]]; then
            log.error "path not found in cloned repo: $path"
            rm -rf "$tmpdir"
            return "$BRIK_EXIT_IO_FAILURE"
        fi
    fi

    # _namespace is accepted for forward-compatibility (kustomize overlay support in Phase 4)

    # Update image tag in manifests using yq when tag is available
    if [[ -n "$tag" ]]; then
        log.info "updating image tag to: $tag"
        if command -v yq >/dev/null 2>&1; then
            local manifest_file="${manifest:-${workdir}/kustomization.yaml}"
            if [[ -f "$manifest_file" ]]; then
                IMAGE_TAG="$tag" yq -i '.spec.template.spec.containers[0].image = env(IMAGE_TAG)' "$manifest_file" || {
                    log.error "failed to update image tag in manifest"
                    rm -rf "$tmpdir"
                    return "$BRIK_EXIT_EXTERNAL_FAIL"
                }
            fi
        fi
    fi

    git -C "$tmpdir" add . || {
        log.error "git add failed"
        rm -rf "$tmpdir"
        return "$BRIK_EXIT_EXTERNAL_FAIL"
    }

    # Commit changes (no-op if nothing to commit)
    local commit_msg="deploy: update image to ${tag:-unknown}"
    local commit_exit=0
    git -C "$tmpdir" -c user.email="brik-ci@noreply" -c user.name="Brik CI" commit -m "$commit_msg" || commit_exit=$?
    if [[ "$commit_exit" -eq 1 ]]; then
        log.info "no changes to commit (manifest already up-to-date)"
        rm -rf "$tmpdir"
        return 0
    elif [[ "$commit_exit" -ne 0 ]]; then
        log.error "git commit failed"
        rm -rf "$tmpdir"
        return "$BRIK_EXIT_EXTERNAL_FAIL"
    fi

    # Push unless dry-run
    if [[ "$dry_run" == "true" ]]; then
        log.info "[dry-run] would push to remote (skipped)"
    else
        local push_err
        push_err="$(GIT_TERMINAL_PROMPT=0 git -C "$tmpdir" push 2>&1)" || {
            local safe_err
            safe_err="$(printf '%s' "$push_err" | sed 's|://[^@]*@|://***@|')"
            log.error "git push failed: $safe_err"
            rm -rf "$tmpdir"
            return "$BRIK_EXIT_EXTERNAL_FAIL"
        }
    fi

    # Controller-specific post-deploy actions
    if [[ "$controller" == "argocd" ]]; then
        if [[ -n "$app_name" && "$dry_run" != "true" ]]; then
            brik.use deploy.argocd
            deploy.argocd.sync "$app_name" || {
                log.error "argocd sync failed for app: ${app_name}"
                rm -rf "$tmpdir"
                return "$BRIK_EXIT_EXTERNAL_FAIL"
            }
            deploy.argocd.wait_healthy "$app_name" || {
                log.warn "argocd wait_healthy failed for app: ${app_name} (non-blocking)"
            }
        elif [[ -n "$app_name" && "$dry_run" == "true" ]]; then
            log.info "[dry-run] would call: deploy.argocd.sync ${app_name}"
        else
            log.info "argocd: repo updated; sync will be triggered by ArgoCD controller"
        fi
    elif [[ "$controller" == "fluxcd" ]]; then
        log.info "fluxcd: flux will auto-reconcile from the updated repo"
    fi

    rm -rf "$tmpdir"
    log.info "gitops deployment completed successfully"
    return 0
}
