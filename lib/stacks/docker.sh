#!/usr/bin/env bash
# @module stacks/docker
# @requires docker
# @description Build Docker images.

# Guard against double-sourcing
[[ -n "${_BRIK_STACKS_DOCKER_LOADED:-}" ]] && return 0
_BRIK_STACKS_DOCKER_LOADED=1

# Build a Docker image.
# Usage: stacks.docker.build <workspace> [--file <Dockerfile>] [--tag <tag>]
#        [--context <path>] [--build-arg <key=value>]...
stacks.docker.build() {
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

    pipeline.require_dir "$workspace" || return "$BRIK_EXIT_IO_FAILURE"

    # Defaults
    [[ -z "$dockerfile" ]] && dockerfile="${workspace}/Dockerfile"
    [[ -z "$context" ]] && context="$workspace"
    [[ -z "$tag" ]] && tag="${BRIK_PROJECT_NAME:-project}:${BRIK_APP_VERSION:-${BRIK_COMMIT_SHORT_SHA:-latest}}"

    pipeline.require_file "$dockerfile" || return "$BRIK_EXIT_IO_FAILURE"
    pipeline.require_tool docker || return "$BRIK_EXIT_MISSING_DEP"

    _stacks.docker._ensure_buildx

    # Use docker buildx (BuildKit) -- the legacy `docker build` is deprecated
    # in Docker Engine 27+ and removed in some 28+ distributions. --load
    # places the produced image in the local docker store so subsequent
    # stages (publish, container scan) can pull it; the publish step issues
    # its own --push later via lib/package-managers/docker.sh.
    local -a cmd=(docker buildx build --load -f "$dockerfile" -t "$tag")
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

# _stacks.docker._ensure_buildx -- idempotently ensure a buildx builder.
#
# Reuses an existing 'brik' builder if available, otherwise creates one
# with the docker-container driver. Falls back silently to whatever
# builder is currently active when buildx itself is missing or refuses to
# create a new builder (restricted seccomp, daemon flags, ...). Never
# fatal -- the caller's `docker buildx build` will surface a clean error
# if buildx is genuinely unavailable.
_stacks.docker._ensure_buildx() {
    command -v docker >/dev/null 2>&1 || return 0
    docker buildx inspect brik >/dev/null 2>&1 && return 0
    docker buildx create --use --name brik --driver docker-container >/dev/null 2>&1 || {
        log.warn "could not create buildx builder 'brik'; falling back to default builder"
        return 0
    }
    log.info "created buildx builder 'brik'"
    return 0
}
