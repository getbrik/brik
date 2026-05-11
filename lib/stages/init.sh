#!/usr/bin/env bash
# @module stages/init
# @description Init stage - detect stack, validate config, setup environment.

# Init stage: detect stack, validate config, setup environment.
# Usage: stages.init <context_file>
stages.init() {
    # context_file positionally passed by stage.run; unused here after §4.2
    # migration (detected stack now lands in the pipeline report's business
    # section via report.record).
    # shellcheck disable=SC2034
    local context_file="$1"

    log.info "initializing pipeline"

    # Validate brik.yml exists
    if [[ ! -f "${BRIK_CONFIG_FILE}" ]]; then
        log.error "brik.yml not found at ${BRIK_CONFIG_FILE}"
        return "$BRIK_EXIT_CONFIG_ERROR"
    fi

    # Validate brik.yml against the JSON Schema (graceful skip if jv absent).
    config.validate_schema || return $?

    # Detect or read stack
    local stack
    stack="$(config.get '.project.stack' 'auto')"

    if [[ "$stack" == "auto" ]]; then
        brik.use stacks._detect
        stack="$(stacks.detect "${BRIK_WORKSPACE}")" || {
            log.warn "could not auto-detect stack, continuing without stack-specific defaults"
            stack="unknown"
        }
        log.info "auto-detected stack: $stack"
    else
        log.info "configured stack: $stack"
    fi

    report.record "init" "tech" "stack" "$stack" 2>/dev/null || true
    report.record "init" "tech" "stack_version" \
        "$(config.get '.project.stack_version' '')" 2>/dev/null || true
    report.record "init" "tech" "config_file" "${BRIK_CONFIG_FILE}" 2>/dev/null || true
    report.record_object "init" "tech" "config_valid" "true" 2>/dev/null || true
    report.record_object "init" "tech" "prereqs_present" \
        "$(_stages.init._collect_prereqs)" 2>/dev/null || true

    # Export config and override stack with the runtime-resolved value.
    # config.export_build_vars re-reads .project.stack from brik.yml, which may
    # be "auto". The init-resolved $stack (e.g. "node") must take precedence.
    config.export_all || return $?
    export BRIK_BUILD_STACK="$stack"
    config.validate_coherence || return $?

    # Surface deprecation of the legacy *.enabled=false stage opt-outs. The
    # stages no longer honour these keys: lint, sast, scan, container-scan
    # always run. The dotenv still exports BRIK_*_ENABLED for any external
    # consumer that scrapes the pipeline env, but the runtime ignores them.
    _stages.init._warn_legacy_enabled_keys

    # Load project-level env file (brik.yml .project.env or auto-detect brik.env).
    # Exports variables that subsequent stages can reference. Existing
    # environment values (CI secrets etc.) take precedence over file entries.
    # Fails the init stage when .project.env is declared but the file is missing.
    brik.use transverse.env
    transverse.env.load_project || return "$BRIK_EXIT_CONFIG_ERROR"

    # Findings-management governance bootstrap (chantier 20260508 P6.C).
    # When BRIK_POLICY_URL is set, fetch the DSI policy file, validate it,
    # and compile a per-run cache that downstream stages (apply_policy,
    # expiring_soon) consume. The fetch is fail-closed: an invalid or
    # unreachable URL surfaces a CONFIG_ERROR rather than silently falling
    # back to the built-in preset, so a project that opted into org policy
    # never silently regresses to defaults.
    _stages.init._load_org_policy || return $?
    # Surface upcoming allowlist expirations as a non-blocking notice and
    # record them in business.policy.expiring_soon for the report.
    _stages.init._record_expiring_soon

    # Log project info
    local project_name
    project_name="$(config.get '.project.name' 'unnamed')"
    log.info "project: $project_name"
    log.info "workspace: ${BRIK_WORKSPACE}"
    log.info "platform: ${BRIK_PLATFORM:-unknown}"

    # Provenance & identity. Provenance fields are sourced from BRIK_*
    # populated by _pipeline.detect_metadata (lib/pipeline/stage.sh) at
    # stage.dispatch entry. Empty fields are skipped so the aggregate
    # omits them rather than emitting empty strings.
    report.record "init" "business" "project_name" "$project_name" 2>/dev/null || true
    report.record "init" "business" "platform" "${BRIK_PLATFORM:-unknown}" 2>/dev/null || true
    local _commit_obj
    _commit_obj="$(_stages.init._build_commit_object)"
    if [[ "$_commit_obj" != "{}" ]]; then
        report.record_object "init" "business" "commit" "$_commit_obj" 2>/dev/null || true
    fi
    local _pipeline_obj
    _pipeline_obj="$(_stages.init._build_pipeline_ref_object)"
    if [[ "$_pipeline_obj" != "{}" ]]; then
        report.record_object "init" "business" "pipeline" "$_pipeline_obj" 2>/dev/null || true
    fi
    if [[ -n "${BRIK_TRIGGERED_BY:-}" ]]; then
        report.record "init" "business" "triggered_by" "$BRIK_TRIGGERED_BY" 2>/dev/null || true
    fi

    # Verify required tools
    if ! command -v yq >/dev/null 2>&1; then
        log.error "yq is required but not available"
        return "$BRIK_EXIT_MISSING_DEP"
    fi

    _stages.init._resolve_git_identity
    _stages.init._write_dotenv

    log.info "init stage complete"
    return 0
}

# Resolve the git user identity for downstream stages that commit or annotate
# tags (release.prepare, deploy.gitops). Resolution order, first non-empty
# wins:
#   1. brik.yml .git.user.email / .git.user.name
#   2. CI platform vars: $GITLAB_USER_EMAIL / $CHANGE_AUTHOR_EMAIL,
#      $GITLAB_USER_NAME / $CHANGE_AUTHOR_DISPLAY_NAME
#   3. fallback "brik-ci@brik.local" / "Brik CI"
#
# Writes the resolved values to the pipeline env file (consumed by
# pipeline.env.load in subsequent stages) AND exports them in the current
# shell so the caller of _write_dotenv below can echo them into brik-init.env
# without re-doing the resolution.
_stages.init._resolve_git_identity() {
    local git_email git_name
    git_email="$(config.get '.git.user.email' '')"
    [[ -z "$git_email" ]] && git_email="${GITLAB_USER_EMAIL:-${CHANGE_AUTHOR_EMAIL:-brik-ci@brik.local}}"
    git_name="$(config.get '.git.user.name' '')"
    [[ -z "$git_name" ]] && git_name="${GITLAB_USER_NAME:-${CHANGE_AUTHOR_DISPLAY_NAME:-Brik CI}}"

    export BRIK_GIT_USER_EMAIL="$git_email"
    export BRIK_GIT_USER_NAME="$git_name"

    pipeline.env.set "BRIK_GIT_USER_EMAIL" "$git_email" 2>/dev/null || true
    pipeline.env.set "BRIK_GIT_USER_NAME"  "$git_name"  2>/dev/null || true
}

# Warn the user when their brik.yml carries one of the legacy
# *.enabled=false stage opt-outs. The stages used to honour these keys
# outside a release context; the new runtime ignores them and runs the
# stage unconditionally. Emitting the warning at init-time gives the
# operator a chance to spot the silent behaviour change before the stage
# runs.
#
# Silent when the key is absent or set to its default value (true).
_stages.init._warn_legacy_enabled_keys() {
    local key val
    for key in \
        ".quality.lint.enabled" \
        ".security.sast.enabled" \
        ".security.scan.enabled" \
        ".security.container_scan.enabled"
    do
        val="$(config.get "$key" 'true')"
        if [[ "$val" == "false" ]]; then
            log.warn "${key#.}=false is deprecated and ignored: the stage will run regardless"
        fi
    done
}

# Resolve the runner image to use for downstream jobs based on the active
# stack and version. Falls back to the base runner if no specific match.
_stages.init._resolve_runner_image() {
    local stack="${BRIK_BUILD_STACK:-auto}"
    local version
    version="$(config.get '.project.stack_version' '')"

    local home="${BRIK_HOME:-/opt/brik}"
    if [[ -f "${home}/lib/pipeline/runner-images.sh" ]]; then
        # shellcheck source=/dev/null
        . "${home}/lib/pipeline/runner-images.sh" 2>/dev/null || true
        local image
        image="$(runner.resolve_image "$stack" "$version" 2>/dev/null)" && {
            printf '%s' "$image"
            return 0
        }
    fi
    printf 'ghcr.io/getbrik/brik-runner-base:latest'
}

# Emit a JSON object listing prerequisite tools and their availability.
# Schema: {"yq": bool, "jq": bool, "jv": bool}. Used by stages.init for
# tech.prereqs_present so DSI can audit the runner's toolchain at a
# glance. Locals are prefixed _p_ to avoid dynamic-scope shadowing of
# variables declared by report.record / _report._append_json_object.
_stages.init._collect_prereqs() {
    local _p_yq _p_jq _p_jv
    command -v yq >/dev/null 2>&1 && _p_yq=true || _p_yq=false
    command -v jq >/dev/null 2>&1 && _p_jq=true || _p_jq=false
    command -v jv >/dev/null 2>&1 && _p_jv=true || _p_jv=false
    printf '{"yq":%s,"jq":%s,"jv":%s}' "$_p_yq" "$_p_jq" "$_p_jv"
}

# Build a JSON object of the populated BRIK_COMMIT_* fields. Returns
# "{}" when no commit metadata is set so the caller can omit the
# business.commit key entirely.
_stages.init._build_commit_object() {
    local _p_obj="{}"
    if command -v jq >/dev/null 2>&1; then
        # KCOV_EXCL_START -- inline jq script body, not bash code
        _p_obj="$(jq -nc \
            --arg sha             "${BRIK_COMMIT_SHA:-}" \
            --arg short_sha       "${BRIK_COMMIT_SHORT_SHA:-}" \
            --arg ref             "${BRIK_COMMIT_REF:-}" \
            --arg branch          "${BRIK_COMMIT_BRANCH:-}" \
            --arg tag             "${BRIK_COMMIT_TAG:-}" \
            --arg author          "${BRIK_COMMIT_AUTHOR:-}" \
            --arg author_email    "${BRIK_COMMIT_AUTHOR_EMAIL:-}" \
            --arg timestamp       "${BRIK_COMMIT_TIMESTAMP:-}" \
            --arg message_subject "${BRIK_COMMIT_MESSAGE_SUBJECT:-}" \
            '{}
             + ( if $sha             != "" then { sha:             $sha }             else {} end )
             + ( if $short_sha       != "" then { short_sha:       $short_sha }       else {} end )
             + ( if $ref             != "" then { ref:             $ref }             else {} end )
             + ( if $branch          != "" then { branch:          $branch }          else {} end )
             + ( if $tag             != "" then { tag:             $tag }             else {} end )
             + ( if $author          != "" then { author:          $author }          else {} end )
             + ( if $author_email    != "" then { author_email:    $author_email }    else {} end )
             + ( if $timestamp       != "" then { timestamp:       $timestamp }       else {} end )
             + ( if $message_subject != "" then { message_subject: $message_subject } else {} end )')"
        # KCOV_EXCL_STOP
    fi
    printf '%s' "$_p_obj"
}

# Build a JSON object of the populated BRIK_PIPELINE_* fields. Returns
# "{}" when no pipeline reference is set.
_stages.init._build_pipeline_ref_object() {
    local _p_obj="{}"
    if command -v jq >/dev/null 2>&1; then
        # KCOV_EXCL_START -- inline jq script body, not bash code
        _p_obj="$(jq -nc \
            --arg id  "${BRIK_PIPELINE_ID:-}" \
            --arg url "${BRIK_PIPELINE_URL:-}" \
            '{}
             + ( if $id  != "" then { id:  $id }  else {} end )
             + ( if $url != "" then { url: $url } else {} end )')"
        # KCOV_EXCL_STOP
    fi
    printf '%s' "$_p_obj"
}

# Detect whether a top-level brik.yml block exists (e.g. .package, .deploy).
# Prints "true" if the block is present and non-null, "false" otherwise.
_stages.init._has_block() {
    local path="$1"
    local val
    val="$(yq "${path} // null" "${BRIK_CONFIG_FILE}" 2>/dev/null)"
    [[ "$val" != "null" && -n "$val" ]] && printf 'true' || printf 'false'
}

# stages.init becomes the single source of truth for the dotenv consumed by
# CI rules and downstream jobs. The schema is contractual: every key has a
# predictable value with a sensible default if brik.yml does not specify it.
# The dotenv lives at $BRIK_WORKSPACE/brik-init.env (the path GitLab's
# artifacts.reports.dotenv consumes).
_stages.init._write_dotenv() {
    local dotenv="${BRIK_WORKSPACE:-.}/brik-init.env"

    {
        # Project identity (BRIK_BUILD_STACK already resolved by the caller).
        printf 'BRIK_PROJECT_NAME=%s\n' "$(config.get '.project.name' 'unnamed')"
        printf 'BRIK_BUILD_STACK=%s\n'  "${BRIK_BUILD_STACK:-auto}"
        printf 'BRIK_BUILD_STACK_VERSION=%s\n' "$(config.get '.project.stack_version' '')"
        printf 'BRIK_CI_IMAGE=%s\n' "$(_stages.init._resolve_runner_image)"

        # Legacy quality and security gating env vars (BRIK_LINT_ENABLED,
        # BRIK_SAST_ENABLED, ...) are no longer emitted: stages always run
        # and the *.enabled=false opt-outs are surfaced as deprecation
        # warnings by _stages.init._warn_legacy_enabled_keys instead.

        # Git identity (already resolved + exported by _resolve_git_identity).
        printf 'BRIK_GIT_USER_EMAIL=%s\n' "${BRIK_GIT_USER_EMAIL:-brik-ci@brik.local}"
        printf 'BRIK_GIT_USER_NAME=%s\n'  "${BRIK_GIT_USER_NAME:-Brik CI}"

        # Release / package / deploy gating (placeholder values that downstream
        # CI rules can read; chantier 9.A will refine release.profile).
        printf 'BRIK_RELEASE_PROFILE=%s\n' "$(config.get '.release.profile' 'none')"
        printf 'BRIK_PACKAGE_ENABLED=%s\n' "$(_stages.init._has_block '.package')"
        printf 'BRIK_DEPLOY_ENABLED=%s\n'  "$(_stages.init._has_block '.deploy')"

        # Test reports opt-in (consumed by lib/stacks/<stack>.sh to inject
        # coverage/junit flags into the test command). Default: false ->
        # test runners keep their native defaults.
        printf 'BRIK_TEST_REPORTS_ENABLED=%s\n'  "$(config.get '.test.reports.enabled' 'false')"
        printf 'BRIK_TEST_COVERAGE_FORMAT=%s\n' "$(config.get '.test.reports.coverage.format' 'auto')"
        printf 'BRIK_TEST_COVERAGE_DIR=%s\n'    "$(config.get '.test.reports.coverage.output_dir' 'brik-artifacts/test/coverage')"
        printf 'BRIK_TEST_JUNIT_PATH=%s\n'      "$(config.get '.test.reports.junit.output_path' 'brik-artifacts/test/junit.xml')"
    } > "$dotenv" 2>/dev/null || {
        log.warn "could not write dotenv to $dotenv"
        return 0
    }

    # Mirror every key into the pipeline env file so Jenkins (which loads
    # pipeline.env at each stage via pipeline.env.load) sees the same
    # values as GitLab (which gets brik-init.env auto-injected via the
    # artifacts.reports.dotenv mechanism).
    local _line _key _val
    while IFS= read -r _line; do
        [[ -z "$_line" ]] && continue
        _key="${_line%%=*}"
        _val="${_line#*=}"
        pipeline.env.set "$_key" "$_val" 2>/dev/null || true
    done < "$dotenv"

    log.info "wrote $(wc -l < "$dotenv" 2>/dev/null | tr -d ' ') variables to $dotenv"
}

# Fetch + compile the DSI policy file when BRIK_POLICY_URL is set.
# Silent no-op when unset (project keeps the built-in preset); fail-closed
# CONFIG_ERROR when the URL is set but unreachable / invalid -- a project
# that opted into org policy must never silently regress to defaults.
_stages.init._load_org_policy() {
    [[ -n "${BRIK_POLICY_URL:-}" ]] || return 0

    # Fail-closed: when BRIK_POLICY_URL is set, the org policy module MUST
    # be available. A stripped install or a corrupt module path silently
    # regressing to the built-in preset would defeat the governance gate.
    if ! brik.use transverse.findings.org_policy 2>/dev/null; then
        log.error "BRIK_POLICY_URL is set but transverse.findings.org_policy is unavailable"
        return "$BRIK_EXIT_CONFIG_ERROR"
    fi
    if ! declare -f org_policy.load >/dev/null 2>&1; then
        log.error "BRIK_POLICY_URL is set but org_policy.load is missing from the loader module"
        return "$BRIK_EXIT_CONFIG_ERROR"
    fi

    log.info "loading organizational policy from $BRIK_POLICY_URL"
    if ! org_policy.load "$BRIK_POLICY_URL"; then
        log.error "failed to load organizational policy: $BRIK_POLICY_URL"
        return "$BRIK_EXIT_CONFIG_ERROR"
    fi
    return 0
}

# Surface allowlist entries whose expires falls within
# BRIK_FINDINGS_EXPIRING_SOON_DAYS (default 30) as a non-blocking notice
# and record the list under business.policy for the aggregate report.
# Silent no-op when no policy is loaded.
_stages.init._record_expiring_soon() {
    brik.use transverse.findings 2>/dev/null || return 0
    if ! declare -f findings.expiring_soon >/dev/null 2>&1; then
        return 0
    fi

    local _expiring
    _expiring="$(findings.expiring_soon 2>/dev/null)" || _expiring="[]"
    [[ -z "$_expiring" ]] && _expiring="[]"

    local _count=0
    if command -v jq >/dev/null 2>&1; then
        _count="$(printf '%s' "$_expiring" | jq -r 'length' 2>/dev/null || printf '0')"
    fi
    [[ "$_count" =~ ^[0-9]+$ ]] || _count=0

    if [[ "$_count" -gt 0 ]]; then
        log.warn "${_count} organizational policy entries expire within \
${BRIK_FINDINGS_EXPIRING_SOON_DAYS:-30} days"
        # Best-effort log of each entry id/glob so the operator sees what
        # is about to expire even when the aggregate report is not consulted.
        if command -v jq >/dev/null 2>&1; then
            local _line
            while IFS= read -r _line; do
                [[ -n "$_line" ]] && log.warn "  $_line"
            done < <(printf '%s' "$_expiring" \
                | jq -r '.[] | "\(.type):\(.id // .glob) expires=\(.expires)"' 2>/dev/null \
                || true)
        fi

        report.record_object "init" "business" "policy_expiring_soon" \
            "$_expiring" 2>/dev/null || true
    fi
    return 0
}
