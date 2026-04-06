#!/usr/bin/env bash
# @module stages/package
# @description Package stage - container build via brik-lib.

# Package stage: build container image via brik-lib.
# Usage: stages.package <context_file>
stages.package() {
    local context_file="$1"
    local result=0 rc=0

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

    # Add build args (split on comma, safe from glob expansion)
    if [[ -n "${BRIK_PACKAGE_DOCKER_BUILD_ARGS:-}" ]]; then
        local -a _build_args
        IFS=',' read -ra _build_args <<< "${BRIK_PACKAGE_DOCKER_BUILD_ARGS}"
        local arg
        for arg in "${_build_args[@]}"; do
            docker_args+=(--build-arg "$arg")
        done
    fi

    log.info "building image: ${BRIK_PACKAGE_DOCKER_IMAGE}:${BRIK_VERSION:-latest}"

    build.docker.run "${docker_args[@]}"
    result=$?

    if [[ $result -ne 0 ]]; then
        context.set "$context_file" "BRIK_PACKAGE_STATUS" "failed"
        return "$result"
    fi

    # Publish configured targets
    config.export_publish_vars

    local -a _publish_targets=(
        "docker:BRIK_PUBLISH_DOCKER_IMAGE"
        "npm:BRIK_PUBLISH_NPM_TOKEN_VAR"
        "maven:BRIK_PUBLISH_MAVEN_REPOSITORY"
        "pypi:BRIK_PUBLISH_PYPI_TOKEN_VAR"
        "cargo:BRIK_PUBLISH_CARGO_TOKEN_VAR"
        "nuget:BRIK_PUBLISH_NUGET_API_KEY_VAR"
    )

    # Pre-scan: only load the publish module if at least one target is configured
    local _has_publish=false _entry _target _detect_var
    for _entry in "${_publish_targets[@]}"; do
        _detect_var="${_entry#*:}"
        if [[ -n "${!_detect_var}" ]]; then
            _has_publish=true
            break
        fi
    done

    if [[ "$_has_publish" == "true" ]]; then
        brik.use publish

        for _entry in "${_publish_targets[@]}"; do
            _target="${_entry%%:*}"
            _detect_var="${_entry#*:}"
            if [[ -n "${!_detect_var}" ]]; then
                log.info "publishing ${_target}"
                rc=0
                publish.run --target "$_target" || rc=$?
                if [[ $rc -ne 0 ]]; then
                    context.set "$context_file" "BRIK_PACKAGE_STATUS" "failed"
                    return "$rc"
                fi
            fi
        done
    fi

    context.set "$context_file" "BRIK_PACKAGE_STATUS" "success"
    return 0
}
