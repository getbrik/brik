#!/usr/bin/env bash
# @module docker-runner
# @description Containerized local execution: runs each pipeline stage in
#   its own runner-class container, mirroring what the GitLab and Jenkins
#   adapters do with CI jobs.
#
# Execution model (one run = one workspace volume):
#   1. seed_workspace      copy .git into a named volume, align ownership on
#                          the host uid:gid, materialize tracked files
#   2. run_plan_container  `brik plan` writes plan.json onto the volume
#   3. run_stage_container one container per registry stage; the plan gate
#                          and the stage itself execute INSIDE the container
#                          (container-stage.sh), exactly like a CI job
#   4. extract_logs        copy .brik-logs/ + brik-artifacts/ back to host
#   5. volume destroyed on success, kept for inspection on failure
#
# The stage containers run under the host uid:gid with HOME redirected to a
# writable directory on the volume; a fresh named volume belongs to root, so
# the seed step chowns it before anything else touches it. pipeline.env and
# report fragments propagate between stages through the volume itself -- the
# next container reads the same files, no extra channel.
#
# docker is the supported engine; BRIK_CONTAINER_ENGINE overrides the binary
# (podman compatibility is parameterized, not verified). DOCKER_HOST is
# honored end to end because every call goes through the engine CLI.
#
# Preconditions: the local wrapper bootstrap has run (log.*, registry.*,
# BRIK_EXIT_* loaded) and BRIK_HOME / BRIK_PROJECT_DIR / BRIK_CONFIG_FILE
# are exported, as cli.integrate does.

# Guard against double-sourcing
[[ -n "${_BRIK_LOCAL_DOCKER_RUNNER_LOADED:-}" ]] && return 0
_BRIK_LOCAL_DOCKER_RUNNER_LOADED=1

# Container-side filesystem contract, shared with container-stage.sh.
_BRIK_LOCAL_DOCKER_WORK="/work"
_BRIK_LOCAL_DOCKER_BRIK_HOME="/opt/brik"
_BRIK_LOCAL_DOCKER_INFRA="/etc/brik/infra"
_BRIK_LOCAL_DOCKER_HOME="/work/.brik-home"

# ---------------------------------------------------------------------------
# Engine and identity helpers
# ---------------------------------------------------------------------------

_brik.local.docker.engine() {
    printf '%s' "${BRIK_CONTAINER_ENGINE:-docker}"
}

_brik.local.docker.uid_gid() {
    printf '%s:%s' "$(id -u)" "$(id -g)"
}

_brik.local.docker.base_image() {
    registry.runner_class.image base
}

# Verify the engine binary exists and the daemon answers. The daemon probe
# goes through the CLI so a remote DOCKER_HOST is exercised, not just the
# local binary.
brik.local.docker.check_engine() {
    local engine
    engine="$(_brik.local.docker.engine)"

    if ! command -v "$engine" >/dev/null 2>&1; then
        log.error "container engine '${engine}' not found -- docker is a prerequisite of brik local execution"
        return "$BRIK_EXIT_MISSING_DEP"
    fi
    if ! "$engine" version >/dev/null 2>&1; then
        log.error "container engine daemon unreachable (checked via '${engine} version'; DOCKER_HOST is honored)"
        return "$BRIK_EXIT_INVALID_ENV"
    fi
    log.debug "container engine ready: ${engine}"
    return "$BRIK_EXIT_OK"
}

# ---------------------------------------------------------------------------
# Run volume lifecycle
# ---------------------------------------------------------------------------

brik.local.docker.run_id() {
    printf '%s-%s' "$(date +%s)" "$$"
}

brik.local.docker.volume_name() {
    printf 'brik-run-%s' "$1"
}

brik.local.docker.create_volume() {
    local volume
    volume="$(brik.local.docker.volume_name "$1")"
    "$(_brik.local.docker.engine)" volume create "$volume" >/dev/null || {
        log.error "cannot create run volume: ${volume}"
        return "$BRIK_EXIT_IO_FAILURE"
    }
    log.debug "run volume created: ${volume}"
}

brik.local.docker.destroy_volume() {
    local volume
    volume="$(brik.local.docker.volume_name "$1")"
    "$(_brik.local.docker.engine)" volume rm -f "$volume" >/dev/null || {
        log.warn "cannot remove run volume: ${volume}"
        return "$BRIK_EXIT_IO_FAILURE"
    }
    log.debug "run volume removed: ${volume}"
}

# Seed the run volume from the project repository: copy .git, align the
# whole volume on the host uid:gid (a fresh named volume belongs to root),
# then materialize the tracked files as the run user. Checkout semantics:
# committed state only -- untracked files and uncommitted edits never leak
# into the run.
# Usage: brik.local.docker.seed_workspace <run_id> <project_dir>
brik.local.docker.seed_workspace() {
    local run_id="$1"
    local project_dir="$2"

    if ! git -C "$project_dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        log.error "seed_workspace: not a git work tree: ${project_dir}"
        return "$BRIK_EXIT_INVALID_INPUT"
    fi

    local engine volume base_image uid_gid
    engine="$(_brik.local.docker.engine)"
    volume="$(brik.local.docker.volume_name "$run_id")"
    base_image="$(_brik.local.docker.base_image)" || return "$?"
    uid_gid="$(_brik.local.docker.uid_gid)"

    # Plain pipe semantics: the engine's exit code decides; a broken tar
    # stream surfaces as a tar -x failure inside the container.
    if ! tar -C "$project_dir" -cf - .git \
        | "$engine" run --rm -i -v "${volume}:${_BRIK_LOCAL_DOCKER_WORK}" "$base_image" \
            sh -c "tar -xf - -C ${_BRIK_LOCAL_DOCKER_WORK} && chown -R ${uid_gid} ${_BRIK_LOCAL_DOCKER_WORK}"; then
        log.error "seed_workspace: failed to copy .git into ${volume}"
        return "$BRIK_EXIT_IO_FAILURE"
    fi

    if ! "$engine" run --rm --user "$uid_gid" -e "HOME=${_BRIK_LOCAL_DOCKER_HOME}" \
        -v "${volume}:${_BRIK_LOCAL_DOCKER_WORK}" "$base_image" \
        sh -c "git -C ${_BRIK_LOCAL_DOCKER_WORK} checkout -f HEAD && mkdir -p ${_BRIK_LOCAL_DOCKER_HOME} ${_BRIK_LOCAL_DOCKER_WORK}/.brik-logs"; then
        log.error "seed_workspace: failed to materialize the work tree in ${volume}"
        return "$BRIK_EXIT_IO_FAILURE"
    fi

    log.info "workspace seeded into ${volume} (committed state of ${project_dir})"
    return "$BRIK_EXIT_OK"
}

# ---------------------------------------------------------------------------
# Image resolution
# ---------------------------------------------------------------------------

# Read one variable from the pipeline.env living on the run volume. The file
# is %q-quoted, so it is sourced the same way pipeline.env.load does inside
# the containers; raw parsing would corrupt escaped values.
# Usage: _brik.local.docker.read_volume_env <run_id> <key>
_brik.local.docker.read_volume_env() {
    local run_id="$1"
    local key="$2"
    local engine volume base_image content tmp value
    engine="$(_brik.local.docker.engine)"
    volume="$(brik.local.docker.volume_name "$run_id")"
    base_image="$(_brik.local.docker.base_image)" || return "$?"

    content="$("$engine" run --rm -v "${volume}:${_BRIK_LOCAL_DOCKER_WORK}" "$base_image" \
        sh -c "cat ${_BRIK_LOCAL_DOCKER_WORK}/.brik-logs/pipeline.env 2>/dev/null" 2>/dev/null)" || content=""
    [[ -z "$content" ]] && return 1

    tmp="$(mktemp)"
    printf '%s\n' "$content" > "$tmp"
    # shellcheck disable=SC1090
    value="$(set -a; . "$tmp" 2>/dev/null; printf '%s' "${!key:-}")"
    rm -f "$tmp"

    [[ -z "$value" ]] && return 1
    printf '%s\n' "$value"
}

# Resolve the OCI image for a stage: static classes come straight from the
# registry; the dynamic stack class needs BRIK_CI_IMAGE, posted by init into
# the volume's pipeline.env (the local counterpart of the CI dotenv channel).
# Usage: brik.local.docker.stage_image <run_id> <stage>
brik.local.docker.stage_image() {
    local run_id="$1"
    local stage="$2"
    local class image
    class="$(registry.stage.runner_class "$stage")" || return "$?"

    if image="$(registry.runner_class.image "$class" 2>/dev/null)"; then
        printf '%s\n' "$image"
        return "$BRIK_EXIT_OK"
    fi

    # Dynamic class: retry with the image variable read from the volume. The
    # registry emits the authoritative error when the variable is missing.
    local ci_image
    ci_image="$(_brik.local.docker.read_volume_env "$run_id" BRIK_CI_IMAGE)" || ci_image=""
    BRIK_CI_IMAGE="$ci_image" registry.runner_class.image "$class"
}

# ---------------------------------------------------------------------------
# Governed container arguments
# ---------------------------------------------------------------------------

# Print the env var names referenced as env:// by the referential's
# credentials and set (non-empty) in the host environment. These are
# forwarded by NAME ONLY (-e VAR) so secret values never appear in the
# engine argv.
_brik.local.docker.env_ref_vars() {
    local infra_dir="${BRIK_INFRA_DIR:-}"
    [[ -d "${infra_dir}/credentials" ]] || return 0

    local var
    while IFS= read -r var; do
        [[ -n "${!var:-}" ]] && printf '%s\n' "$var"
    done < <(grep -rhoE 'env://[A-Za-z_][A-Za-z0-9_]*' "${infra_dir}/credentials" 2>/dev/null \
                | sed 's|env://||' | sort -u)
    return 0
}

# Map the host config path to its in-container location. The config must
# live inside the project so the seeded volume carries it.
_brik.local.docker.container_config_path() {
    local project_dir="${BRIK_PROJECT_DIR:-$(pwd)}"
    local config="${BRIK_CONFIG_FILE:-${project_dir}/${BRIK_DEFAULT_CONFIG:-brik.yml}}"

    case "$config" in
        "${project_dir}"/*)
            printf '%s/%s\n' "$_BRIK_LOCAL_DOCKER_WORK" "${config#"${project_dir}"/}"
            ;;
        *)
            log.error "config file is outside the project directory (not on the run volume): ${config}"
            return "$BRIK_EXIT_INVALID_INPUT"
            ;;
    esac
}

# Print the engine arguments shared by every container of a run, one per
# line: mitigated uid profile, workspace volume, read-only brik runtime,
# container-side BRIK contract, governed referential mount and env-ref
# forwarding.
# Usage: _brik.local.docker.common_run_args <run_id>
_brik.local.docker.common_run_args() {
    local run_id="$1"
    local volume config_path
    volume="$(brik.local.docker.volume_name "$run_id")"
    config_path="$(_brik.local.docker.container_config_path)" || return "$?"

    printf '%s\n' \
        "--rm" \
        "--user" "$(_brik.local.docker.uid_gid)" \
        "-e" "HOME=${_BRIK_LOCAL_DOCKER_HOME}" \
        "-e" "BRIK_HOME=${_BRIK_LOCAL_DOCKER_BRIK_HOME}" \
        "-e" "BRIK_PLATFORM=local" \
        "-e" "BRIK_WORKSPACE=${_BRIK_LOCAL_DOCKER_WORK}" \
        "-e" "BRIK_PROJECT_DIR=${_BRIK_LOCAL_DOCKER_WORK}" \
        "-e" "BRIK_CONFIG_FILE=${config_path}" \
        "-e" "BRIK_LOG_DIR=${_BRIK_LOCAL_DOCKER_WORK}/.brik-logs" \
        "-e" "BRIK_PLAN_FILE=${_BRIK_LOCAL_DOCKER_WORK}/.brik-logs/plan.json" \
        "-v" "${volume}:${_BRIK_LOCAL_DOCKER_WORK}" \
        "-v" "${BRIK_HOME}:${_BRIK_LOCAL_DOCKER_BRIK_HOME}:ro" \
        "-w" "$_BRIK_LOCAL_DOCKER_WORK"

    [[ -n "${BRIK_LOG_LEVEL:-}" ]] && printf '%s\n' "-e" "BRIK_LOG_LEVEL"
    [[ -n "${BRIK_DRY_RUN:-}" ]]   && printf '%s\n' "-e" "BRIK_DRY_RUN"

    if [[ -n "${BRIK_INFRA_DIR:-}" ]]; then
        printf '%s\n' \
            "-v" "${BRIK_INFRA_DIR}:${_BRIK_LOCAL_DOCKER_INFRA}:ro" \
            "-e" "BRIK_INFRA_DIR=${_BRIK_LOCAL_DOCKER_INFRA}"
        local var
        while IFS= read -r var; do
            printf '%s\n' "-e" "$var"
        done < <(_brik.local.docker.env_ref_vars)
    fi
    return 0
}

# ---------------------------------------------------------------------------
# Container execution
# ---------------------------------------------------------------------------

# Run the planner in a base-class container; plan.json lands on the volume
# where every stage gate reads it. Extra arguments are forwarded to
# `brik plan` (the opt-in flags).
# Usage: brik.local.docker.run_plan_container <run_id> [plan flags...]
brik.local.docker.run_plan_container() {
    local run_id="$1"
    shift

    local image
    image="$(_brik.local.docker.base_image)" || return "$?"

    local -a args=()
    mapfile -t args < <(_brik.local.docker.common_run_args "$run_id") || return "$?"
    [[ ${#args[@]} -eq 0 ]] && return "$BRIK_EXIT_INVALID_INPUT"
    # Runner provenance: stamp the actual image, the way the Jenkins
    # adapter passes -e BRIK_RUNNER_IMAGE (otherwise the in-container
    # fallback reports the stack image for every stage).
    args+=("-e" "BRIK_RUNNER_IMAGE=${image}")

    "$(_brik.local.docker.engine)" run "${args[@]}" "$image" \
        "${_BRIK_LOCAL_DOCKER_BRIK_HOME}/bin/brik" plan \
        --workspace "$_BRIK_LOCAL_DOCKER_WORK" \
        --out "${_BRIK_LOCAL_DOCKER_WORK}/.brik-logs/plan.json" "$@"
}

# Run one stage in its runner-class container. The container entry replays
# the CI job contract: plan gate first, then bootstrap + stage execution
# with report fragments on.
# Usage: brik.local.docker.run_stage_container <run_id> <stage>
brik.local.docker.run_stage_container() {
    local run_id="$1"
    local stage="$2"

    local image
    image="$(brik.local.docker.stage_image "$run_id" "$stage")" || return "$?"

    local -a args=()
    mapfile -t args < <(_brik.local.docker.common_run_args "$run_id") || return "$?"
    [[ ${#args[@]} -eq 0 ]] && return "$BRIK_EXIT_INVALID_INPUT"
    # Runner provenance: stamp the actual image, the way the Jenkins
    # adapter passes -e BRIK_RUNNER_IMAGE (otherwise the in-container
    # fallback reports the stack image for every stage).
    args+=("-e" "BRIK_RUNNER_IMAGE=${image}")

    "$(_brik.local.docker.engine)" run "${args[@]}" "$image" \
        bash "${_BRIK_LOCAL_DOCKER_BRIK_HOME}/shared-libs/local/scripts/container-stage.sh" "$stage"
}

# Copy the run outputs (.brik-logs/, brik-artifacts/) from the volume back
# to the host so the report and the artifacts survive volume destruction.
# Usage: brik.local.docker.extract_logs <run_id> <dest_dir>
brik.local.docker.extract_logs() {
    local run_id="$1"
    local dest="$2"

    local engine volume base_image tmp
    engine="$(_brik.local.docker.engine)"
    volume="$(brik.local.docker.volume_name "$run_id")"
    base_image="$(_brik.local.docker.base_image)" || return "$?"
    tmp="$(mktemp)"

    "$engine" run --rm -v "${volume}:${_BRIK_LOCAL_DOCKER_WORK}" "$base_image" \
        sh -c "cd ${_BRIK_LOCAL_DOCKER_WORK} && tar -cf - \$(ls -d .brik-logs brik-artifacts 2>/dev/null) 2>/dev/null || true" \
        > "$tmp" 2>/dev/null || true

    if [[ -s "$tmp" ]]; then
        tar -xf "$tmp" -C "$dest" 2>/dev/null \
            || log.warn "extract_logs: could not unpack run outputs into ${dest}"
    fi
    rm -f "$tmp"
    return "$BRIK_EXIT_OK"
}

# ---------------------------------------------------------------------------
# Pipeline orchestration
# ---------------------------------------------------------------------------

# Run the full fixed flow, one container per stage, mirroring the CI
# adapters: the plan decides every run/skip (the opt-in flags feed the
# planner, not the loop), a failed stage stops the sequence unless
# --continue-on-error, and notify always runs (the CI when:always rule).
# On failure the volume is kept for inspection; logs are extracted to the
# project directory in every outcome.
# Usage: brik.local.docker.run_pipeline [--continue-on-error]
#        [--with-release] [--with-package] [--with-deploy]
brik.local.docker.run_pipeline() {
    local continue_on_error=false
    local -a plan_flags=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --continue-on-error) continue_on_error=true; shift ;;
            --with-release|--with-package|--with-deploy) plan_flags+=("$1"); shift ;;
            *)
                log.error "run_pipeline: unknown flag '$1'"
                return "$BRIK_EXIT_INVALID_INPUT"
                ;;
        esac
    done

    brik.local.docker.check_engine || return "$?"

    if ! declare -f registry.stage.list >/dev/null 2>&1; then
        log.error "run_pipeline: registry.stage.list is not loaded"
        return "$BRIK_EXIT_CONFIG_ERROR"
    fi
    local -a stages=()
    mapfile -t stages < <(registry.stage.list 2>/dev/null || true)
    if [[ ${#stages[@]} -eq 0 ]]; then
        log.error "run_pipeline: registry.stage.list returned no stages"
        return "$BRIK_EXIT_CONFIG_ERROR"
    fi

    local project_dir="${BRIK_PROJECT_DIR:-$(pwd)}"
    local run_id
    run_id="$(brik.local.docker.run_id)"

    brik.local.docker.create_volume "$run_id" || return "$?"

    local had_failure=false
    if brik.local.docker.seed_workspace "$run_id" "$project_dir" \
        && brik.local.docker.run_plan_container "$run_id" "${plan_flags[@]}"; then
        local stage rc
        for stage in "${stages[@]}"; do
            # Mirror the CI behavior after a failure: downstream jobs do not
            # run (no fragment), except notify which is always-on.
            if $had_failure && ! $continue_on_error && [[ "$stage" != "notify" ]]; then
                continue
            fi
            if ! brik.local.docker.run_stage_container "$run_id" "$stage"; then
                rc=$?
                had_failure=true
                log.error "stage ${stage} failed (rc=${rc})"
            fi
        done
    else
        had_failure=true
        log.error "run aborted before the stage sequence (seed or plan failed)"
    fi

    brik.local.docker.extract_logs "$run_id" "$project_dir" || true

    if $had_failure; then
        log.warn "run volume kept for inspection: $(brik.local.docker.volume_name "$run_id")"
        return "$BRIK_EXIT_FAILURE"
    fi
    brik.local.docker.destroy_volume "$run_id" || true
    return "$BRIK_EXIT_OK"
}
