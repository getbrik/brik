#!/usr/bin/env bash
# @module deploy.ssh
# @requires rsync ssh
# @description Deploy via rsync over SSH, with optional remote restart command.

# Guard against double-sourcing
[[ -n "${_BRIK_CORE_DEPLOY_SSH_LOADED:-}" ]] && return 0
_BRIK_CORE_DEPLOY_SSH_LOADED=1

# Deploy files via rsync over SSH.
# Usage: deploy.ssh.run --host <host> --remote-path <path>
#        [--manifest <source>] [--restart-cmd <cmd>] [--dry-run]
deploy.ssh.run() {
    local host="" remote_path="" restart_cmd="" manifest=""
    local dry_run="${BRIK_DRY_RUN:-}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --host)         host="$2";         shift 2 ;;
            --remote-path)  remote_path="$2";  shift 2 ;;
            --restart-cmd)  restart_cmd="$2";  shift 2 ;;
            --manifest)     manifest="$2";     shift 2 ;;
            --dry-run)      dry_run="true";    shift ;;
            # Ignore deploy.run passthrough options
            --target|--env) shift 2 ;;
            *) log.error "unknown option: $1"; return "$BRIK_EXIT_INVALID_INPUT" ;;
        esac
    done

    if [[ -z "$host" ]]; then
        log.error "host is required (--host)"
        return "$BRIK_EXIT_INVALID_INPUT"
    fi

    if [[ -z "$remote_path" ]]; then
        log.error "remote-path is required (--remote-path)"
        return "$BRIK_EXIT_INVALID_INPUT"
    fi

    runtime.require_tool rsync || return "$BRIK_EXIT_MISSING_DEP"
    runtime.require_tool ssh   || return "$BRIK_EXIT_MISSING_DEP"

    local -a ssh_opts=(-o BatchMode=yes -o StrictHostKeyChecking=yes)

    # Determine source files: --manifest or current directory
    local source="${manifest:-.}"

    # Build rsync command
    local -a rsync_cmd=(rsync -avz --delete -e "ssh ${ssh_opts[*]}")
    [[ "$dry_run" == "true" ]] && rsync_cmd+=(--dry-run)
    rsync_cmd+=("${source}/" "${host}:${remote_path}/")

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
        _unsafe_chars="$(printf '%s' "$restart_cmd" | tr -d '[:alnum:][:blank:]._/-')"
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
