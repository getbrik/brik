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
[[ -n "${_BRIK_CORE_DEPLOY_GITOPS_LOADED:-}" ]] && return 0
_BRIK_CORE_DEPLOY_GITOPS_LOADED=1

# Internal helper: inject git token into a repo URL via variable indirection.
# Usage: _deploy.gitops._inject_token <repo_url> <token_var_name>
# stdout: URL with token injected, or original URL if no token var
_deploy.gitops._inject_token() {
    local repo="$1" token_var="$2"
    if [[ -z "$token_var" ]]; then
        printf '%s' "$repo"
        return 0
    fi
    local token="${!token_var:-}"
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
            runtime.require_tool kustomize || return "$BRIK_EXIT_MISSING_DEP"
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
            runtime.require_tool helm || return "$BRIK_EXIT_MISSING_DEP"
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
            # Apply --set values via yq if provided
            if [[ ${#set_values[@]} -gt 0 ]]; then
                runtime.require_tool yq || return "$BRIK_EXIT_MISSING_DEP"
                local sv2
                for sv2 in "${set_values[@]}"; do
                    local key="${sv2%%=*}"
                    local val="${sv2#*=}"
                    find "$output_dir" -name '*.yaml' -o -name '*.yml' | while read -r f; do
                        yq -i ".${key} = \"${val}\"" "$f" 2>/dev/null || true
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

    runtime.require_tool git || return "$BRIK_EXIT_MISSING_DEP"

    # Inject token into URL if provided
    local clone_url
    clone_url="$(_deploy.gitops._inject_token "$repo" "$git_token_var")" || return $?

    local safe_url
    safe_url="$(_deploy.gitops._safe_url "$clone_url")"

    if [[ "$dry_run" == "true" ]]; then
        log.info "[dry-run] would push manifests to ${safe_url} branch=${branch} path=${target_path}"
        return 0
    fi

    # Clone into temp directory with trap-based cleanup
    local tmpdir
    tmpdir="$(mktemp -d)"
    trap 'rm -rf "$tmpdir"' RETURN

    log.info "cloning config repo: $safe_url (branch: $branch)"
    GIT_TERMINAL_PROMPT=0 git clone --depth 1 --branch "$branch" "$clone_url" "$tmpdir" || {
        log.error "git clone failed"
        return "$BRIK_EXIT_EXTERNAL_FAIL"
    }

    # Clear target path and copy new manifests
    local dest="${tmpdir}/${target_path}"
    mkdir -p "$dest"
    rm -rf "${dest:?}"/*
    cp -r "${source_dir}/." "${dest}/" || {
        log.error "failed to copy manifests to config repo"
        return "$BRIK_EXIT_IO_FAILURE"
    }

    # Substitute image tags if --image-tag was provided
    if [[ -n "$image_tag" ]]; then
        runtime.require_tool yq || return "$BRIK_EXIT_MISSING_DEP"
        local manifest_file
        while IFS= read -r manifest_file; do
            yq -i "(.spec.template.spec.containers[]?.image) |= sub(\":[^:]*$\", \":${image_tag}\")" "$manifest_file" 2>/dev/null || true
            yq -i "(.spec.template.spec.initContainers[]?.image) |= sub(\":[^:]*$\", \":${image_tag}\")" "$manifest_file" 2>/dev/null || true
        done < <(find "$dest" -name '*.yaml' -o -name '*.yml')
        log.info "image tags substituted to :${image_tag}"
    fi

    # Commit and push
    git -C "$tmpdir" add . || {
        log.error "git add failed"
        return "$BRIK_EXIT_EXTERNAL_FAIL"
    }

    local commit_exit=0
    git -C "$tmpdir" -c user.email="brik-ci@noreply" -c user.name="Brik CI" commit -m "$message" || commit_exit=$?
    if [[ "$commit_exit" -eq 1 ]]; then
        log.info "no changes to commit (manifests already up-to-date)"
        return 0
    elif [[ "$commit_exit" -ne 0 ]]; then
        log.error "git commit failed"
        return "$BRIK_EXIT_EXTERNAL_FAIL"
    fi

    local push_err
    push_err="$(GIT_TERMINAL_PROMPT=0 git -C "$tmpdir" push 2>&1)" || {
        local safe_err
        safe_err="$(printf '%s' "$push_err" | sed 's|://[^@]*@|://***@|')"
        log.error "git push failed: $safe_err"
        return "$BRIK_EXIT_EXTERNAL_FAIL"
    }

    log.info "manifests pushed successfully to ${safe_url}"
    return 0
}

# Generic poll loop waiting for a GitOps controller to sync.
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

    # Extract function name (first word) for validation
    local fn_name="${check_fn%% *}"
    if ! declare -f "$fn_name" >/dev/null 2>&1; then
        log.error "check-fn is not a declared function: $fn_name"
        return "$BRIK_EXIT_INVALID_INPUT"
    fi

    if ! [[ "$timeout" =~ ^[0-9]+$ ]]; then
        log.error "timeout must be a positive integer, got: $timeout"
        return "$BRIK_EXIT_INVALID_INPUT"
    fi

    if ! [[ "$interval" =~ ^[0-9]+$ ]] || [[ "$interval" -lt 1 ]]; then
        log.error "interval must be a positive integer >= 1, got: $interval"
        return "$BRIK_EXIT_INVALID_INPUT"
    fi

    if [[ "$dry_run" == "true" ]]; then
        log.info "[dry-run] would wait for sync: check-fn=${check_fn} timeout=${timeout}s interval=${interval}s"
        return 0
    fi

    log.info "waiting for sync (timeout=${timeout}s, interval=${interval}s, check-fn=${fn_name})"

    # Split check_fn into array for safe execution
    local -a check_cmd
    read -ra check_cmd <<< "$check_fn"

    local elapsed=0
    while [[ "$elapsed" -lt "$timeout" ]]; do
        if "${check_cmd[@]}" 2>/dev/null; then
            log.info "sync completed after ${elapsed}s"
            return 0
        fi
        log.info "sync pending (${elapsed}s/${timeout}s), waiting ${interval}s..."
        sleep "$interval"
        elapsed=$(( elapsed + interval ))
    done

    log.error "sync timeout after ${timeout}s"
    return "$BRIK_EXIT_TIMEOUT"
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

    runtime.require_tool git || return "$BRIK_EXIT_MISSING_DEP"

    local clone_url
    clone_url="$(_deploy.gitops._inject_token "$repo" "$git_token_var")" || return $?

    local tmpdir
    tmpdir="$(mktemp -d)"
    trap 'rm -rf "$tmpdir"' RETURN

    GIT_TERMINAL_PROMPT=0 git clone --depth 1 --branch "$branch" "$clone_url" "$tmpdir" 2>/dev/null || {
        log.error "git clone failed"
        return "$BRIK_EXIT_EXTERNAL_FAIL"
    }

    local remote_path="${tmpdir}/${target_path}"
    if [[ ! -d "$remote_path" ]]; then
        # Target path doesn't exist yet -- everything is new
        remote_path="$(mktemp -d)"
    fi

    diff -ruN "$remote_path" "$source_dir" || return 0
    # diff returns 0 when identical, 1 when different -- but we invert:
    # identical = return 0, different = diff already printed, return 1
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

    runtime.require_tool git || return "$BRIK_EXIT_MISSING_DEP"

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
    trap 'rm -rf "$tmpdir"' RETURN

    GIT_TERMINAL_PROMPT=0 git clone --depth 10 --branch "$branch" "$clone_url" "$tmpdir" || {
        log.error "git clone failed"
        return "$BRIK_EXIT_EXTERNAL_FAIL"
    }

    if [[ -n "$to_commit" ]]; then
        # Restore specific path from a given commit
        git -C "$tmpdir" checkout "$to_commit" -- "${target_path:-.}" || {
            log.error "git checkout to commit $to_commit failed"
            return "$BRIK_EXIT_INVALID_INPUT"
        }
        git -C "$tmpdir" -c user.email="brik-ci@noreply" -c user.name="Brik CI" \
            commit -m "rollback: restore ${target_path:-repo} to $to_commit" || {
            log.error "git commit failed"
            return "$BRIK_EXIT_EXTERNAL_FAIL"
        }
    elif [[ -n "$target_path" ]]; then
        # Path-scoped rollback: restore from previous commit
        git -C "$tmpdir" checkout HEAD~1 -- "$target_path" || {
            log.error "git checkout HEAD~1 -- $target_path failed"
            return "$BRIK_EXIT_EXTERNAL_FAIL"
        }
        git -C "$tmpdir" -c user.email="brik-ci@noreply" -c user.name="Brik CI" \
            commit -m "rollback: revert ${target_path} to previous version" || {
            log.error "git commit failed"
            return "$BRIK_EXIT_EXTERNAL_FAIL"
        }
    else
        # Unscoped rollback: revert the last commit entirely
        git -C "$tmpdir" -c user.email="brik-ci@noreply" -c user.name="Brik CI" \
            revert --no-edit HEAD || {
            log.error "git revert failed"
            return "$BRIK_EXIT_EXTERNAL_FAIL"
        }
    fi

    GIT_TERMINAL_PROMPT=0 git -C "$tmpdir" push || {
        log.error "git push failed after rollback"
        return "$BRIK_EXIT_EXTERNAL_FAIL"
    }

    log.info "rollback pushed successfully to ${safe_url}"
    return 0
}

# Convenience orchestrator: render -> push -> wait_sync.
# Usage: deploy.gitops.run --repo <url> [--branch <branch>] [--path <target>]
#        [--source <local_path>] [--type <kustomize|helm_template|plain>]
#        [--controller <argocd|fluxcd>] [--app-name <name>]
#        [--git-token-var <VAR>] [--dry-run]
deploy.gitops.run() {
    local repo="" branch="main" target_path="" source_dir="." render_type=""
    local controller="" app_name="" git_token_var=""
    local dry_run="${BRIK_DRY_RUN:-}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --repo)          repo="$2";          shift 2 ;;
            --branch)        branch="$2";        shift 2 ;;
            --path)          target_path="$2";   shift 2 ;;
            --source)        source_dir="$2";    shift 2 ;;
            --type)          render_type="$2";   shift 2 ;;
            --controller)    controller="$2";    shift 2 ;;
            --app-name)      app_name="$2";      shift 2 ;;
            --git-token-var) git_token_var="$2"; shift 2 ;;
            --dry-run)       dry_run="true";     shift ;;
            # Ignore deploy.run passthrough options
            --target|--env)  shift 2 ;;
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
    local tag="${BRIK_DEPLOY_IMAGE_TAG:-${BRIK_APP_VERSION:-${BRIK_COMMIT_SHORT_SHA:-unknown}}}"
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
        brik.use deploy.argocd
        if [[ "$dry_run" == "true" ]]; then
            log.info "[dry-run] would call: deploy.argocd.sync --app ${app_name}"
        else
            deploy.argocd.sync --app "$app_name" || {
                log.error "argocd sync failed for app: ${app_name}"
                return "$BRIK_EXIT_EXTERNAL_FAIL"
            }
            deploy.argocd.wait_healthy --app "$app_name" || {
                log.error "argocd app not healthy: ${app_name}"
                return "$BRIK_EXIT_EXTERNAL_FAIL"
            }
        fi
    elif [[ "$controller" == "argocd" ]]; then
        log.info "argocd: repo updated; sync will be triggered by ArgoCD controller"
    elif [[ "$controller" == "fluxcd" ]]; then
        log.info "fluxcd: flux will auto-reconcile from the updated repo"
    fi

    # Step 4: Rollback test (E2E verification of rollback path)
    if [[ "${BRIK_DEPLOY_ROLLBACK_TEST:-}" == "true" ]]; then
        log.info "rollback test enabled - reverting last deployment"

        if [[ "$controller" == "argocd" && -n "$app_name" ]]; then
            # ArgoCD-native rollback (safer, uses ArgoCD's deployment history)
            if [[ "$dry_run" == "true" ]]; then
                log.info "[dry-run] would call: deploy.argocd.rollback --app ${app_name}"
            else
                deploy.argocd.rollback --app "$app_name" || {
                    log.error "argocd rollback failed for app: ${app_name}"
                    return "$BRIK_EXIT_EXTERNAL_FAIL"
                }
                deploy.argocd.wait_healthy --app "$app_name" || {
                    log.error "argocd app not healthy after rollback: ${app_name}"
                    return "$BRIK_EXIT_EXTERNAL_FAIL"
                }
            fi
        else
            # Git-based rollback
            local -a rollback_args=(
                --repo "$repo"
                --branch "$branch"
            )
            [[ -n "$target_path" ]] && rollback_args+=(--path "$target_path")
            [[ -n "$git_token_var" ]] && rollback_args+=(--git-token-var "$git_token_var")

            deploy.gitops.rollback "${rollback_args[@]}" "${common_args[@]}" || {
                log.error "rollback failed"
                return "$BRIK_EXIT_EXTERNAL_FAIL"
            }
        fi

        log.info "rollback test completed successfully"
    fi

    log.info "gitops deployment completed successfully"
    return 0
}
