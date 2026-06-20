#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# @module transverse.config.exports.publish
# @description Exports BRIK_PUBLISH_* variables from brik.yml.

# Guard against double-sourcing
[[ -n "${_BRIK_CONFIG_EXPORTS_PUBLISH_LOADED:-}" ]] && return 0
_BRIK_CONFIG_EXPORTS_PUBLISH_LOADED=1

# Export publish-related variables from brik.yml.
# Sets: BRIK_PUBLISH_NPM_*, BRIK_PUBLISH_DOCKER_*, BRIK_PUBLISH_MAVEN_*,
#       BRIK_PUBLISH_PYPI_*, BRIK_PUBLISH_CARGO_*, BRIK_PUBLISH_NUGET_*
config.export_publish_vars() {
    local val
    local config_file="${BRIK_CONFIG_FILE:-${BRIK_WORKSPACE:-.}/brik.yml}"

    # npm
    val="$(config.get '.publish.npm.registry' '')"
    [[ -n "$val" ]] && export BRIK_PUBLISH_NPM_REGISTRY="$val"

    val="$(config.get '.publish.npm.tag' '')"
    [[ -n "$val" ]] && export BRIK_PUBLISH_NPM_TAG="$val"

    val="$(config.get '.publish.npm.access' '')"
    [[ -n "$val" ]] && export BRIK_PUBLISH_NPM_ACCESS="$val"

    val="$(config.get '.publish.npm.token_var' '')"
    [[ -n "$val" ]] && export BRIK_PUBLISH_NPM_TOKEN_VAR="$val"

    # docker -- fall back to package.docker.image when publish.docker.image
    # is absent (single source of truth).
    val="$(config.get '.publish.docker.image' '')"
    [[ -z "$val" ]] && val="$(config.get '.package.docker.image' '')"
    [[ -n "$val" ]] && export BRIK_PUBLISH_DOCKER_IMAGE="$val"

    # Intent-to-publish flag: true when the user declared a publish.docker
    # block (with image, registry, or credentials). Decoupled from
    # BRIK_PUBLISH_DOCKER_IMAGE because the latter now falls back to
    # package.docker.image and would always be set on docker projects.
    if [[ "$(yq '.publish.docker // null' "$config_file" 2>/dev/null)" != "null" ]]; then
        export BRIK_PUBLISH_DOCKER_ENABLED="true"
    fi

    val="$(config.get '.publish.docker.registry' '')"
    [[ -n "$val" ]] && export BRIK_PUBLISH_DOCKER_REGISTRY="$val"

    val="$(config.get '.publish.docker.tags | join(",")' '')"
    [[ -n "$val" ]] && export BRIK_PUBLISH_DOCKER_TAGS="$val"

    val="$(config.get '.publish.docker.username_var' '')"
    [[ -n "$val" ]] && export BRIK_PUBLISH_DOCKER_USERNAME_VAR="$val"

    val="$(config.get '.publish.docker.password_var' '')"
    [[ -n "$val" ]] && export BRIK_PUBLISH_DOCKER_PASSWORD_VAR="$val"

    # maven
    val="$(config.get '.publish.maven.repository' '')"
    [[ -n "$val" ]] && export BRIK_PUBLISH_MAVEN_REPOSITORY="$val"

    val="$(config.get '.publish.maven.username_var' '')"
    [[ -n "$val" ]] && export BRIK_PUBLISH_MAVEN_USERNAME_VAR="$val"

    val="$(config.get '.publish.maven.password_var' '')"
    [[ -n "$val" ]] && export BRIK_PUBLISH_MAVEN_PASSWORD_VAR="$val"

    # pypi
    val="$(config.get '.publish.pypi.repository' '')"
    [[ -n "$val" ]] && export BRIK_PUBLISH_PYPI_REPOSITORY="$val"

    val="$(config.get '.publish.pypi.token_var' '')"
    [[ -n "$val" ]] && export BRIK_PUBLISH_PYPI_TOKEN_VAR="$val"

    # cargo
    val="$(config.get '.publish.cargo.registry' '')"
    [[ -n "$val" ]] && export BRIK_PUBLISH_CARGO_REGISTRY="$val"

    val="$(config.get '.publish.cargo.index' '')"
    [[ -n "$val" ]] && export BRIK_PUBLISH_CARGO_INDEX="$val"

    val="$(config.get '.publish.cargo.token_var' '')"
    [[ -n "$val" ]] && export BRIK_PUBLISH_CARGO_TOKEN_VAR="$val"

    # nuget
    val="$(config.get '.publish.nuget.source' '')"
    [[ -n "$val" ]] && export BRIK_PUBLISH_NUGET_SOURCE="$val"

    val="$(config.get '.publish.nuget.token_var' '')"
    [[ -n "$val" ]] && export BRIK_PUBLISH_NUGET_TOKEN_VAR="$val"

    return 0
}
