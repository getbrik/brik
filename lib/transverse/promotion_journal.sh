#!/usr/bin/env bash
# @module transverse.promotion_journal
# @requires jq git
# @description PromotionJournal: file-per-event, digest-bound promotion records.
#
# The journal lives under promotions/ in the state-repo (the same repository
# as the evidence store) and records artifact-scoped transitions as
# append-only, file-per-event commits: artifact_promoted (a channel move),
# artifact_validated_for and artifact_authorized_for (eligibility for an
# environment). Every event is bound to the image digest -- an eligibility
# granted to a version name alone could be replayed against a different
# artifact.
#
# Events are validated against schemas/state/v1/promotion-event.schema.json
# fail-closed at write AND at read: a journal entry that does not validate is
# an integrity failure, never a skip. Authorship and integrity come from the
# signed git commit that appends the file, not from fields in the document.
#
# Functions:
#   promotion_journal.relpath <timestamp> <uid> - the day-bucketed event path
#   promotion_journal.build_event --type ...    - emit a validated event JSON
#   promotion_journal.publish --repo ...        - commit an event (stdin)
#   promotion_journal.events_for <dir> --digest ... - read and filter events

# Guard against double-sourcing
[[ -n "${_BRIK_MODULE_TRANSVERSE_PROMOTION_JOURNAL_LOADED:-}" ]] && return 0
_BRIK_MODULE_TRANSVERSE_PROMOTION_JOURNAL_LOADED=1

# Validate one promotion event (stdin) against the state/v1 schema.
# Fail-closed: a missing schema file or no available validator refuses the
# event rather than letting an unvalidated document into the journal.
# Usage: <event> | _promotion_journal._validate
_promotion_journal._validate() {
    local schema="${BRIK_HOME:-/opt/brik}/schemas/state/v1/promotion-event.schema.json"
    if [[ ! -f "$schema" ]]; then
        log.error "promotion-event schema not found at ${schema}"
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
_promotion_journal._uid() {
    od -An -tx1 -N8 /dev/urandom | tr -d ' \n'
}

# Day-bucketed store path for an event. The ISO timestamp keeps the journal
# browsable by date; the uid makes concurrent events on the same second
# collision-free.
# Usage: promotion_journal.relpath <iso-timestamp> <uid>
promotion_journal.relpath() {
    local ts="$1" uid="$2"
    local date="${ts%%T*}"
    local compact="${ts//-/}"
    compact="${compact//:/}"
    printf 'promotions/%s/%s/%s/%s-%s.json' \
        "${date:0:4}" "${date:5:2}" "${date:8:2}" "$compact" "$uid"
}

# Build one promotion event on stdout, schema-validated fail-closed.
# artifact_promoted carries the channel transition; artifact_validated_for
# and artifact_authorized_for carry the target environment.
# Usage: promotion_journal.build_event --type <t> --version <v> --digest <d>
#        [--environment <e>] [--from-channel <c> --to-channel <c>]
#        [--timestamp <iso>]
promotion_journal.build_event() {
    local type="" version="" digest="" environment=""
    local from_channel="" to_channel="" timestamp=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --type)         type="$2";         shift 2 ;;
            --version)      version="$2";      shift 2 ;;
            --digest)       digest="$2";       shift 2 ;;
            --environment)  environment="$2";  shift 2 ;;
            --from-channel) from_channel="$2"; shift 2 ;;
            --to-channel)   to_channel="$2";   shift 2 ;;
            --timestamp)    timestamp="$2";    shift 2 ;;
            *) log.error "promotion_journal.build_event: unknown option: $1"
               return "$BRIK_EXIT_INVALID_INPUT" ;;
        esac
    done

    if [[ -z "$type" || -z "$version" ]]; then
        log.error "promotion_journal.build_event: --type and --version are required"
        return "$BRIK_EXIT_INVALID_INPUT"
    fi
    if [[ ! "$digest" =~ ^sha256:[0-9a-f]{64}$ ]]; then
        log.error "promotion_journal.build_event: --digest must be a sha256:HEX image digest (events bind to the artifact, not a tag)"
        return "$BRIK_EXIT_INVALID_INPUT"
    fi

    case "$type" in
        artifact_promoted)
            if [[ -z "$from_channel" || -z "$to_channel" ]]; then
                log.error "promotion_journal.build_event: artifact_promoted requires --from-channel and --to-channel"
                return "$BRIK_EXIT_INVALID_INPUT"
            fi
            ;;
        artifact_validated_for|artifact_authorized_for)
            if [[ -z "$environment" ]]; then
                log.error "promotion_journal.build_event: ${type} requires --environment"
                return "$BRIK_EXIT_INVALID_INPUT"
            fi
            ;;
        *)
            log.error "promotion_journal.build_event: unknown event type '${type}'"
            return "$BRIK_EXIT_INVALID_INPUT"
            ;;
    esac

    [[ -z "$timestamp" ]] && timestamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

    local event
    # KCOV_EXCL_START -- inline jq document body, not bash code
    event="$(jq -n \
        --arg type "$type" \
        --arg version "$version" \
        --arg digest "$digest" \
        --arg timestamp "$timestamp" \
        --arg environment "$environment" \
        --arg from_channel "$from_channel" \
        --arg to_channel "$to_channel" '
        {
          schema: "brik.promotion-event/v1",
          type: $type,
          version: $version,
          digest: $digest,
          timestamp: $timestamp
        }
        + (if $type == "artifact_promoted"
           then {from_channel: $from_channel, to_channel: $to_channel}
           else {environment: $environment}
           end)')"
    # KCOV_EXCL_STOP

    local rc=0
    printf '%s\n' "$event" | _promotion_journal._validate || rc=$?
    if [[ "$rc" -ne 0 ]]; then
        [[ "$rc" -eq "$BRIK_EXIT_INVALID_INPUT" ]] \
            && log.error "promotion_journal.build_event: the event does not validate against the promotion-event schema"
        return "$rc"
    fi
    printf '%s\n' "$event"
}

# Commit a promotion event (read from stdin) to the state-repo at its
# day-bucketed path. The event is re-validated fail-closed before anything
# touches the store; the append is append-only and the commit optionally
# ssh-signed.
# Usage: <event> | promotion_journal.publish --repo <url>
#        [--branch <b>] [--token-var <VAR>] [--sign] [--dry-run]
promotion_journal.publish() {
    local repo="" branch="" token_var="" sign="" dry_run="${BRIK_DRY_RUN:-}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --repo)      repo="$2";      shift 2 ;;
            --branch)    branch="$2";    shift 2 ;;
            --token-var) token_var="$2"; shift 2 ;;
            --sign)      sign="true";    shift ;;
            --dry-run)   dry_run="true"; shift ;;
            *) log.error "promotion_journal.publish: unknown option: $1"
               return "$BRIK_EXIT_INVALID_INPUT" ;;
        esac
    done

    if [[ -z "$repo" ]]; then
        cat >/dev/null   # consume the event so the producer does not block
        log.error "promotion_journal.publish: --repo is required"
        return "$BRIK_EXIT_INVALID_INPUT"
    fi

    local doc
    doc="$(cat)"

    local rc=0
    printf '%s\n' "$doc" | _promotion_journal._validate || rc=$?
    if [[ "$rc" -ne 0 ]]; then
        [[ "$rc" -eq "$BRIK_EXIT_INVALID_INPUT" ]] \
            && log.error "promotion_journal.publish: the event does not validate against the promotion-event schema -- refusing to append"
        return "$rc"
    fi

    local type version digest timestamp
    type="$(printf '%s' "$doc" | jq -r '.type')"
    version="$(printf '%s' "$doc" | jq -r '.version')"
    digest="$(printf '%s' "$doc" | jq -r '.digest')"
    timestamp="$(printf '%s' "$doc" | jq -r '.timestamp')"

    local relpath
    relpath="$(promotion_journal.relpath "$timestamp" "$(_promotion_journal._uid)")"

    if [[ "$dry_run" == "true" ]]; then
        log.info "[dry-run] would publish ${type} ${version} at ${relpath}"
        return 0
    fi

    brik.use transverse.state_repo

    local dest
    dest="$(mktemp -d)" || { log.error "promotion_journal.publish: mktemp failed"; return "$BRIK_EXIT_IO_FAILURE"; }

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

    local -a commit_args=("$dest" "promotion: ${type} ${version} ${digest}")
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

# Record an artifact_promoted event in the project's declared state-repo
# (.artifacts.evidence.*: decision #3, one state-repo per project). Self-skips
# when no repo is declared -- an unjournaled promotion is a declared posture,
# the attestations on the digest stand on their own. A declared journal that
# cannot record is an error: gates downstream rely on it.
# Usage: promotion_journal.record_promotion --version <v> --digest <d>
#        --from-channel <c> --to-channel <c>
promotion_journal.record_promotion() {
    local version="" digest="" from_channel="" to_channel=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --version)      version="$2";      shift 2 ;;
            --digest)       digest="$2";       shift 2 ;;
            --from-channel) from_channel="$2"; shift 2 ;;
            --to-channel)   to_channel="$2";   shift 2 ;;
            *) log.error "promotion_journal.record_promotion: unknown option: $1"
               return "$BRIK_EXIT_INVALID_INPUT" ;;
        esac
    done

    brik.use transverse.config

    local repo
    repo="$(config.get '.artifacts.evidence.repo' '' 2>/dev/null || printf '')"
    if [[ -z "$repo" ]]; then
        log.info "no state-repo declared; not journaling the promotion"
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

    if ! promotion_journal.build_event \
            --type artifact_promoted \
            --version "$version" --digest "$digest" \
            --from-channel "$from_channel" --to-channel "$to_channel" \
            | promotion_journal.publish "${pub[@]}"; then
        log.error "failed to journal the promotion of ${version} (${from_channel} -> ${to_channel})"
        return "$BRIK_EXIT_EXTERNAL_FAIL"
    fi
    log.info "journaled artifact_promoted ${version} (${from_channel} -> ${to_channel})"
    return 0
}

# Record an artifact_authorized_for event in the project's declared
# state-repo. Unlike record_promotion this does NOT self-skip: an
# authorization only exists as a journal entry, so a project without a
# declared state-repo has nothing to grant against -- fail closed.
# Usage: promotion_journal.record_authorization --version <v> --digest <d>
#        --environment <e>
promotion_journal.record_authorization() {
    local version="" digest="" environment=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --version)     version="$2";     shift 2 ;;
            --digest)      digest="$2";      shift 2 ;;
            --environment) environment="$2"; shift 2 ;;
            *) log.error "promotion_journal.record_authorization: unknown option: $1"
               return "$BRIK_EXIT_INVALID_INPUT" ;;
        esac
    done

    brik.use transverse.config

    local repo
    repo="$(config.get '.artifacts.evidence.repo' '' 2>/dev/null || printf '')"
    if [[ -z "$repo" ]]; then
        log.error "no state-repo declared (.artifacts.evidence.repo): an authorization only exists as a journal entry -- refusing"
        return "$BRIK_EXIT_CONFIG_ERROR"
    fi

    local branch token_var sign
    branch="$(config.get '.artifacts.evidence.branch' '' 2>/dev/null || printf '')"
    token_var="$(config.get '.artifacts.evidence.token_var' '' 2>/dev/null || printf '')"
    sign="$(config.get '.artifacts.evidence.sign' 'false' 2>/dev/null || printf 'false')"

    local -a pub=(--repo "$repo")
    [[ -n "$branch" ]]      && pub+=(--branch "$branch")
    [[ -n "$token_var" ]]   && pub+=(--token-var "$token_var")
    [[ "$sign" == "true" ]] && pub+=(--sign)

    if ! promotion_journal.build_event \
            --type artifact_authorized_for \
            --version "$version" --digest "$digest" \
            --environment "$environment" \
            | promotion_journal.publish "${pub[@]}"; then
        log.error "failed to journal the authorization of ${version} for ${environment}"
        return "$BRIK_EXIT_EXTERNAL_FAIL"
    fi
    log.info "journaled artifact_authorized_for ${version} (${environment})"
    return 0
}

# Record an artifact_validated_for event in the project's declared
# state-repo. Emitted by the CD flow after a green deploy on an environment
# that declares validates_for: the artifact becomes eligible for the NEXT
# environment of the chain. Like record_authorization this does NOT
# self-skip: a validation only exists as a journal entry, so a declared
# chain without a state-repo has nothing to validate into -- fail closed.
# Usage: promotion_journal.record_validation --version <v> --digest <d>
#        --environment <e>
promotion_journal.record_validation() {
    local version="" digest="" environment=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --version)     version="$2";     shift 2 ;;
            --digest)      digest="$2";      shift 2 ;;
            --environment) environment="$2"; shift 2 ;;
            *) log.error "promotion_journal.record_validation: unknown option: $1"
               return "$BRIK_EXIT_INVALID_INPUT" ;;
        esac
    done

    brik.use transverse.config

    local repo
    repo="$(config.get '.artifacts.evidence.repo' '' 2>/dev/null || printf '')"
    if [[ -z "$repo" ]]; then
        log.error "no state-repo declared (.artifacts.evidence.repo): a validation only exists as a journal entry -- refusing"
        return "$BRIK_EXIT_CONFIG_ERROR"
    fi

    local branch token_var sign
    branch="$(config.get '.artifacts.evidence.branch' '' 2>/dev/null || printf '')"
    token_var="$(config.get '.artifacts.evidence.token_var' '' 2>/dev/null || printf '')"
    sign="$(config.get '.artifacts.evidence.sign' 'false' 2>/dev/null || printf 'false')"

    local -a pub=(--repo "$repo")
    [[ -n "$branch" ]]      && pub+=(--branch "$branch")
    [[ -n "$token_var" ]]   && pub+=(--token-var "$token_var")
    [[ "$sign" == "true" ]] && pub+=(--sign)

    if ! promotion_journal.build_event \
            --type artifact_validated_for \
            --version "$version" --digest "$digest" \
            --environment "$environment" \
            | promotion_journal.publish "${pub[@]}"; then
        log.error "failed to journal the validation of ${version} for ${environment}"
        return "$BRIK_EXIT_EXTERNAL_FAIL"
    fi
    log.info "journaled artifact_validated_for ${version} (${environment})"
    return 0
}

# Read the journal of a cloned state-repo working tree and emit the events
# bound to a digest as a JSON array, optionally narrowed by environment and
# type. Every file under promotions/ is validated fail-closed first: one
# non-conforming entry poisons the whole read (CHECK_FAILED), because a gate
# fed by a partially readable journal could grant an eligibility it cannot
# prove.
# Usage: promotion_journal.events_for <repo_dir> --digest <d>
#        [--environment <e>] [--type <t>]
promotion_journal.events_for() {
    local repo_dir="${1:-}"
    [[ $# -ge 1 ]] && shift
    local digest="" environment="" type=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --digest)      digest="$2";      shift 2 ;;
            --environment) environment="$2"; shift 2 ;;
            --type)        type="$2";        shift 2 ;;
            *) log.error "promotion_journal.events_for: unknown option: $1"
               return "$BRIK_EXIT_INVALID_INPUT" ;;
        esac
    done

    if [[ -z "$repo_dir" || -z "$digest" ]]; then
        log.error "promotion_journal.events_for: <repo_dir> and --digest are required"
        return "$BRIK_EXIT_INVALID_INPUT"
    fi

    if [[ ! -d "${repo_dir}/promotions" ]]; then
        printf '[]\n'
        return 0
    fi

    local -a files=()
    while IFS= read -r -d '' f; do
        files+=("$f")
    done < <(find "${repo_dir}/promotions" -type f -name '*.json' -print0 | sort -z)

    if [[ "${#files[@]}" -eq 0 ]]; then
        printf '[]\n'
        return 0
    fi

    local f
    for f in "${files[@]}"; do
        if ! _promotion_journal._validate <"$f"; then
            log.error "promotion_journal.events_for: journal entry does not validate: ${f}"
            return "$BRIK_EXIT_CHECK_FAILED"
        fi
    done

    # KCOV_EXCL_START -- inline jq filter body, not bash code
    jq -s \
        --arg digest "$digest" \
        --arg environment "$environment" \
        --arg type "$type" '
        map(select(.digest == $digest))
        | map(select($environment == "" or .environment == $environment))
        | map(select($type == "" or .type == $type))' \
        "${files[@]}"
    # KCOV_EXCL_STOP
}
