#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# @module transverse.config.exports.package
# @description Exports BRIK_PACKAGE_* variables from brik.yml.

# Guard against double-sourcing
[[ -n "${_BRIK_CONFIG_EXPORTS_PACKAGE_LOADED:-}" ]] && return 0
_BRIK_CONFIG_EXPORTS_PACKAGE_LOADED=1

# _config._export_trigger_vars lives in transverse.config.exports.release;
# package shares the helper. brik.use is idempotent (guard-checked).
brik.use transverse.config.exports.release

# Export package-related variables from brik.yml.
# Sets: BRIK_PACKAGE_DOCKER_*
config.export_package_vars() {
    local image
    image="$(config.get '.package.docker.image' '')"
    [[ -n "$image" ]] && export BRIK_PACKAGE_DOCKER_IMAGE="$image"

    local dockerfile
    dockerfile="$(config.get '.package.docker.dockerfile' '')"
    [[ -n "$dockerfile" ]] && export BRIK_PACKAGE_DOCKER_DOCKERFILE="$dockerfile"

    local context
    context="$(config.get '.package.docker.context' '')"
    [[ -n "$context" ]] && export BRIK_PACKAGE_DOCKER_CONTEXT="$context"

    local platforms
    platforms="$(config.get '.package.docker.platforms' '')"
    [[ -n "$platforms" ]] && export BRIK_PACKAGE_DOCKER_PLATFORMS="$platforms"

    local build_args
    build_args="$(config.get '.package.docker.build_args' '')"
    [[ -n "$build_args" ]] && export BRIK_PACKAGE_DOCKER_BUILD_ARGS="$build_args"

    # Optional UI URL for the registry that hosts the published image.
    # The CI/CD push endpoint (e.g. nexus.example.com:8082) is rarely the
    # same as the human-browseable UI (e.g. nexus.example.com:8081 for
    # Nexus 3). This URL is propagated into business.registry.ui_url so
    # the HTML report can produce a clickable link to the image page.
    # Env var BRIK_PACKAGE_REGISTRY_UI_URL set in the runner wins over
    # brik.yml so platform teams can configure it once at the CI level.
    if [[ -z "${BRIK_PACKAGE_REGISTRY_UI_URL:-}" ]]; then
        local ui_url
        ui_url="$(config.get '.package.registry.ui_url' '')"
        [[ -n "$ui_url" ]] && export BRIK_PACKAGE_REGISTRY_UI_URL="$ui_url"
    fi

    _config._export_trigger_vars package PACKAGE

    return 0
}
