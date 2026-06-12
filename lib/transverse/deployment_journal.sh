#!/usr/bin/env bash
# @module transverse.deployment_journal
# @requires jq git sha256sum
# @description DeploymentJournal: file-per-event, env-scoped deployment records.
#
# The journal lives under deployments/ in the state-repo (the same repository
# as the evidence store and the PromotionJournal) and records every observed
# deploy as an append-only, file-per-event commit: one 'deployed' event per
# digest per environment. The event binds the digest (anti-replay), the
# definition layers it was rendered from (version_ref = Layer V tag commit,
# env_config_ref = Layer E commit when the env is governed by config_ref) and
# the definition_hash of the rendered definition that was applied -- the
# anchor the status command re-derives and compares for drift detection.
# run_id/run_url/actor are orchestrator traceability, informational only.
#
# Events are validated against schemas/state/v1/deployment-event.schema.json
# fail-closed at write AND at read: a journal entry that does not validate is
# an integrity failure, never a skip. Authorship and integrity come from the
# signed git commit that appends the file, not from fields in the document.
#
# Replay semantics: the event is appended AFTER the rollout and the live
# read-back, so a deploy whose append fails has happened without its record.
# The run is failed (never silent) and the event is recovered by re-running
# the deploy: the re-entry converges on the same digest and journals it.
#
# Functions:
#   deployment_journal.relpath <timestamp> <uid>  - the day-bucketed event path
#   deployment_journal.build_event --environment ... - emit a validated event JSON
#   deployment_journal.definition_hash --workspace ... - hash the rendered definition
#   deployment_journal.publish --repo ...         - commit an event (stdin)
#   deployment_journal.record_deployment ...      - config-aware wrapper
#   deployment_journal.events_for <dir> --environment ... - read and filter events

# Guard against double-sourcing
[[ -n "${_BRIK_MODULE_TRANSVERSE_DEPLOYMENT_JOURNAL_LOADED:-}" ]] && return 0
_BRIK_MODULE_TRANSVERSE_DEPLOYMENT_JOURNAL_LOADED=1

# Validate one deployment event (stdin) against the state/v1 schema.
# Fail-closed: a missing schema file or no available validator refuses the
# event rather than letting an unvalidated document into the journal.
# Usage: <event> | _deployment_journal._validate
_deployment_journal._validate() {
    local schema="${BRIK_HOME:-/opt/brik}/schemas/state/v1/deployment-event.schema.json"
    if [[ ! -f "$schema" ]]; then
        log.error "deployment-event schema not found at ${schema}"
        return "$BRIK_EXIT_MISSING_DEP"
    fi
    if command -v jv >/dev/null 2>&1; then
        jv "$schema" - >/dev/null 2>&1 && return 0
        return "$BRIK_EXIT_INVALID_INPUT"
    fi
    if command -v check-jsonschema >/dev/null 2>&1; then
        check-jsonschema --schemafile "$schema" - >/dev/null 2>&1 && return 0
        return "$BRIK_EXIT_INVALID_INPUT"
    fi
    log.error "no JSON Schema validator available (jv or check-jsonschema): refusing an unvalidated journal event"
    return "$BRIK_EXIT_MISSING_DEP"
}

# Random 16-hex event uid (no uuidgen dependency: busybox images lack it).
_deployment_journal._uid() {
    od -An -tx1 -N8 /dev/urandom | tr -d ' \n'
}

# Day-bucketed store path for an event. The ISO timestamp keeps the journal
# browsable by date; the uid makes concurrent events on the same second
# collision-free.
# Usage: deployment_journal.relpath <iso-timestamp> <uid>
deployment_journal.relpath() {
    local ts="$1" uid="$2"
    local date="${ts%%T*}"
    local compact="${ts//-/}"
    compact="${compact//:/}"
    printf 'deployments/%s/%s/%s/%s-%s.json' \
        "${date:0:4}" "${date:5:2}" "${date:8:2}" "$compact" "$uid"
}

# Build one deployed event on stdout, schema-validated fail-closed. The
# digest and the definition_hash are both mandatory: an event that cannot
# name the artifact or the definition it applied records nothing usable.
# Usage: deployment_journal.build_event --environment <e> --version <v>
#        --digest <d> --definition-hash <h> [--version-ref <sha>]
#        [--env-config-ref <sha>] [--run-id <id>] [--run-url <url>]
#        [--actor <a>] [--timestamp <iso>]
deployment_journal.build_event() {
    local environment="" version="" digest="" definition_hash=""
    local version_ref="" env_config_ref="" run_id="" run_url="" actor=""
    local timestamp=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --environment)     environment="$2";     shift 2 ;;
            --version)         version="$2";         shift 2 ;;
            --digest)          digest="$2";          shift 2 ;;
            --definition-hash) definition_hash="$2"; shift 2 ;;
            --version-ref)     version_ref="$2";     shift 2 ;;
            --env-config-ref)  env_config_ref="$2";  shift 2 ;;
            --run-id)          run_id="$2";          shift 2 ;;
            --run-url)         run_url="$2";         shift 2 ;;
            --actor)           actor="$2";           shift 2 ;;
            --timestamp)       timestamp="$2";       shift 2 ;;
            *) log.error "deployment_journal.build_event: unknown option: $1"
               return "$BRIK_EXIT_INVALID_INPUT" ;;
        esac
    done

    if [[ -z "$environment" || -z "$version" ]]; then
        log.error "deployment_journal.build_event: --environment and --version are required"
        return "$BRIK_EXIT_INVALID_INPUT"
    fi
    if [[ ! "$digest" =~ ^sha256:[0-9a-f]{64}$ ]]; then
        log.error "deployment_journal.build_event: --digest must be a sha256:HEX image digest (events bind to the artifact, not a tag)"
        return "$BRIK_EXIT_INVALID_INPUT"
    fi
    if [[ ! "$definition_hash" =~ ^sha256:[0-9a-f]{64}$ ]]; then
        log.error "deployment_journal.build_event: --definition-hash must be a sha256:HEX hash of the rendered definition (the drift anchor)"
        return "$BRIK_EXIT_INVALID_INPUT"
    fi

    [[ -z "$timestamp" ]] && timestamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

    local event
    # KCOV_EXCL_START -- inline jq document body, not bash code
    event="$(jq -n \
        --arg environment "$environment" \
        --arg version "$version" \
        --arg digest "$digest" \
        --arg definition_hash "$definition_hash" \
        --arg timestamp "$timestamp" \
        --arg version_ref "$version_ref" \
        --arg env_config_ref "$env_config_ref" \
        --arg run_id "$run_id" \
        --arg run_url "$run_url" \
        --arg actor "$actor" '
        {
          schema: "brik.deployment-event/v1",
          type: "deployed",
          environment: $environment,
          version: $version,
          digest: $digest,
          timestamp: $timestamp,
          definition_hash: $definition_hash
        }
        + (if $version_ref    != "" then {version_ref: $version_ref}       else {} end)
        + (if $env_config_ref != "" then {env_config_ref: $env_config_ref} else {} end)
        + (if $run_id         != "" then {run_id: $run_id}                 else {} end)
        + (if $run_url        != "" then {run_url: $run_url}               else {} end)
        + (if $actor          != "" then {actor: $actor}                   else {} end)')"
    # KCOV_EXCL_STOP

    local rc=0
    printf '%s\n' "$event" | _deployment_journal._validate || rc=$?
    if [[ "$rc" -ne 0 ]]; then
        [[ "$rc" -eq "$BRIK_EXIT_INVALID_INPUT" ]] \
            && log.error "deployment_journal.build_event: the event does not validate against the deployment-event schema"
        return "$rc"
    fi
    printf '%s\n' "$event"
}

# Hash the rendered definition an environment deploy applies: the canonical
# JSON of the env's config block, the content of every LOCAL definition file
# it references (manifest/values/compose_file/source/chart -- a non-local
# reference such as a remote helm chart participates through the config
# block) and the digest-pinned image ref. Deterministic and
# location-independent, so the status command can re-derive the hash from
# the recorded version_ref/env_config_ref and compare it for drift.
# Usage: deployment_journal.definition_hash --workspace <ws>
#        --environment <e> [--pinned <ref>]
deployment_journal.definition_hash() {
    local workspace="" environment="" pinned=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --workspace)   workspace="$2";   shift 2 ;;
            --environment) environment="$2"; shift 2 ;;
            --pinned)      pinned="$2";      shift 2 ;;
            *) log.error "deployment_journal.definition_hash: unknown option: $1"
               return "$BRIK_EXIT_INVALID_INPUT" ;;
        esac
    done

    if [[ -z "$workspace" || -z "$environment" ]]; then
        log.error "deployment_journal.definition_hash: --workspace and --environment are required"
        return "$BRIK_EXIT_INVALID_INPUT"
    fi

    local cfg="${workspace}/${BRIK_DEFAULT_CONFIG:-brik.yml}"
    if [[ ! -f "$cfg" ]]; then
        log.error "deployment_journal.definition_hash: no config at ${cfg}"
        return "$BRIK_EXIT_CONFIG_ERROR"
    fi

    # A test harness stubbing brik.use as a no-op supplies its own config.get.
    declare -f config.get >/dev/null 2>&1 || brik.use transverse.config

    local env_json
    if ! env_json="$(BRIK_CONFIG_FILE="$cfg" \
            config.get ".deploy.environments.${environment} | @json" 2>/dev/null)"; then
        log.error "deployment_journal.definition_hash: environment '${environment}' is not declared in ${cfg}"
        return "$BRIK_EXIT_CONFIG_ERROR"
    fi
    if ! env_json="$(printf '%s' "$env_json" | jq -Sc . 2>/dev/null)"; then
        log.error "deployment_journal.definition_hash: the '${environment}' config block is not valid JSON"
        return "$BRIK_EXIT_CONFIG_ERROR"
    fi

    local parts key path abs h
    parts="config:$(printf '%s' "$env_json" | sha256sum | cut -d' ' -f1)"
    for key in manifest values compose_file source chart; do
        path="$(printf '%s' "$env_json" | jq -r --arg k "$key" '.[$k] // empty')"
        [[ -z "$path" ]] && continue
        abs="${workspace}/${path}"
        if [[ -f "$abs" ]]; then
            h="$(sha256sum "$abs" | cut -d' ' -f1)"
        elif [[ -d "$abs" ]]; then
            h="$( (cd "$abs" && find . -type f ! -path './.git/*' -print0 \
                | LC_ALL=C sort -z \
                | xargs -0 sha256sum) \
                | sha256sum | cut -d' ' -f1)"
        else
            continue
        fi
        parts="${parts}"$'\n'"${key}:${path}:${h}"
    done
    [[ -n "$pinned" ]] && parts="${parts}"$'\n'"image:${pinned}"

    printf 'sha256:%s' "$(printf '%s\n' "$parts" | sha256sum | cut -d' ' -f1)"
}

# Commit a deployment event (read from stdin) to the state-repo at its
# day-bucketed path. The event is re-validated fail-closed before anything
# touches the store; the append is append-only and the commit optionally
# ssh-signed.
# Usage: <event> | deployment_journal.publish --repo <url>
#        [--branch <b>] [--token-var <VAR>] [--sign] [--dry-run]
deployment_journal.publish() {
    local repo="" branch="" token_var="" sign="" dry_run="${BRIK_DRY_RUN:-}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --repo)      repo="$2";      shift 2 ;;
            --branch)    branch="$2";    shift 2 ;;
            --token-var) token_var="$2"; shift 2 ;;
            --sign)      sign="true";    shift ;;
            --dry-run)   dry_run="true"; shift ;;
            *) log.error "deployment_journal.publish: unknown option: $1"
               return "$BRIK_EXIT_INVALID_INPUT" ;;
        esac
    done

    if [[ -z "$repo" ]]; then
        cat >/dev/null   # consume the event so the producer does not block
        log.error "deployment_journal.publish: --repo is required"
        return "$BRIK_EXIT_INVALID_INPUT"
    fi

    local doc
    doc="$(cat)"

    local rc=0
    printf '%s\n' "$doc" | _deployment_journal._validate || rc=$?
    if [[ "$rc" -ne 0 ]]; then
        [[ "$rc" -eq "$BRIK_EXIT_INVALID_INPUT" ]] \
            && log.error "deployment_journal.publish: the event does not validate against the deployment-event schema -- refusing to append"
        return "$rc"
    fi

    local environment version digest timestamp
    environment="$(printf '%s' "$doc" | jq -r '.environment')"
    version="$(printf '%s' "$doc" | jq -r '.version')"
    digest="$(printf '%s' "$doc" | jq -r '.digest')"
    timestamp="$(printf '%s' "$doc" | jq -r '.timestamp')"

    local relpath
    relpath="$(deployment_journal.relpath "$timestamp" "$(_deployment_journal._uid)")"

    if [[ "$dry_run" == "true" ]]; then
        log.info "[dry-run] would publish deployed ${environment} ${version} at ${relpath}"
        return 0
    fi

    brik.use transverse.state_repo

    local dest
    dest="$(mktemp -d)" || { log.error "deployment_journal.publish: mktemp failed"; return "$BRIK_EXIT_IO_FAILURE"; }

    local -a clone_args=("$repo" "$dest")
    [[ -n "$branch" ]]    && clone_args+=(--branch "$branch")
    [[ -n "$token_var" ]] && clone_args+=(--token-var "$token_var")

    if ! transverse.state_repo.clone "${clone_args[@]}"; then
        rm -rf "$dest"
        return "$BRIK_EXIT_EXTERNAL_FAIL"
    fi

    if ! printf '%s' "$doc" | transverse.state_repo.append "$dest" "$relpath"; then
        rm -rf "$dest"
        return "$BRIK_EXIT_IO_FAILURE"
    fi

    local -a commit_args=("$dest" "deployment: deployed ${environment} ${version} ${digest}")
    [[ "$sign" == "true" ]] && commit_args+=(--sign)
    if ! transverse.state_repo.commit "${commit_args[@]}"; then
        rm -rf "$dest"
        return "$BRIK_EXIT_EXTERNAL_FAIL"
    fi

    rc=0
    transverse.state_repo.push "$dest" || rc="$BRIK_EXIT_EXTERNAL_FAIL"

    rm -rf "$dest"
    return "$rc"
}

# Record a deployed event in the project's declared state-repo
# (.artifacts.evidence.*: decision #3, one state-repo per project). Self-skips
# when no repo is declared -- an unjournaled deploy is a declared posture, the
# aggregate report still records the run. A declared journal that cannot
# record is an error: the run is failed (never silent) and the event is
# recovered by re-running the deploy (the re-entry converges and journals).
# Usage: deployment_journal.record_deployment --environment <e> --version <v>
#        --digest <d> --definition-hash <h> [--version-ref <sha>]
#        [--env-config-ref <sha>] [--run-id <id>] [--run-url <url>] [--actor <a>]
deployment_journal.record_deployment() {
    local environment="" version="" digest="" definition_hash=""
    local version_ref="" env_config_ref="" run_id="" run_url="" actor=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --environment)     environment="$2";     shift 2 ;;
            --version)         version="$2";         shift 2 ;;
            --digest)          digest="$2";          shift 2 ;;
            --definition-hash) definition_hash="$2"; shift 2 ;;
            --version-ref)     version_ref="$2";     shift 2 ;;
            --env-config-ref)  env_config_ref="$2";  shift 2 ;;
            --run-id)          run_id="$2";          shift 2 ;;
            --run-url)         run_url="$2";         shift 2 ;;
            --actor)           actor="$2";           shift 2 ;;
            *) log.error "deployment_journal.record_deployment: unknown option: $1"
               return "$BRIK_EXIT_INVALID_INPUT" ;;
        esac
    done

    brik.use transverse.config

    local repo
    repo="$(config.get '.artifacts.evidence.repo' '' 2>/dev/null || printf '')"
    if [[ -z "$repo" ]]; then
        log.info "no state-repo declared; not journaling the deployment"
        return 0
    fi

    local branch token_var sign
    branch="$(config.get '.artifacts.evidence.branch' '' 2>/dev/null || printf '')"
    token_var="$(config.get '.artifacts.evidence.token_var' '' 2>/dev/null || printf '')"
    sign="$(config.get '.artifacts.evidence.sign' 'false' 2>/dev/null || printf 'false')"

    local -a pub=(--repo "$repo")
    [[ -n "$branch" ]]      && pub+=(--branch "$branch")
    [[ -n "$token_var" ]]   && pub+=(--token-var "$token_var")
    [[ "$sign" == "true" ]] && pub+=(--sign)

    local -a ev=(--environment "$environment" --version "$version"
                 --digest "$digest" --definition-hash "$definition_hash")
    [[ -n "$version_ref" ]]    && ev+=(--version-ref "$version_ref")
    [[ -n "$env_config_ref" ]] && ev+=(--env-config-ref "$env_config_ref")
    [[ -n "$run_id" ]]         && ev+=(--run-id "$run_id")
    [[ -n "$run_url" ]]        && ev+=(--run-url "$run_url")
    [[ -n "$actor" ]]          && ev+=(--actor "$actor")

    if ! deployment_journal.build_event "${ev[@]}" \
            | deployment_journal.publish "${pub[@]}"; then
        log.error "failed to journal the deployment of ${version} to ${environment}"
        return "$BRIK_EXIT_EXTERNAL_FAIL"
    fi
    log.info "journaled deployed ${version} (${environment})"
    return 0
}

# Read the journal of a cloned state-repo working tree and emit the events
# of an environment as a JSON array, optionally narrowed by digest. Every
# file under deployments/ is validated fail-closed first: one non-conforming
# entry poisons the whole read (CHECK_FAILED), because a status fed by a
# partially readable journal could present a state it cannot prove.
# Usage: deployment_journal.events_for <repo_dir> --environment <e>
#        [--digest <d>]
deployment_journal.events_for() {
    local repo_dir="${1:-}"
    [[ $# -ge 1 ]] && shift
    local environment="" digest=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --environment) environment="$2"; shift 2 ;;
            --digest)      digest="$2";      shift 2 ;;
            *) log.error "deployment_journal.events_for: unknown option: $1"
               return "$BRIK_EXIT_INVALID_INPUT" ;;
        esac
    done

    if [[ -z "$repo_dir" || -z "$environment" ]]; then
        log.error "deployment_journal.events_for: <repo_dir> and --environment are required"
        return "$BRIK_EXIT_INVALID_INPUT"
    fi

    if [[ ! -d "${repo_dir}/deployments" ]]; then
        printf '[]\n'
        return 0
    fi

    local -a files=()
    while IFS= read -r -d '' f; do
        files+=("$f")
    done < <(find "${repo_dir}/deployments" -type f -name '*.json' -print0 | sort -z)

    if [[ "${#files[@]}" -eq 0 ]]; then
        printf '[]\n'
        return 0
    fi

    local f
    for f in "${files[@]}"; do
        if ! _deployment_journal._validate <"$f"; then
            log.error "deployment_journal.events_for: journal entry does not validate: ${f}"
            return "$BRIK_EXIT_CHECK_FAILED"
        fi
    done

    # KCOV_EXCL_START -- inline jq filter body, not bash code
    jq -s \
        --arg environment "$environment" \
        --arg digest "$digest" '
        map(select(.environment == $environment))
        | map(select($digest == "" or .digest == $digest))' \
        "${files[@]}"
    # KCOV_EXCL_STOP
}
