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
    local host="" remote_path="" restart_cmd="" source="" image_ref=""
    local dry_run="${BRIK_DRY_RUN:-}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --host)         host="$2";         shift 2 ;;
            --path)         remote_path="$2";  shift 2 ;;
            --restart-cmd)  restart_cmd="$2";  shift 2 ;;
            --source)       source="$2";       shift 2 ;;
            --image-ref)    image_ref="$2";    shift 2 ;;
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

    local -a ssh_opts=(-o BatchMode=yes)
    transverse.ssh.host_opts ssh_opts "$host" || return "$?"

    # Determine source files: --source or current directory
    local src="${source:-.}"

    # When a digest-pinned ref is supplied, sync a staged copy with image refs
    # pinned in any YAML, never mutating the user's source tree.
    local _staged=""
    if [[ -n "$image_ref" ]]; then
        brik.use deployments._image_ref
        if ! deploy.image_ref.is_pinned "$image_ref"; then
            log.error "refusing a non-digest-pinned image ref: ${image_ref}"
            return "$BRIK_EXIT_INVALID_INPUT"
        fi
        brik.use transverse.yaml
        _staged="$(mktemp -d)"
        cp -r "${src}/." "${_staged}/"
        local _yaml_file
        while IFS= read -r _yaml_file; do
            transverse.yaml.set_image "$_yaml_file" \
                ".spec.template.spec.containers[]?.image" "$image_ref" 2>/dev/null || true
            transverse.yaml.set_image "$_yaml_file" \
                ".services[]?.image" "$image_ref" 2>/dev/null || true
        done < <(find "$_staged" \( -name '*.yaml' -o -name '*.yml' \))
        src="$_staged"
    fi

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

    local _rsync_rc=0
    "${rsync_cmd[@]}" || _rsync_rc=$?
    [[ -n "$_staged" ]] && rm -rf "$_staged"
    if [[ "$_rsync_rc" -ne 0 ]]; then
        log.error "rsync failed"
        return "$BRIK_EXIT_EXTERNAL_FAIL"
    fi

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

# Read back the live image digest of an SSH deploy.
# A generic rsync+restart deploy exposes no live image query, so the running
# image digest cannot be read back. Reading the local synced payload would be
# circular -- it reflects what was pushed, not the running state -- so we report
# "unsupported" rather than a tautological match that would be a false green.
# A deploy that mandates digest verification must therefore fail closed on this
# target rather than trust an unverifiable read-back.
# stdout: "unsupported"
deploy.ssh.get_deployed_digest() {
    printf 'unsupported'
    return 0
}

