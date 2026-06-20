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
_BRIK_LOCAL_DOCKER_POLICY="/etc/brik/policy"
_BRIK_LOCAL_DOCKER_HOME="/work/.brik-home"
_BRIK_LOCAL_DOCKER_SOCKET="/var/run/docker.sock"

# ---------------------------------------------------------------------------
# Engine and identity helpers
# ---------------------------------------------------------------------------

_brik.local.docker.engine() {
    printf '%s' "${BRIK_CONTAINER_ENGINE:-docker}"
}

# --platform tokens when BRIK_LOCAL_PLATFORM is set (exact arch parity, e.g.
# linux/amd64 on an arm64 host). Empty by default = host architecture.
_brik.local.docker.platform_args() {
    [[ -n "${BRIK_LOCAL_PLATFORM:-}" ]] && printf '%s\n' "--platform" "${BRIK_LOCAL_PLATFORM}"
    return 0
}

# engine_run - the single chokepoint for `<engine> run`. Injects --platform so
# every container of a run (seed, plan, stage, extract) executes on the same
# architecture. All run sites go through here.
_brik.local.docker.engine_run() {
    local engine
    engine="$(_brik.local.docker.engine)"
    local -a plat=()
    mapfile -t plat < <(_brik.local.docker.platform_args)
    "${engine}" run "${plat[@]}" "$@"
}

# work_mount - the `-v <src>:/work` spec for a run. Bind-mounts the project dir
# live when BRIK_LOCAL_BIND_MOUNT=1 (fast edit/inspect loop, waives the
# committed-state guarantee), otherwise the per-run named volume.
_brik.local.docker.work_mount() {
    local run_id="$1"
    if [[ "${BRIK_LOCAL_BIND_MOUNT:-}" == "1" ]]; then
        printf '%s' "${BRIK_PROJECT_DIR}:${_BRIK_LOCAL_DOCKER_WORK}"
    else
        printf '%s' "$(brik.local.docker.volume_name "$run_id"):${_BRIK_LOCAL_DOCKER_WORK}"
    fi
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
        | _brik.local.docker.engine_run --rm -i -v "$(_brik.local.docker.work_mount "$run_id")" "$base_image" \
            sh -c "tar -xf - -C ${_BRIK_LOCAL_DOCKER_WORK} && chown -R ${uid_gid} ${_BRIK_LOCAL_DOCKER_WORK}"; then
        log.error "seed_workspace: failed to copy .git into ${volume}"
        return "$BRIK_EXIT_IO_FAILURE"
    fi

    if ! _brik.local.docker.engine_run --rm --user "$uid_gid" -e "HOME=${_BRIK_LOCAL_DOCKER_HOME}" \
        -v "$(_brik.local.docker.work_mount "$run_id")" "$base_image" \
        sh -c "git -C ${_BRIK_LOCAL_DOCKER_WORK} checkout -f HEAD && mkdir -p ${_BRIK_LOCAL_DOCKER_HOME} ${_BRIK_LOCAL_DOCKER_WORK}/.brik-logs"; then
        log.error "seed_workspace: failed to materialize the work tree in ${volume}"
        return "$BRIK_EXIT_IO_FAILURE"
    fi

    log.info "workspace seeded into ${volume} (committed state of ${project_dir})"
    return "$BRIK_EXIT_OK"
}

# Seed a caller-provided plan.json onto the run volume in place of running
# the planner (the `brik integrate --plan` contract): the gates then execute
# against exactly the file the caller audited. The log dir already exists
# (created by seed_workspace).
# Usage: brik.local.docker.seed_plan <run_id> <plan_file>
brik.local.docker.seed_plan() {
    local run_id="$1"
    local plan_file="$2"

    if [[ ! -f "$plan_file" ]]; then
        log.error "seed_plan: plan file not found: ${plan_file}"
        return "$BRIK_EXIT_INVALID_INPUT"
    fi

    local engine volume base_image
    engine="$(_brik.local.docker.engine)"
    volume="$(brik.local.docker.volume_name "$run_id")"
    base_image="$(_brik.local.docker.base_image)" || return "$?"

    if ! _brik.local.docker.engine_run --rm -i --user "$(_brik.local.docker.uid_gid)" \
        -v "$(_brik.local.docker.work_mount "$run_id")" "$base_image" \
        sh -c "cat > ${_BRIK_LOCAL_DOCKER_WORK}/.brik-logs/plan.json" < "$plan_file"; then
        log.error "seed_plan: failed to copy ${plan_file} into ${volume}"
        return "$BRIK_EXIT_IO_FAILURE"
    fi
    log.info "plan seeded into ${volume} from ${plan_file}"
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

    content="$(_brik.local.docker.engine_run --rm -v "$(_brik.local.docker.work_mount "$run_id")" "$base_image" \
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

# Print --add-host aliases for the referential's endpoint hosts that the
# HOST resolves through a loopback /etc/hosts entry (the host-published
# service pattern, e.g. a lab registry behind 127.0.0.1). Inside a
# container, loopback points at the container itself, so those names are
# remapped to the host gateway. Hosts with real DNS are left alone, and
# localhost itself is never aliased (it must keep meaning the container).
# BRIK_LOCAL_HOSTS_FILE overrides the hosts file (tests, chroots).
_brik.local.docker.add_host_args() {
    local infra_dir="${BRIK_INFRA_DIR:-}"
    local hosts_file="${BRIK_LOCAL_HOSTS_FILE:-/etc/hosts}"
    [[ -d "${infra_dir}/endpoints" && -r "$hosts_file" ]] || return 0

    local host
    while IFS= read -r host; do
        [[ -z "$host" || "$host" == "localhost" ]] && continue
        if grep -qE "^[[:space:]]*(127\.[0-9.]+|::1)([[:space:]][^#]*)?[[:space:]]${host}([[:space:]]|\$)" \
            "$hosts_file" 2>/dev/null; then
            printf '%s\n' "--add-host" "${host}:host-gateway"
        fi
    done < <(grep -rhoE '^[a-z_]*url: *[a-z+]+://[^/ ]+' "${infra_dir}/endpoints" 2>/dev/null \
                | sed -E 's|^[a-z_]*url: *[a-z+]+://||; s|^[^@/ ]*@||; s|:[0-9]+$||' | sort -u)
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
        "-e" "BRIK_LOCAL_CONTAINER=1" \
        "-e" "BRIK_WORKSPACE=${_BRIK_LOCAL_DOCKER_WORK}" \
        "-e" "BRIK_PROJECT_DIR=${_BRIK_LOCAL_DOCKER_WORK}" \
        "-e" "BRIK_CONFIG_FILE=${config_path}" \
        "-e" "BRIK_LOG_DIR=${_BRIK_LOCAL_DOCKER_WORK}/.brik-logs" \
        "-e" "BRIK_PLAN_FILE=${_BRIK_LOCAL_DOCKER_WORK}/.brik-logs/plan.json" \
        "-v" "$(_brik.local.docker.work_mount "$run_id")" \
        "-v" "${BRIK_HOME}:${_BRIK_LOCAL_DOCKER_BRIK_HOME}:ro" \
        "-w" "$_BRIK_LOCAL_DOCKER_WORK"

    [[ -n "${BRIK_LOG_LEVEL:-}" ]] && printf '%s\n' "-e" "BRIK_LOG_LEVEL"
    [[ -n "${BRIK_DRY_RUN:-}" ]]   && printf '%s\n' "-e" "BRIK_DRY_RUN"

    # Ambient pipeline variables that the CI adapters inject as job variables
    # and brik reads inside the stage. They are NOT referential credentials, so
    # the local engine forwards them by name to mirror the orchestrators:
    #   BRIK_COMMIT_TAG  the release-context signal (set from a tag-push event,
    #                    or locally by `brik integrate --release`); without it a
    #                    local run is always snapshot and never cuts a release.
    #   COSIGN_PASSWORD  the signing-key passphrase (a key backend names the key
    #                    file; the passphrase travels as a variable). Forwarded
    #                    even when empty (the common lab passphrase) so signing
    #                    does not block on a non-interactive password prompt.
    [[ -n "${BRIK_COMMIT_TAG:-}" ]] && printf '%s\n' "-e" "BRIK_COMMIT_TAG"
    [[ -n "${COSIGN_PASSWORD+x}" ]] && printf '%s\n' "-e" "COSIGN_PASSWORD"

    if [[ -n "${BRIK_INFRA_DIR:-}" ]]; then
        printf '%s\n' \
            "-v" "${BRIK_INFRA_DIR}:${_BRIK_LOCAL_DOCKER_INFRA}:ro" \
            "-e" "BRIK_INFRA_DIR=${_BRIK_LOCAL_DOCKER_INFRA}"
        local var
        while IFS= read -r var; do
            printf '%s\n' "-e" "$var"
        done < <(_brik.local.docker.env_ref_vars)
        _brik.local.docker.add_host_args
    fi

    # The org policy is owned by the organization (the DSI), not the infra
    # referential: the referential only names it (a Policy document whose url
    # points at /etc/brik/policy/...). The CI runners mount the policy there;
    # the local engine mirrors that mount from BRIK_POLICY_DIR so a referential
    # Policy resolves identically on a bare host.
    if [[ -n "${BRIK_POLICY_DIR:-}" ]]; then
        printf '%s\n' "-v" "${BRIK_POLICY_DIR}:${_BRIK_LOCAL_DOCKER_POLICY}:ro"
    fi
    return 0
}

# Keyless signing needs a platform OIDC token, and a bare local host has
# none (declared divergence of the local mode). When the wired referential
# declares a keyless Signing endpoint, refuse the CI flow up front with a
# cross-validation error: the binding must point at a key or kms backend
# (or declare no Signing endpoint at all) for local execution. The CD verb
# is NOT gated: verification is OIDC-free.
_brik.local.docker.check_signing_backend() {
    [[ -z "${BRIK_INFRA_DIR:-}" ]] && return 0

    brik.use transverse.infra
    local sig backend
    # No (or ambiguous) Signing endpoint: nothing to cross-validate here,
    # the referential validation owns those errors.
    sig="$(infra.endpoint_of_kind Signing 2>/dev/null)" || return 0
    backend="$(printf '%s' "$sig" | jq -r '.backend // empty' 2>/dev/null)" || backend=""

    if [[ "$backend" == "keyless" ]]; then
        log.error "the referential declares keyless signing, which is unavailable in local execution (no platform OIDC issuer): bind a key or kms backend, or remove the Signing endpoint"
        return "$BRIK_EXIT_CONFIG_ERROR"
    fi
    return 0
}

# Print the engine arguments granting a container access to the host docker
# daemon, one per line. Mounted ONLY into stages whose manifest declares
# runner.docker (the caller gates on registry.stage.needs_docker). A unix://
# DOCKER_HOST overrides the default socket path; a remote DOCKER_HOST is
# forwarded as-is instead of mounting (the in-container CLI then talks to
# the same endpoint the host uses).
_brik.local.docker.socket_args() {
    local docker_host="${DOCKER_HOST:-}"
    case "$docker_host" in
        unix://*) _brik.local.docker._socket_mount_args "${docker_host#unix://}" ;;
        ?*)       printf '%s\n' "-e" "DOCKER_HOST" ;;
        *)        _brik.local.docker._socket_mount_args "$_BRIK_LOCAL_DOCKER_SOCKET" ;;
    esac
}

_brik.local.docker._socket_mount_args() {
    local socket="$1"
    printf '%s\n' "-v" "${socket}:${_BRIK_LOCAL_DOCKER_SOCKET}"
    # H8: on Linux the socket is root:docker 0660, so the arbitrary-uid run
    # user needs the socket's gid as a supplementary group. Docker Desktop
    # (macOS/Windows) exposes a 0666 socket -- nothing to add.
    if [[ "$(uname -s)" == "Linux" ]]; then
        local gid
        gid="$(stat -c %g "$socket" 2>/dev/null)" || gid=""
        [[ -n "$gid" ]] && printf '%s\n' "--group-add" "$gid"
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

    _brik.local.docker.engine_run "${args[@]}" "$image" \
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

    # Governed socket: only the stages whose manifest declares runner.docker
    # get access to the host engine (least privilege, H8).
    if registry.stage.needs_docker "$stage"; then
        local -a socket_args=()
        mapfile -t socket_args < <(_brik.local.docker.socket_args)
        args+=("${socket_args[@]}")
    fi

    _brik.local.docker.engine_run "${args[@]}" "$image" \
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

    _brik.local.docker.engine_run --rm -v "$(_brik.local.docker.work_mount "$run_id")" "$base_image" \
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
#        [--with-release] [--with-package] [--with-deploy] [--plan <file>]
brik.local.docker.run_pipeline() {
    local continue_on_error=false
    local plan_file=""
    local -a plan_flags=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --continue-on-error) continue_on_error=true; shift ;;
            --with-release|--with-package|--with-deploy) plan_flags+=("$1"); shift ;;
            --plan)
                if [[ -z "${2:-}" ]]; then
                    log.error "run_pipeline: --plan requires a path"
                    return "$BRIK_EXIT_INVALID_INPUT"
                fi
                plan_file="$2"; shift 2
                ;;
            *)
                log.error "run_pipeline: unknown flag '$1'"
                return "$BRIK_EXIT_INVALID_INPUT"
                ;;
        esac
    done

    if [[ -n "$plan_file" && ! -f "$plan_file" ]]; then
        log.error "run_pipeline: plan file not found: ${plan_file}"
        return "$BRIK_EXIT_INVALID_INPUT"
    fi

    brik.local.docker.check_engine || return "$?"
    _brik.local.docker.check_signing_backend || return "$?"

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

    local bind=false
    [[ "${BRIK_LOCAL_BIND_MOUNT:-}" == "1" ]] && bind=true

    if ! $bind; then
        brik.local.docker.create_volume "$run_id" || return "$?"
    fi

    local had_failure=false
    # Seed the work dir, then the plan. Non-bind copies the committed state
    # into the volume; bind uses the live project dir as /work (the
    # committed-state guarantee is waived by opt-in) and only ensures the log
    # dir exists. The plan runs the same way in both modes.
    local prepared=false
    if $bind; then
        mkdir -p "${project_dir}/.brik-logs" && prepared=true
    elif brik.local.docker.seed_workspace "$run_id" "$project_dir"; then
        prepared=true
    fi
    if $prepared; then
        if [[ -n "$plan_file" ]]; then
            brik.local.docker.seed_plan "$run_id" "$plan_file" || prepared=false
        else
            brik.local.docker.run_plan_container "$run_id" "${plan_flags[@]}" || prepared=false
        fi
    fi
    if $prepared; then
        local stage rc group prev_group="" skip_rest=false
        for stage in "${stages[@]}"; do
            # Mirror the CI dependency graph: stages sharing a placement group
            # (e.g. [lint || sast || scan || test], group=verify) run as an
            # independent wave -- a failed sibling never skips the others. A
            # failure only gates the NEXT wave (the skip decision is locked at
            # each group boundary), and notify is always-on. An empty group is
            # a singleton wave keyed by the stage id, preserving stop-on-failure
            # for the linear stages (build, package, ...).
            group="$(registry.stage.placement_group "$stage" 2>/dev/null || true)"
            [[ -z "$group" ]] && group="$stage"
            if [[ "$group" != "$prev_group" ]]; then
                if $had_failure && ! $continue_on_error; then
                    skip_rest=true
                fi
                prev_group="$group"
            fi
            if $skip_rest && [[ "$stage" != "notify" ]]; then
                continue
            fi
            rc=0
            brik.local.docker.run_stage_container "$run_id" "$stage" || rc=$?
            if (( rc != 0 )); then
                had_failure=true
                log.error "stage ${stage} failed (rc=${rc})"
            fi
        done
    else
        had_failure=true
        log.error "run aborted before the stage sequence (seed or plan failed)"
    fi

    if ! $bind; then
        brik.local.docker.extract_logs "$run_id" "$project_dir" || true
    fi

    if $had_failure; then
        if $bind; then
            log.warn "run failed; outputs are in ${project_dir}/.brik-logs"
        else
            log.warn "run volume kept for inspection: $(brik.local.docker.volume_name "$run_id")"
        fi
        return "$BRIK_EXIT_FAILURE"
    fi
    if ! $bind; then
        brik.local.docker.destroy_volume "$run_id" || true
    fi
    return "$BRIK_EXIT_OK"
}

# Run ONE stage in its runner-class container (the `brik stage` dev verb).
# Same lifecycle as run_pipeline: fresh volume, seed, plan, the stage's
# container, logs extracted, volume destroyed on success / kept on failure.
# The plan gate applies in-container exactly as in the full flow (no
# bypass); the stage's own opt-in flag is fed to the planner so explicitly
# asking for an opt-in stage (package, deploy, ...) does not plan it away.
# Usage: brik.local.docker.run_single_stage <stage>
brik.local.docker.run_single_stage() {
    local stage="$1"

    brik.local.docker.check_engine || return "$?"
    _brik.local.docker.check_signing_backend || return "$?"

    # Validate the stage id against the registry before paying any container.
    registry.stage.runner_class "$stage" >/dev/null || return "$?"

    local -a plan_flags=()
    local opt_flag
    opt_flag="$(registry.stage.gate_opt_in_flag "$stage" 2>/dev/null)" || opt_flag=""
    [[ -n "$opt_flag" ]] && plan_flags+=("$opt_flag")

    local project_dir="${BRIK_PROJECT_DIR:-$(pwd)}"
    local run_id
    run_id="$(brik.local.docker.run_id)"

    brik.local.docker.create_volume "$run_id" || return "$?"

    local rc=0
    if brik.local.docker.seed_workspace "$run_id" "$project_dir" \
        && brik.local.docker.run_plan_container "$run_id" "${plan_flags[@]}"; then
        # Replay the CI job contract: every stage consumes init's dotenv
        # (BRIK_CI_IMAGE for the stack class, release metadata), so init
        # bootstraps the run before the requested stage -- the same
        # ordering the CI adapters enforce with the init job.
        if [[ "$stage" != "init" ]]; then
            brik.local.docker.run_stage_container "$run_id" init || rc=$?
        fi
        if [[ "$rc" -eq 0 ]]; then
            brik.local.docker.run_stage_container "$run_id" "$stage" || rc=$?
        fi
    else
        rc="$BRIK_EXIT_FAILURE"
        log.error "run aborted before the stage container (seed or plan failed)"
    fi

    brik.local.docker.extract_logs "$run_id" "$project_dir" || true

    if [[ "$rc" -ne 0 ]]; then
        log.warn "run volume kept for inspection: $(brik.local.docker.volume_name "$run_id")"
        return "$rc"
    fi
    brik.local.docker.destroy_volume "$run_id" || true
    return "$BRIK_EXIT_OK"
}

# Run a CD-side CLI verb in the deploy-class container -- the local
# counterpart of the GitLab/Jenkins CD jobs, which also execute these verbs
# inside a deploy-class image. The seeded volume carries the full git
# history, so the in-container verb resolves definition refs exactly as in
# CI, and every gate executes in-container, unchanged (no bypass). An
# explicit --config is remapped to its in-volume path; the other arguments
# pass through verbatim.
# Usage: _brik.local.docker._run_cli_verb_container <verb> [args...]
_brik.local.docker._run_cli_verb_container() {
    local verb="$1"
    shift
    local -a verb_args=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --config)
                if [[ -z "${2:-}" ]]; then
                    log.error "run_deploy_container: --config requires a path"
                    return "$BRIK_EXIT_INVALID_INPUT"
                fi
                local mapped
                mapped="$(BRIK_CONFIG_FILE="$2" _brik.local.docker.container_config_path)" \
                    || return "$?"
                verb_args+=(--config "$mapped")
                shift 2
                ;;
            *) verb_args+=("$1"); shift ;;
        esac
    done

    brik.local.docker.check_engine || return "$?"

    local image
    image="$(registry.runner_class.image deploy)" || return "$?"

    local project_dir="${BRIK_PROJECT_DIR:-$(pwd)}"
    local run_id
    run_id="$(brik.local.docker.run_id)"

    local -a args=()
    mapfile -t args < <(_brik.local.docker.common_run_args "$run_id") || return "$?"
    [[ ${#args[@]} -eq 0 ]] && return "$BRIK_EXIT_INVALID_INPUT"
    args+=("-e" "BRIK_RUNNER_IMAGE=${image}")
    # The deploy stage's manifest governs the engine socket for the verb
    # container too (compose targets drive docker through it).
    if registry.stage.needs_docker deploy; then
        local -a socket_args=()
        mapfile -t socket_args < <(_brik.local.docker.socket_args)
        args+=("${socket_args[@]}")
    fi

    brik.local.docker.create_volume "$run_id" || return "$?"

    local rc=0
    if brik.local.docker.seed_workspace "$run_id" "$project_dir"; then
        _brik.local.docker.engine_run "${args[@]}" "$image" \
            "${_BRIK_LOCAL_DOCKER_BRIK_HOME}/bin/brik" "$verb" "${verb_args[@]}" || rc=$?
    else
        rc="$BRIK_EXIT_FAILURE"
        log.error "run aborted before the ${verb} container (seed failed)"
    fi

    brik.local.docker.extract_logs "$run_id" "$project_dir" || true

    if [[ "$rc" -ne 0 ]]; then
        log.warn "run volume kept for inspection: $(brik.local.docker.volume_name "$run_id")"
        return "$rc"
    fi
    brik.local.docker.destroy_volume "$run_id" || true
    return "$BRIK_EXIT_OK"
}

# Usage: brik.local.docker.run_deploy_container [brik deploy args...]
brik.local.docker.run_deploy_container() {
    _brik.local.docker._run_cli_verb_container deploy "$@"
}

# Usage: brik.local.docker.run_status_container [brik status args...]
brik.local.docker.run_status_container() {
    _brik.local.docker._run_cli_verb_container status "$@"
}
