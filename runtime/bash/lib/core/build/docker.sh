#!/usr/bin/env bash
# @module build.docker
# @requires docker
# @description Build Docker images.

# Guard against double-sourcing
[[ -n "${_BRIK_CORE_BUILD_DOCKER_LOADED:-}" ]] && return 0
_BRIK_CORE_BUILD_DOCKER_LOADED=1

# Build a Docker image.
# Usage: build.docker.run <workspace> [--file <Dockerfile>] [--tag <tag>]
#        [--context <path>] [--build-arg <key=value>]...
build.docker.run() {
    local workspace="$1"
    shift
    local dockerfile="" tag="" context="" dry_run="${BRIK_DRY_RUN:-}"
    local -a build_args=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --file) dockerfile="$2"; shift 2 ;;
            --tag) tag="$2"; shift 2 ;;
            --context) context="$2"; shift 2 ;;
            --build-arg) build_args+=("--build-arg" "$2"); shift 2 ;;
            --dry-run) dry_run="true"; shift ;;
            *) log.error "unknown option: $1"; return "$BRIK_EXIT_INVALID_INPUT" ;;
        esac
    done

    runtime.require_dir "$workspace" || return "$BRIK_EXIT_IO_FAILURE"

    # Defaults
    [[ -z "$dockerfile" ]] && dockerfile="${workspace}/Dockerfile"
    [[ -z "$context" ]] && context="$workspace"
    [[ -z "$tag" ]] && tag="${BRIK_PROJECT_NAME:-project}:${BRIK_VERSION:-latest}"

    runtime.require_file "$dockerfile" || return "$BRIK_EXIT_IO_FAILURE"
    runtime.require_tool docker || return "$BRIK_EXIT_MISSING_DEP"

    # Build the command
    local -a cmd=(docker build -f "$dockerfile" -t "$tag")
    if [[ ${#build_args[@]} -gt 0 ]]; then
        cmd+=("${build_args[@]}")
    fi
    cmd+=("$context")

    if [[ "$dry_run" == "true" ]]; then
        log.info "[dry-run] ${cmd[*]}"
        return 0
    fi

    log.info "building Docker image: $tag"
    "${cmd[@]}" || {
        log.error "build failed"
        return "$BRIK_EXIT_EXTERNAL_FAIL"
    }

    log.info "build completed successfully"
    return 0
}
