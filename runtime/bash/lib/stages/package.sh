#!/usr/bin/env bash
# @module stages/package
# @description Package stage - container build via brik-lib.

# Package stage: build container image via brik-lib.
# Usage: stages.package <context_file>
stages.package() {
    local context_file="$1"

    config.export_package_vars

    brik.use build.docker

    log.info "package stage - container build"

    if [[ -z "${BRIK_PACKAGE_DOCKER_IMAGE:-}" ]]; then
        log.warn "no docker image configured, skipping package stage"
        context.set "$context_file" "BRIK_PACKAGE_STATUS" "skipped"
        return 0
    fi

    local docker_args=("${BRIK_WORKSPACE}")
    [[ -n "${BRIK_PACKAGE_DOCKER_DOCKERFILE:-}" ]] && docker_args+=(--file "$BRIK_PACKAGE_DOCKER_DOCKERFILE")
    docker_args+=(--tag "${BRIK_PACKAGE_DOCKER_IMAGE}:${BRIK_VERSION:-latest}")
    [[ -n "${BRIK_PACKAGE_DOCKER_CONTEXT:-}" ]] && docker_args+=(--context "$BRIK_PACKAGE_DOCKER_CONTEXT")

    # Add build args
    if [[ -n "${BRIK_PACKAGE_DOCKER_BUILD_ARGS:-}" ]]; then
        local old_ifs="${IFS}"
        IFS=','
        local arg
        for arg in $BRIK_PACKAGE_DOCKER_BUILD_ARGS; do
            docker_args+=(--build-arg "$arg")
        done
        IFS="${old_ifs}"
    fi

    log.info "building image: ${BRIK_PACKAGE_DOCKER_IMAGE}:${BRIK_VERSION:-latest}"

    build.docker.run "${docker_args[@]}"
    local result=$?

    if [[ $result -eq 0 ]]; then
        context.set "$context_file" "BRIK_PACKAGE_STATUS" "success"
    else
        context.set "$context_file" "BRIK_PACKAGE_STATUS" "failed"
    fi

    return "$result"
}
