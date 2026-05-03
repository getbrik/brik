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
        report.record "package" "tech" "status"      "skipped" 2>/dev/null || true
        report.record "package" "tech" "image_built" "false"   2>/dev/null || true
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

    # Pipeline-report enrichment (chantier 20260502 L2.C.4). business.registry.*,
    # business.signature.* (cosign, F.1), and business.sbom.* (CycloneDX, F.2)
    # are deferred. business.publish.targets is also deferred.
    report.record "package" "tech" "packager" "docker" 2>/dev/null || true
    if [[ -n "${BRIK_PACKAGE_DOCKER_DOCKERFILE:-}" ]]; then
        report.record "package" "tech" "dockerfile" "$BRIK_PACKAGE_DOCKER_DOCKERFILE" 2>/dev/null || true
    fi
    if command -v jq >/dev/null 2>&1; then
        local _img_obj
        _img_obj="$(jq -nc \
            --arg name "$BRIK_PACKAGE_DOCKER_IMAGE" \
            --arg tag  "$_app_tag" \
            '{name: $name, tag: $tag, full_name: ($name + ":" + $tag)}')"
        report.record_object "package" "business" "image" "$_img_obj" 2>/dev/null || true
    fi

    stacks.docker.build "${docker_args[@]}"
    result=$?

    if [[ $result -ne 0 ]]; then
        return "$result"
    fi

    # Source of truth consumed by stages.container_scan: the image was
    # actually produced and is available locally for scanning.
    report.record "package" "tech" "image_built" "true" 2>/dev/null || true
    report.record "package" "tech" "image_ref"   "${BRIK_PACKAGE_DOCKER_IMAGE}:${_app_tag}" 2>/dev/null || true

    # Publish configured targets
    config.export_publish_vars

    # Trigger publish for each target only when intent-to-publish is
    # declared. For docker, that intent now lives in BRIK_PUBLISH_DOCKER_ENABLED
    # (set when the publish.docker block is present), because
    # BRIK_PUBLISH_DOCKER_IMAGE now falls back to package.docker.image and
    # would otherwise always be set on docker projects.
    local -a _publish_targets=(
        "docker:BRIK_PUBLISH_DOCKER_ENABLED"
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
