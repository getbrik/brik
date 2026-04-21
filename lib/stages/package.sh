#!/usr/bin/env bash
# @module stages/package
# @description Package stage - container build via brik-lib.

# Package stage: build container image via brik-lib.
# Usage: stages.package <context_file>
stages.package() {
    # context_file positionally passed by stage.run; unused here after §4.2
    # migration (pipeline.run records tech.status from rc; config-skip path
    # uses report.record directly).
    # shellcheck disable=SC2034
    local context_file="$1"
    local result=0 rc=0

    config.export_package_vars

    brik.use stacks.docker

    log.info "package stage - container build"

    if [[ -z "${BRIK_PACKAGE_DOCKER_IMAGE:-}" ]]; then
        log.warn "no docker image configured, skipping package stage"
        report.record "package" "tech" "status" "skipped" 2>/dev/null || true
        return 0
    fi

    local _app_tag="${BRIK_APP_VERSION:-${BRIK_COMMIT_SHORT_SHA:-latest}}"

    local docker_args=("${BRIK_WORKSPACE}")
    [[ -n "${BRIK_PACKAGE_DOCKER_DOCKERFILE:-}" ]] && docker_args+=(--file "$BRIK_PACKAGE_DOCKER_DOCKERFILE")
    docker_args+=(--tag "${BRIK_PACKAGE_DOCKER_IMAGE}:${_app_tag}")
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

    log.info "building image: ${BRIK_PACKAGE_DOCKER_IMAGE}:${_app_tag}"

    stacks.docker.build "${docker_args[@]}"
    result=$?

    if [[ $result -ne 0 ]]; then
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
        "nuget:BRIK_PUBLISH_NUGET_TOKEN_VAR"
    )

    # Pre-scan: only load the publish module if at least one target is configured
    brik.use transverse.env
    local _has_publish=false _entry _target _detect_var _detect_val
    for _entry in "${_publish_targets[@]}"; do
        _detect_var="${_entry#*:}"
        _detect_val="$(transverse.env.resolve_indirect "$_detect_var")"
        if [[ -n "$_detect_val" ]]; then
            _has_publish=true
            break
        fi
    done

    if [[ "$_has_publish" == "true" ]]; then
        for _entry in "${_publish_targets[@]}"; do
            _target="${_entry%%:*}"
            _detect_var="${_entry#*:}"
            _detect_val="$(transverse.env.resolve_indirect "$_detect_var")"
            if [[ -n "$_detect_val" ]]; then
                log.info "publishing ${_target}"
                if ! brik.use "package-managers.${_target}"; then
                    log.error "unsupported publish target: ${_target}"
                    return "$BRIK_EXIT_CONFIG_ERROR"
                fi
                local _publish_fn="pkg.${_target}.publish"
                if ! declare -f "$_publish_fn" >/dev/null 2>&1; then
                    log.error "publish function not found: $_publish_fn"
                    return "$BRIK_EXIT_CONFIG_ERROR"
                fi
                rc=0
                "$_publish_fn" || rc=$?
                if [[ $rc -ne 0 ]]; then
                    return "$rc"
                fi
            fi
        done
    fi

    # pipeline.run records tech.status=success from rc (see commit cf719f5).
    return 0
}
