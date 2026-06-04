#!/usr/bin/env bash
# @module deploy.gitops
# @requires git
# @description GitOps deployment functions: render, push, wait, diff, rollback.
#
# Functions:
#   deploy.gitops.render_manifests - Generate final K8s YAML from various sources
#   deploy.gitops.push_manifests   - Clone config-repo, copy rendered YAML, commit+push
#   deploy.gitops.wait_sync        - Generic poll loop with pluggable check function
#   deploy.gitops.diff             - Preview changes before push
#   deploy.gitops.rollback         - Revert last deployment in config-repo
#   deploy.gitops.run              - Convenience orchestrator (render -> push -> wait)

# Guard against double-sourcing
[[ -n "${_BRIK_DEPLOYMENTS_GITOPS_LOADED:-}" ]] && return 0
_BRIK_DEPLOYMENTS_GITOPS_LOADED=1

# Internal helper: inject git token into a repo URL via variable indirection.
# Usage: _deploy.gitops._inject_token <repo_url> <token_var_name>
# stdout: URL with token injected, or original URL if no token var
_deploy.gitops._inject_token() {
    local repo="$1" token_var="$2"
    if [[ -z "$token_var" ]]; then
        printf '%s' "$repo"
        return 0
    fi
    brik.use transverse.env
    local token
    token="$(transverse.env.resolve_indirect "$token_var")"
    if [[ -z "$token" ]]; then
        log.error "token variable is empty: ${token_var}"
        return "$BRIK_EXIT_INVALID_ENV"
    fi
    # Inject token into https URL: https://TOKEN@host/...
    printf '%s' "$repo" | sed "s|https://|https://${token}@|"
}

# Internal helper: mask credentials in a URL for safe logging.
_deploy.gitops._safe_url() {
    printf '%s' "$1" | sed 's|://[^@]*@|://***@|'
}

# Render Kubernetes manifests from various sources.
# Usage: deploy.gitops.render_manifests --source <path> --output <path>
#        --type <kustomize|helm_template|plain> [--set <key=value>...] [--dry-run]
deploy.gitops.render_manifests() {
    local source_dir="" output_dir="" render_type=""
    local -a set_values=()
    local dry_run="${BRIK_DRY_RUN:-}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --source)  source_dir="$2";  shift 2 ;;
            --output)  output_dir="$2";  shift 2 ;;
            --type)    render_type="$2"; shift 2 ;;
            --set)     set_values+=("$2"); shift 2 ;;
            --dry-run) dry_run="true";   shift ;;
            *) log.error "unknown option: $1"; return "$BRIK_EXIT_INVALID_INPUT" ;;
        esac
    done

    if [[ -z "$source_dir" ]]; then
        log.error "source is required (--source)"
        return "$BRIK_EXIT_INVALID_INPUT"
    fi
    if [[ -z "$output_dir" ]]; then
        log.error "output is required (--output)"
        return "$BRIK_EXIT_INVALID_INPUT"
    fi
    if [[ -z "$render_type" ]]; then
        log.error "type is required (--type)"
        return "$BRIK_EXIT_INVALID_INPUT"
    fi

    if [[ ! -d "$source_dir" ]]; then
        log.error "source directory not found: $source_dir"
        return "$BRIK_EXIT_IO_FAILURE"
    fi

    if [[ "$dry_run" == "true" ]]; then
        log.info "[dry-run] would render manifests: type=${render_type} source=${source_dir} output=${output_dir}"
        return 0
    fi

    mkdir -p "$output_dir" || {
        log.error "cannot create output directory: $output_dir"
        return "$BRIK_EXIT_IO_FAILURE"
    }

    case "$render_type" in
        kustomize)
            pipeline.require_tool kustomize || return "$BRIK_EXIT_MISSING_DEP"
            # Apply --set values via kustomize edit if provided
            local set_val
            for set_val in "${set_values[@]}"; do
                kustomize edit set image "$set_val" -C "$source_dir" 2>/dev/null || true
            done
            log.info "rendering kustomize manifests: $source_dir -> $output_dir"
            kustomize build "$source_dir" -o "$output_dir" || {
                log.error "kustomize build failed"
                return "$BRIK_EXIT_EXTERNAL_FAIL"
            }
            ;;
        helm_template)
            pipeline.require_tool helm || return "$BRIK_EXIT_MISSING_DEP"
            local -a helm_cmd=(helm template "$source_dir")
            local sv
            for sv in "${set_values[@]}"; do
                helm_cmd+=(--set "$sv")
            done
            log.info "rendering helm template: $source_dir -> $output_dir"
            "${helm_cmd[@]}" > "${output_dir}/manifests.yaml" || {
                log.error "helm template failed"
                return "$BRIK_EXIT_EXTERNAL_FAIL"
            }
            ;;
        plain)
            log.info "copying plain manifests: $source_dir -> $output_dir"
            cp -r "${source_dir}/." "${output_dir}/" || {
                log.error "copy failed"
                return "$BRIK_EXIT_IO_FAILURE"
            }
            # Apply --set values via transverse.yaml.patch if provided
            if [[ ${#set_values[@]} -gt 0 ]]; then
                brik.use transverse.yaml
                local sv2
                for sv2 in "${set_values[@]}"; do
                    local key="${sv2%%=*}"
                    local val="${sv2#*=}"
                    find "$output_dir" -name '*.yaml' -o -name '*.yml' | while read -r f; do
                        transverse.yaml.patch "$f" ".${key}" "$val" 2>/dev/null || true
                    done
                done
            fi
            ;;
        *)
            log.error "unknown render type: $render_type (expected: kustomize, helm_template, plain)"
            return "$BRIK_EXIT_CONFIG_ERROR"
            ;;
    esac

    printf '%s' "$output_dir"
    return 0
}

# Clone a config repo, copy rendered manifests, commit and push.
# Usage: deploy.gitops.push_manifests --repo <url> --branch <branch>
#        --path <target> --source <rendered> --message <msg>
#        [--git-token-var <VAR>] [--dry-run]
deploy.gitops.push_manifests() {
    local repo="" branch="" target_path="" source_dir="" message="" git_token_var=""
    local image_tag=""
    local dry_run="${BRIK_DRY_RUN:-}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --repo)          repo="$2";          shift 2 ;;
            --branch)        branch="$2";        shift 2 ;;
            --path)          target_path="$2";   shift 2 ;;
            --source)        source_dir="$2";    shift 2 ;;
            --message)       message="$2";       shift 2 ;;
            --git-token-var) git_token_var="$2"; shift 2 ;;
            --image-tag)     image_tag="$2";     shift 2 ;;
            --dry-run)       dry_run="true";     shift ;;
            *) log.error "unknown option: $1"; return "$BRIK_EXIT_INVALID_INPUT" ;;
        esac
    done

    if [[ -z "$repo" ]]; then
        log.error "repo is required (--repo)"
        return "$BRIK_EXIT_INVALID_INPUT"
    fi
    if [[ -z "$branch" ]]; then
        log.error "branch is required (--branch)"
        return "$BRIK_EXIT_INVALID_INPUT"
    fi
    if [[ -z "$target_path" ]]; then
        log.error "path is required (--path)"
        return "$BRIK_EXIT_INVALID_INPUT"
    fi
    if [[ -z "$source_dir" ]]; then
        log.error "source is required (--source)"
        return "$BRIK_EXIT_INVALID_INPUT"
    fi
    if [[ -z "$message" ]]; then
        log.error "message is required (--message)"
        return "$BRIK_EXIT_INVALID_INPUT"
    fi

    pipeline.require_tool git || return "$BRIK_EXIT_MISSING_DEP"

    # Inject token into URL if provided
    local clone_url
    clone_url="$(_deploy.gitops._inject_token "$repo" "$git_token_var")" || return $?

    local safe_url
    safe_url="$(_deploy.gitops._safe_url "$clone_url")"

    if [[ "$dry_run" == "true" ]]; then
        log.info "[dry-run] would push manifests to ${safe_url} branch=${branch} path=${target_path}"
        return 0
    fi

    # Clone into temp directory (explicit cleanup -- trap RETURN is
    # incompatible with kcov which enables functrace)
    local tmpdir
    tmpdir="$(mktemp -d)"

    log.info "cloning config repo: $safe_url (branch: $branch)"
    brik.use transverse.git
    if ! transverse.git.clone_shallow "$clone_url" "$tmpdir" --branch "$branch"; then
        rm -rf "$tmpdir"
        return "$BRIK_EXIT_EXTERNAL_FAIL"
    fi

    # Clear target path and copy new manifests
    local dest="${tmpdir}/${target_path}"
    mkdir -p "$dest"
    rm -rf "${dest:?}"/*
    if ! cp -r "${source_dir}/." "${dest}/"; then
        log.error "failed to copy manifests to config repo"
        rm -rf "$tmpdir"
        return "$BRIK_EXIT_IO_FAILURE"
    fi

    # Substitute image tags if --image-tag was provided
    if [[ -n "$image_tag" ]]; then
        brik.use transverse.yaml
        local manifest_file
        while IFS= read -r manifest_file; do
            transverse.yaml.set_image_tag "$manifest_file" \
                ".spec.template.spec.containers[]?.image" "$image_tag" 2>/dev/null || true
            transverse.yaml.set_image_tag "$manifest_file" \
                ".spec.template.spec.initContainers[]?.image" "$image_tag" 2>/dev/null || true
        done < <(find "$dest" -name '*.yaml' -o -name '*.yml')
        log.info "image tags substituted to :${image_tag}"
    fi

    # Commit and push
    if ! git -C "$tmpdir" add .; then
        log.error "git add failed"
        rm -rf "$tmpdir"
        return "$BRIK_EXIT_EXTERNAL_FAIL"
    fi

    local commit_exit=0
    git -C "$tmpdir" -c user.email="brik-ci@noreply" -c user.name="Brik CI" commit -m "$message" || commit_exit=$?
    if [[ "$commit_exit" -eq 1 ]]; then
        log.info "no changes to commit (manifests already up-to-date)"
        rm -rf "$tmpdir"
        return 0
    elif [[ "$commit_exit" -ne 0 ]]; then
        log.error "git commit failed"
        rm -rf "$tmpdir"
        return "$BRIK_EXIT_EXTERNAL_FAIL"
    fi

    local push_err
    if ! push_err="$(GIT_TERMINAL_PROMPT=0 git -C "$tmpdir" push 2>&1)"; then
        local safe_err
        safe_err="$(printf '%s' "$push_err" | sed 's|://[^@]*@|://***@|')"
        log.error "git push failed: $safe_err"
        rm -rf "$tmpdir"
        return "$BRIK_EXIT_EXTERNAL_FAIL"
    fi

    log.info "manifests pushed successfully to ${safe_url}"
    rm -rf "$tmpdir"
    return 0
}

# Generic poll loop waiting for a GitOps controller to sync.
# Delegates to transverse.wait.until; preserves --check-fn as public flag.
# Usage: deploy.gitops.wait_sync --check-fn <function>
#        [--timeout <s>] [--interval <s>] [--dry-run]
deploy.gitops.wait_sync() {
    local check_fn="" timeout="300" interval="10"
    local dry_run="${BRIK_DRY_RUN:-}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --check-fn) check_fn="$2"; shift 2 ;;
            --timeout)  timeout="$2";  shift 2 ;;
            --interval) interval="$2"; shift 2 ;;
            --dry-run)  dry_run="true"; shift ;;
            *) log.error "unknown option: $1"; return "$BRIK_EXIT_INVALID_INPUT" ;;
        esac
    done

    if [[ -z "$check_fn" ]]; then
        log.error "check-fn is required (--check-fn)"
        return "$BRIK_EXIT_INVALID_INPUT"
    fi

    brik.use transverse.wait
    local -a wait_args=(
        "$check_fn"
        --timeout  "$timeout"
        --interval "$interval"
        --message  "gitops sync"
    )
    [[ "$dry_run" == "true" ]] && wait_args+=(--dry-run)

    transverse.wait.until "${wait_args[@]}"
}

# Preview changes before pushing to config-repo.
# Usage: deploy.gitops.diff --repo <url> --branch <branch> --path <target>
#        --source <rendered> [--git-token-var <VAR>]
# stdout: unified diff
deploy.gitops.diff() {
    local repo="" branch="" target_path="" source_dir="" git_token_var=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --repo)          repo="$2";          shift 2 ;;
            --branch)        branch="$2";        shift 2 ;;
            --path)          target_path="$2";   shift 2 ;;
            --source)        source_dir="$2";    shift 2 ;;
            --git-token-var) git_token_var="$2"; shift 2 ;;
            *) log.error "unknown option: $1"; return "$BRIK_EXIT_INVALID_INPUT" ;;
        esac
    done

    if [[ -z "$repo" ]]; then
        log.error "repo is required (--repo)"
        return "$BRIK_EXIT_INVALID_INPUT"
    fi
    if [[ -z "$branch" ]]; then
        log.error "branch is required (--branch)"
        return "$BRIK_EXIT_INVALID_INPUT"
    fi
    if [[ -z "$target_path" ]]; then
        log.error "path is required (--path)"
        return "$BRIK_EXIT_INVALID_INPUT"
    fi
    if [[ -z "$source_dir" ]]; then
        log.error "source is required (--source)"
        return "$BRIK_EXIT_INVALID_INPUT"
    fi

    pipeline.require_tool git || return "$BRIK_EXIT_MISSING_DEP"

    local clone_url
    clone_url="$(_deploy.gitops._inject_token "$repo" "$git_token_var")" || return $?

    local tmpdir
    tmpdir="$(mktemp -d)"

    brik.use transverse.git
    if ! transverse.git.clone_shallow "$clone_url" "$tmpdir" --branch "$branch"; then
        rm -rf "$tmpdir"
        return "$BRIK_EXIT_EXTERNAL_FAIL"
    fi

    local remote_path="${tmpdir}/${target_path}"
    if [[ ! -d "$remote_path" ]]; then
        # Target path doesn't exist yet -- everything is new
        remote_path="$(mktemp -d)"
    fi

    diff -ruN "$remote_path" "$source_dir" || true
    rm -rf "$tmpdir"
    return 0
}

# Rollback the last deployment in the config-repo.
# Usage: deploy.gitops.rollback --repo <url> --branch <branch> --path <target>
#        [--to-commit <sha>] [--git-token-var <VAR>] [--dry-run]
deploy.gitops.rollback() {
    local repo="" branch="" target_path="" to_commit="" git_token_var=""
    local dry_run="${BRIK_DRY_RUN:-}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --repo)          repo="$2";          shift 2 ;;
            --branch)        branch="$2";        shift 2 ;;
            --path)          target_path="$2";   shift 2 ;;
            --to-commit)     to_commit="$2";     shift 2 ;;
            --git-token-var) git_token_var="$2"; shift 2 ;;
            --dry-run)       dry_run="true";     shift ;;
            *) log.error "unknown option: $1"; return "$BRIK_EXIT_INVALID_INPUT" ;;
        esac
    done

    if [[ -z "$repo" ]]; then
        log.error "repo is required (--repo)"
        return "$BRIK_EXIT_INVALID_INPUT"
    fi
    if [[ -z "$branch" ]]; then
        log.error "branch is required (--branch)"
        return "$BRIK_EXIT_INVALID_INPUT"
    fi

    pipeline.require_tool git || return "$BRIK_EXIT_MISSING_DEP"

    local clone_url
    clone_url="$(_deploy.gitops._inject_token "$repo" "$git_token_var")" || return $?

    local safe_url
    safe_url="$(_deploy.gitops._safe_url "$clone_url")"

    if [[ "$dry_run" == "true" ]]; then
        log.info "[dry-run] would rollback ${safe_url} branch=${branch}"
        return 0
    fi

    local tmpdir
    tmpdir="$(mktemp -d)"

    brik.use transverse.git
    if ! transverse.git.clone_shallow "$clone_url" "$tmpdir" --branch "$branch" --depth 10; then
        rm -rf "$tmpdir"
        return "$BRIK_EXIT_EXTERNAL_FAIL"
    fi

    if [[ -n "$to_commit" ]]; then
        # Restore specific path from a given commit
        if ! git -C "$tmpdir" checkout "$to_commit" -- "${target_path:-.}"; then
            log.error "git checkout to commit $to_commit failed"
            rm -rf "$tmpdir"
            return "$BRIK_EXIT_INVALID_INPUT"
        fi
        if ! git -C "$tmpdir" -c user.email="brik-ci@noreply" -c user.name="Brik CI" \
            commit -m "rollback: restore ${target_path:-repo} to $to_commit"; then
            log.error "git commit failed"
            rm -rf "$tmpdir"
            return "$BRIK_EXIT_EXTERNAL_FAIL"
        fi
    elif [[ -n "$target_path" ]]; then
        # Path-scoped rollback: restore from previous commit
        if ! git -C "$tmpdir" checkout HEAD~1 -- "$target_path"; then
            log.error "git checkout HEAD~1 -- $target_path failed"
            rm -rf "$tmpdir"
            return "$BRIK_EXIT_EXTERNAL_FAIL"
        fi
        if ! git -C "$tmpdir" -c user.email="brik-ci@noreply" -c user.name="Brik CI" \
            commit -m "rollback: revert ${target_path} to previous version"; then
            log.error "git commit failed"
            rm -rf "$tmpdir"
            return "$BRIK_EXIT_EXTERNAL_FAIL"
        fi
    else
        # Unscoped rollback: revert the last commit entirely
        if ! git -C "$tmpdir" -c user.email="brik-ci@noreply" -c user.name="Brik CI" \
            revert --no-edit HEAD; then
            log.error "git revert failed"
            rm -rf "$tmpdir"
            return "$BRIK_EXIT_EXTERNAL_FAIL"
        fi
    fi

    if ! GIT_TERMINAL_PROMPT=0 git -C "$tmpdir" push; then
        log.error "git push failed after rollback"
        rm -rf "$tmpdir"
        return "$BRIK_EXIT_EXTERNAL_FAIL"
    fi

    log.info "rollback pushed successfully to ${safe_url}"
    rm -rf "$tmpdir"
    return 0
}

# Convenience orchestrator: render -> push -> wait_sync.
# Usage: deploy.gitops.run --repo <url> [--branch <branch>] [--path <target>]
#        [--source <local_path>] [--type <kustomize|helm_template|plain>]
#        [--controller <argocd|fluxcd>] [--app-name <name>]
#        [--git-token-var <VAR>] [--auth-token-var <VAR>] [--dry-run]
deploy.gitops.run() {
    local repo="" branch="main" target_path="" source_dir="." render_type=""
    local controller="" app_name="" git_token_var="" auth_token_var=""
    local dry_run="${BRIK_DRY_RUN:-}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --repo)           repo="$2";           shift 2 ;;
            --branch)         branch="$2";         shift 2 ;;
            --path)           target_path="$2";    shift 2 ;;
            --source)         source_dir="$2";     shift 2 ;;
            --type)           render_type="$2";    shift 2 ;;
            --controller)     controller="$2";     shift 2 ;;
            --app-name)       app_name="$2";       shift 2 ;;
            --git-token-var)  git_token_var="$2";  shift 2 ;;
            --auth-token-var) auth_token_var="$2"; shift 2 ;;
            --dry-run)        dry_run="true";      shift ;;
            # Ignore deploy.run passthrough options. --namespace is a
            # k8s-centric field a workflow profile may inject into every env;
            # gitops renders it into the manifests, not as a CLI flag, so
            # tolerate (ignore) it rather than abort.
            --target|--env|--namespace) shift 2 ;;
            *) log.error "unknown option: $1"; return "$BRIK_EXIT_INVALID_INPUT" ;;
        esac
    done

    if [[ -z "$repo" ]]; then
        log.error "repo is required (--repo)"
        return "$BRIK_EXIT_INVALID_INPUT"
    fi

    local -a common_args=()
    [[ "$dry_run" == "true" ]] && common_args+=(--dry-run)

    # Step 1: Render manifests if type is specified
    local rendered_dir="$source_dir"
    if [[ -n "$render_type" ]]; then
        rendered_dir="$(mktemp -d)"
        deploy.gitops.render_manifests \
            --source "$source_dir" \
            --output "$rendered_dir" \
            --type "$render_type" \
            "${common_args[@]}" || return $?
    fi

    # Step 2: Push manifests
    local tag="${BRIK_APP_VERSION:-${BRIK_COMMIT_SHORT_SHA:-unknown}}"
    local -a push_args=(
        --repo "$repo"
        --branch "$branch"
        --path "${target_path:-.}"
        --source "$rendered_dir"
        --message "deploy: update to ${tag}"
    )
    [[ -n "$git_token_var" ]] && push_args+=(--git-token-var "$git_token_var")
    [[ "$tag" != "unknown" ]] && push_args+=(--image-tag "$tag")
    deploy.gitops.push_manifests "${push_args[@]}" "${common_args[@]}" || return $?

    # Clean up rendered temp dir if we created one
    if [[ -n "$render_type" ]]; then
        rm -rf "$rendered_dir"
    fi

    # Step 3: Controller-specific sync
    if [[ "$controller" == "argocd" && -n "$app_name" ]]; then
        brik.use deployments.argocd
        local -a argocd_args=(--app "$app_name")
        [[ -n "$auth_token_var" ]] && argocd_args+=(--auth-token-var "$auth_token_var")
        if [[ "$dry_run" == "true" ]]; then
            log.info "[dry-run] would call: deploy.argocd.sync ${argocd_args[*]}"
        else
            deploy.argocd.sync "${argocd_args[@]}" || {
                log.error "argocd sync failed for app: ${app_name}"
                return "$BRIK_EXIT_EXTERNAL_FAIL"
            }
            deploy.argocd.wait_healthy "${argocd_args[@]}" || {
                log.error "argocd app not healthy: ${app_name}"
                return "$BRIK_EXIT_EXTERNAL_FAIL"
            }
        fi
    elif [[ "$controller" == "argocd" ]]; then
        log.info "argocd: repo updated; sync will be triggered by ArgoCD controller"
    elif [[ "$controller" == "fluxcd" ]]; then
        log.info "fluxcd: flux will auto-reconcile from the updated repo"
    fi

    log.info "gitops deployment completed successfully"
    return 0
}
