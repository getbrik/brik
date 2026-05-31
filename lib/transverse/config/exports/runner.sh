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

    # GitLab exposes the resolved job image as CI_JOB_IMAGE. Prefer it so the
    # banner and report record the image the stage ACTUALLY runs in (e.g. the
    # stub image under a BRIK_RUNNER_CLASSES_FILE override), not the project's
    # stack default. Jenkins gets the same parity by injecting BRIK_RUNNER_IMAGE
    # explicitly via brikRunStage. Empty on platforms that do not set it.
    if [[ -n "${CI_JOB_IMAGE:-}" ]]; then
        export BRIK_RUNNER_IMAGE="$CI_JOB_IMAGE"
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

    local stack="${BRIK_BUILD_STACK:-auto}"
    local version="${BRIK_BUILD_STACK_VERSION:-}"

    # Delegate to the single shared stack-or-base resolver: stack image when
    # known, base image (with the warning) otherwise. The base fallback literal
    # lives only in runner.base_image.
    if declare -f runner.resolve_stack_or_base >/dev/null 2>&1; then
        local image
        image="$(runner.resolve_stack_or_base "$stack" "$version")"
        export BRIK_RUNNER_IMAGE="$image"
        return 0
    fi

    # runner-images.sh unavailable (degraded environment): emit the base ref.
    export BRIK_RUNNER_IMAGE="${BRIK_RUNNER_REGISTRY:-ghcr.io/getbrik}/brik-runner-base:latest"
    return 0
}
