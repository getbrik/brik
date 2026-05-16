#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# @module transverse.config.exports.runner
# @description Resolves and exports BRIK_RUNNER_IMAGE based on stack + version.

# Guard against double-sourcing
[[ -n "${_BRIK_CONFIG_EXPORTS_RUNNER_LOADED:-}" ]] && return 0
_BRIK_CONFIG_EXPORTS_RUNNER_LOADED=1

# Export runner image variable from stack + version.
# Sets: BRIK_RUNNER_IMAGE
#
# Respects a wrapper-supplied value (Jenkins injects the per-stage image
# via `-e BRIK_RUNNER_IMAGE=...`, GitLab can derive it from CI_JOB_IMAGE)
# so report.write_fragment records the actual execution image, not the
# project's stack default. Falls back to stack-derived resolution only
# when no explicit image was injected.
config.export_runner_vars() {
    if [[ -n "${BRIK_RUNNER_IMAGE:-}" ]]; then
        return 0
    fi

    local stack="${BRIK_BUILD_STACK:-auto}"
    local version="${BRIK_BUILD_STACK_VERSION:-}"

    if [[ "$stack" == "auto" || -z "$stack" ]]; then
        export BRIK_RUNNER_IMAGE="${BRIK_RUNNER_REGISTRY:-ghcr.io/getbrik}/brik-runner-base:latest"
        return 0
    fi

    # Source runner-images if not already loaded.
    # Path: lib/transverse/config/exports/runner.sh -> lib/pipeline/runner-images.sh
    # (../../../pipeline relative to this file).
    local runner_file="${BASH_SOURCE[0]%/*}/../../../pipeline/runner-images.sh"
    if [[ -f "$runner_file" && -z "${_BRIK_RUNNER_IMAGES_LOADED:-}" ]]; then
        # shellcheck source=../../../pipeline/runner-images.sh
        . "$runner_file"
    fi

    local image
    if image="$(runner.resolve_image "$stack" "$version")"; then
        export BRIK_RUNNER_IMAGE="$image"
    else
        log.warn "no runner image found for stack '$stack' version '${version:-default}', using base"
        export BRIK_RUNNER_IMAGE="${BRIK_RUNNER_REGISTRY:-ghcr.io/getbrik}/brik-runner-base:latest"
    fi

    return 0
}
