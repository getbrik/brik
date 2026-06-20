#!/usr/bin/env bash
# @module stages/package
# @description Package stage - container build via brik-lib.

# Package stage: build container image via brik-lib.
# Usage: stages.package <context_file>
stages.package() {
    # context_file positionally passed by stage.run; unused here
    # migration (pipeline.run records tech.status from rc; config-skip path
    # uses report.record directly).
    # shellcheck disable=SC2034
    local context_file="$1"
    local result=0 rc=0

    config.export_package_vars

    # SC20: honour package.trigger.{on-tag, on-main, on-feature, manual}.
    # Legacy compat preserved: unconfigured trigger -> always run.
    # Defensive: a test harness stubbing brik.use as a no-op leaves
    # gating.should_run_stage undefined; treat that as "run".
    brik.use transverse.gating 2>/dev/null || true
    if declare -f gating.should_run_stage >/dev/null 2>&1; then
        if ! gating.should_run_stage PACKAGE; then
            log.info "package stage skipped: trigger conditions not met"
            report.record "package" "tech" "status" "skipped"          2>/dev/null || true
            report.record "package" "tech" "kind"   "not-applicable"   2>/dev/null || true
            return 0
        fi
    fi

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

        local _reg_obj
        _reg_obj="$(_stages.package._parse_registry "$BRIK_PACKAGE_DOCKER_IMAGE" "${BRIK_PACKAGE_REGISTRY_UI_URL:-}")"
        if [[ -n "$_reg_obj" ]]; then
            report.record_object "package" "business" "registry" "$_reg_obj" 2>/dev/null || true
        fi
    fi

    local _build_start_ms _build_end_ms _build_dur_ms
    _build_start_ms="$(_helpers.epoch_ms 2>/dev/null || printf '0')"
    stacks.docker.build "${docker_args[@]}"
    result=$?
    _build_end_ms="$(_helpers.epoch_ms 2>/dev/null || printf '0')"
    _build_dur_ms=$(( _build_end_ms - _build_start_ms ))
    [[ "$_build_dur_ms" -lt 0 ]] && _build_dur_ms=0
    report.record "package" "tech" "build_duration_ms" "$_build_dur_ms" 2>/dev/null || true

    if [[ $result -ne 0 ]]; then
        return "$result"
    fi

    report.record "package" "tech" "image_built" "true" 2>/dev/null || true
    report.record "package" "tech" "image_ref"   "${BRIK_PACKAGE_DOCKER_IMAGE}:${_app_tag}" 2>/dev/null || true

    # Capture the manifest digest from RepoDigests after push. docker
    # inspect on a pushed image yields entries like
    # "<image>@sha256:<hash>" -- we keep the sha256 part as the canonical
    # digest container-scan will scan. Silent fallback when no RepoDigests
    # exist (local-only builds in dev or buildx-pushed images that the
    # daemon hasn't recorded) so digest stays absent rather than mis-reported.
    local _digest_raw _digest
    _digest_raw="$(docker inspect --format='{{index .RepoDigests 0}}' \
                    "${BRIK_PACKAGE_DOCKER_IMAGE}:${_app_tag}" 2>/dev/null || true)"
    _digest="${_digest_raw##*@}"
    if [[ "$_digest" =~ ^sha256: ]] && command -v jq >/dev/null 2>&1; then
        local _img_with_digest
        _img_with_digest="$(jq -nc \
            --arg name   "$BRIK_PACKAGE_DOCKER_IMAGE" \
            --arg tag    "$_app_tag" \
            --arg digest "$_digest" \
            '{name: $name, tag: $tag, full_name: ($name + ":" + $tag), digest: $digest}')"
        report.record_object "package" "business" "image" "$_img_with_digest" 2>/dev/null || true
    fi

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
                if [[ "$_target" == "docker" ]]; then
                    _stages.package._record_pushed_image \
                        "${BRIK_PACKAGE_DOCKER_IMAGE:-}" "${_app_tag:-}"
                fi
            fi
        done
    fi

    return 0
}

# After a successful docker publish, RepoDigests reflects THIS push: record
# the pushed flag and re-capture the manifest digest. The pre-publish capture
# above can carry a stale digest from a byte-identical previous run (shared
# daemon); evidence signing gates on image_pushed so only artifacts that
# actually reached the registry are attested.
_stages.package._record_pushed_image() {
    local image="$1" tag="$2"
    [[ -z "$image" || -z "$tag" ]] && return 0
    report.record "package" "tech" "image_pushed" "true" 2>/dev/null || true
    local _digest_raw _digest
    _digest_raw="$(docker inspect --format='{{index .RepoDigests 0}}' \
                    "${image}:${tag}" 2>/dev/null || true)"
    _digest="${_digest_raw##*@}"
    if [[ "$_digest" =~ ^sha256: ]] && command -v jq >/dev/null 2>&1; then
        local _img
        _img="$(jq -nc \
            --arg name   "$image" \
            --arg tag    "$tag" \
            --arg digest "$_digest" \
            '{name: $name, tag: $tag, full_name: ($name + ":" + $tag), digest: $digest}')"
        report.record_object "package" "business" "image" "$_img" 2>/dev/null || true
    fi
    return 0
}

# Parse a Docker image reference into {host, namespace, repository}. Mirrors
# Docker CLI's normalization: bare names default to docker.io/library, and
# a 2-segment ref without a "." or ":" in the first segment is treated as
# a Docker Hub user/repo pair. When a non-empty <ui_url> is provided, the
# emitted JSON also carries a "ui_url" field (browseable URL distinct from
# the docker push endpoint -- Nexus 3 splits these on ports 8081 vs 8082).
# Usage: _stages.package._parse_registry <image_ref> [<ui_url>]
# Prints the JSON object on stdout, or empty on error.
_stages.package._parse_registry() {
    local _ref="$1"
    local _ui_url="${2:-}"
    [[ -z "$_ref" ]] && return 0
    command -v jq >/dev/null 2>&1 || return 0

    # Strip an optional ":tag" so registry parsing only sees the path.
    # A tag is the substring after the LAST ":" iff there is no "/" after
    # it (otherwise that ":" is a host port). Without this guard, refs like
    # "nexus.host:8082/brik/app" would lose their port.
    local _path="$_ref"
    if [[ "$_ref" == *":"* ]]; then
        local _tail="${_ref##*:}"
        if [[ "$_tail" != *"/"* ]]; then
            _path="${_ref%:*}"
        fi
    fi

    local _host="" _namespace="" _repo=""
    local _first="${_path%%/*}"
    local _rest=""
    [[ "$_path" == */* ]] && _rest="${_path#*/}"

    if [[ -z "$_rest" ]]; then
        # Single segment, e.g. "redis" -> docker.io/library/redis
        _host="docker.io"
        _namespace="library"
        _repo="$_path"
    elif [[ "$_first" == *.* || "$_first" == *:* ]]; then
        # First segment looks like a host (contains a dot or port).
        _host="$_first"
        if [[ "$_rest" == */* ]]; then
            _namespace="${_rest%/*}"
            _repo="${_rest##*/}"
        else
            _namespace=""
            _repo="$_rest"
        fi
    else
        # First segment is a Docker Hub user; rest is the repository
        # (possibly with further nesting, but Docker Hub flat-only is the
        # common case).
        _host="docker.io"
        _namespace="$_first"
        _repo="$_rest"
    fi

    jq -nc \
        --arg host       "$_host" \
        --arg namespace  "$_namespace" \
        --arg repository "$_repo" \
        --arg ui_url     "$_ui_url" \
        '{host: $host, namespace: $namespace, repository: $repository}
         + (if $ui_url == "" then {} else {ui_url: $ui_url} end)'
}
