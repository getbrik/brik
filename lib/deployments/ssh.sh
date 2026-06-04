#!/usr/bin/env bash
# @module deploy.ssh
# @requires rsync ssh
# @description Deploy via rsync over SSH, with optional remote restart command.

# Guard against double-sourcing
[[ -n "${_BRIK_DEPLOYMENTS_SSH_LOADED:-}" ]] && return 0
_BRIK_DEPLOYMENTS_SSH_LOADED=1

# Deploy files via rsync over SSH.
# Usage: deploy.ssh.run --host <host> --path <remote_path>
#        [--source <local_path>] [--restart-cmd <cmd>] [--dry-run]
deploy.ssh.run() {
    local host="" remote_path="" restart_cmd="" source=""
    local dry_run="${BRIK_DRY_RUN:-}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --host)         host="$2";         shift 2 ;;
            --path)         remote_path="$2";  shift 2 ;;
            --restart-cmd)  restart_cmd="$2";  shift 2 ;;
            --source)       source="$2";       shift 2 ;;
            --dry-run)      dry_run="true";    shift ;;
            # Ignore deploy.run passthrough options. --namespace is a
            # k8s-centric field a workflow profile may inject into every env;
            # ssh has no concept of a namespace, so tolerate (ignore) it
            # rather than abort.
            --target|--env|--namespace) shift 2 ;;
            *) log.error "unknown option: $1"; return "$BRIK_EXIT_INVALID_INPUT" ;;
        esac
    done

    if [[ -z "$host" ]]; then
        log.error "host is required (--host)"
        return "$BRIK_EXIT_INVALID_INPUT"
    fi

    if [[ -z "$remote_path" ]]; then
        log.error "path is required (--path)"
        return "$BRIK_EXIT_INVALID_INPUT"
    fi

    pipeline.require_tool rsync || return "$BRIK_EXIT_MISSING_DEP"
    pipeline.require_tool ssh   || return "$BRIK_EXIT_MISSING_DEP"

    # Setup SSH agent with key from SSH_PRIVATE_KEY if available
    brik.use transverse.ssh
    transverse.ssh.setup_agent

    local strict_host="${BRIK_SSH_STRICT_HOST_KEY:-yes}"
    local -a ssh_opts=(-o BatchMode=yes -o "StrictHostKeyChecking=${strict_host}")

    # Determine source files: --source or current directory
    local src="${source:-.}"

    # Build rsync command. Exclude internal CI state directories that the
    # workspace accumulates between stages: .ssh holds the deployer key
    # plus an ssh-agent socket that rsync cannot transfer (--exclude
    # avoids "failed to set times on agent socket" errors), and .kube
    # caches the kubeconfig copy.
    local -a rsync_cmd=(
        rsync -avz --delete
        --exclude='.ssh'
        --exclude='.kube'
        --exclude='.brik-logs'
        --exclude='.brik-keep'
        -e "ssh ${ssh_opts[*]}"
    )
    [[ "$dry_run" == "true" ]] && rsync_cmd+=(--dry-run)
    rsync_cmd+=("${src}/" "${host}:${remote_path}/")

    if [[ "$dry_run" == "true" ]]; then
        log.info "[dry-run] ${rsync_cmd[*]}"
    else
        log.info "running: ${rsync_cmd[*]}"
    fi

    "${rsync_cmd[@]}" || {
        log.error "rsync failed"
        return "$BRIK_EXIT_EXTERNAL_FAIL"
    }

    # Execute restart command via ssh if provided
    if [[ -n "$restart_cmd" ]]; then
        # restart_cmd is trusted input from brik.yml - validated for basic safety
        local _unsafe_chars
        _unsafe_chars="$(printf '%s' "$restart_cmd" | tr -d "[:alnum:][:blank:]._/='\"\\-")"
        if [[ -n "$_unsafe_chars" ]] || [[ "$restart_cmd" =~ $'\n'|$'\r' ]]; then
            log.error "restart-cmd contains unsafe characters: use simple commands only"
            return "$BRIK_EXIT_INVALID_INPUT"
        fi
        if [[ "$dry_run" == "true" ]]; then
            log.info "[dry-run] would ssh ${host} -- ${restart_cmd}"
        else
            log.info "restarting service on ${host}: ${restart_cmd}"
            ssh "${ssh_opts[@]}" "$host" "$restart_cmd" || {
                log.error "remote restart command failed"
                return "$BRIK_EXIT_EXTERNAL_FAIL"
            }
        fi
    fi

    log.info "ssh deployment completed successfully"
    return 0
}

