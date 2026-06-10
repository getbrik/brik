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

    # Verify required tools before anything that consumes them (the
    # referential validation below parses YAML documents with yq).
    if ! command -v yq >/dev/null 2>&1; then
        log.error "yq is required but not available"
        return "$BRIK_EXIT_MISSING_DEP"
    fi

    # The infrastructure referential is mandatory: validate it eagerly
    # (schemas, binding references) and record its fingerprint so the run's
    # evidence pins the environment declaration it executed against. The
    # same fingerprint is stamped into plan.json by the planner.
    brik.use transverse.infra
    local infra_root infra_fingerprint
    infra_root="$(infra.root)" || return $?
    infra.validate "$infra_root" || return $?
    infra_fingerprint="$(infra.fingerprint "$infra_root")" || return $?
    log.info "infrastructure referential: ${infra_root} (${infra_fingerprint:0:12})"
    report.record "init" "tech" "infra_fingerprint" "$infra_fingerprint" 2>/dev/null || true

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
    local _tool_versions
    _tool_versions="$(_stages.init._collect_tool_versions 2>/dev/null)"
    if [[ -n "$_tool_versions" && "$_tool_versions" != "{}" ]]; then
        report.record_object "init" "tech" "tool_versions" "$_tool_versions" 2>/dev/null || true
    fi

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

    # Findings-management governance bootstrap. When the referential
    # declares a Policy document, fetch the org policy file it points at,
    # validate it, and compile a per-run cache that downstream stages
    # (apply_policy, expiring_soon) consume. The fetch is fail-closed: an
    # invalid or unreachable policy surfaces a CONFIG_ERROR rather than
    # silently falling back to the built-in preset, so a project governed
    # by org policy never silently regresses to defaults.
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

    _stages.init._resolve_git_identity
    _stages.init._record_env_section

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
# Records the resolved values in the report env section (consumed by
# pipeline.env.load in subsequent stages, after the post-stage projection
# hook mirrors them into BRIK_PIPELINE_ENV) AND exports them in the current
# shell so _record_env_section below can read them via ${BRIK_GIT_USER_*:-...}
# without re-doing the resolution.
_stages.init._resolve_git_identity() {
    local git_email git_name
    git_email="$(config.get '.git.user.email' '')"
    [[ -z "$git_email" ]] && git_email="${GITLAB_USER_EMAIL:-${CHANGE_AUTHOR_EMAIL:-brik-ci@brik.local}}"
    git_name="$(config.get '.git.user.name' '')"
    [[ -z "$git_name" ]] && git_name="${GITLAB_USER_NAME:-${CHANGE_AUTHOR_DISPLAY_NAME:-Brik CI}}"

    export BRIK_GIT_USER_EMAIL="$git_email"
    export BRIK_GIT_USER_NAME="$git_name"

    # Cross-stage publish via the report env section. The post-stage
    # projection hook (_stage.run._project_env) mirrors these into
    # BRIK_PIPELINE_ENV so transverse.git.config_identity sees them when
    # release runs.
    report.record "init" "env" "BRIK_GIT_USER_EMAIL" "$git_email" 2>/dev/null || true
    report.record "init" "env" "BRIK_GIT_USER_NAME"  "$git_name"  2>/dev/null || true
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
# stack and version. Thin wrapper over runner.resolve_stack_or_base (the
# single shared stack-or-base resolver): reads the project stack_version,
# then delegates so the resolution policy and the base fallback literal live
# in one place (lib/pipeline/runner-images.sh).
_stages.init._resolve_runner_image() {
    local stack="${BRIK_BUILD_STACK:-auto}"
    local version
    version="$(config.get '.project.stack_version' '')"

    local home="${BRIK_HOME:-/opt/brik}"
    if [[ -f "${home}/lib/pipeline/runner-images.sh" ]]; then
        # shellcheck source=/dev/null
        . "${home}/lib/pipeline/runner-images.sh" 2>/dev/null || true
    fi
    if declare -f runner.resolve_stack_or_base >/dev/null 2>&1; then
        runner.resolve_stack_or_base "$stack" "$version"
        return 0
    fi
    # runner-images.sh unavailable (degraded environment): emit the base ref
    # directly. Kept in sync with runner.base_image's default tag.
    printf '%s/brik-runner-base:latest' "${BRIK_RUNNER_REGISTRY:-ghcr.io/getbrik}"
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

# Emit a JSON object with the semver of each prerequisite tool that is
# present on the runner. Tools that are absent are omitted from the object
# so the consumer can distinguish "tool missing" (no key) from "tool
# present, version capture failed" (empty string).
# Output shape: {"yq": "4.45.1", "jq": "1.7.1", "jv": "0.5.0"}
# Used by stages.init for tech.tool_versions, surfaced in the init panel
# of the HTML report.
_stages.init._collect_tool_versions() {
    local _v_yq="" _v_jq="" _v_jv=""
    if command -v yq >/dev/null 2>&1; then
        # yq Go (Mike Farah): "yq (...) version v4.45.1"; yq python: "yq 3.2.3"
        _v_yq="$(yq --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1)"
    fi
    if command -v jq >/dev/null 2>&1; then
        # jq prints "jq-1.7.1"
        _v_jq="$(jq --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1)"
    fi
    if command -v jv >/dev/null 2>&1; then
        # jv (Santhosh Kumar's go-yaml validator) prints "jv version 0.5.0"
        _v_jv="$(jv --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1)"
    fi
    if command -v jq >/dev/null 2>&1; then
        # KCOV_EXCL_START -- inline jq script body, not bash code
        jq -nc \
            --arg yq "$_v_yq" \
            --arg jq "$_v_jq" \
            --arg jv "$_v_jv" \
            '{}
             + ( if $yq != "" then { yq: $yq } else {} end )
             + ( if $jq != "" then { jq: $jq } else {} end )
             + ( if $jv != "" then { jv: $jv } else {} end )'
        # KCOV_EXCL_STOP
    else
        printf '{}'
    fi
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
            --arg repo_url        "${BRIK_COMMIT_REPO_URL:-}" \
            '{}
             + ( if $sha             != "" then { sha:             $sha }             else {} end )
             + ( if $short_sha       != "" then { short_sha:       $short_sha }       else {} end )
             + ( if $ref             != "" then { ref:             $ref }             else {} end )
             + ( if $branch          != "" then { branch:          $branch }          else {} end )
             + ( if $tag             != "" then { tag:             $tag }             else {} end )
             + ( if $author          != "" then { author:          $author }          else {} end )
             + ( if $author_email    != "" then { author_email:    $author_email }    else {} end )
             + ( if $timestamp       != "" then { timestamp:       $timestamp }       else {} end )
             + ( if $message_subject != "" then { message_subject: $message_subject } else {} end )
             + ( if $repo_url        != "" then { repo_url:        $repo_url }        else {} end )')"
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

# stages.init publishes the cross-stage env contract through report.record
# env. The post-stage projection hook (_stage.run._project_env) mirrors the
# env section into .brik-logs/pipeline.env, which is now the single physical
# env file: GitLab declares it as artifacts.reports.dotenv, Jenkins reads it
# via brikReadDotenv, and the Bash runtime sources it via pipeline.env.load.
_stages.init._record_env_section() {
    # _kv KEY VALUE: publish through the report env section.
    _kv() {
        report.record "init" "env" "$1" "$2" 2>/dev/null || true
    }

    # Project identity (BRIK_BUILD_STACK already resolved by the caller).
    _kv BRIK_PROJECT_NAME        "$(config.get '.project.name' 'unnamed')"
    _kv BRIK_BUILD_STACK         "${BRIK_BUILD_STACK:-auto}"
    _kv BRIK_BUILD_STACK_VERSION "$(config.get '.project.stack_version' '')"
    # Resolve the project's stack image dynamically (node:22, python:3.13,
    # ...) and export it as BRIK_CI_IMAGE *before* consulting the registry:
    # the 'stack' runner_class declares image_env: BRIK_CI_IMAGE, so this is
    # the value it reads back by default.
    local _stack_default
    _stack_default="$(_stages.init._resolve_runner_image)"
    export BRIK_CI_IMAGE="$_stack_default"

    # Runner image map (Lot 3 of chantier 20260526). Each runner_class
    # declared in lib/registry/runner_classes.yml is exposed as a CI
    # variable so downstream GitLab jobs can substitute ${BRIK_IMG_<CLASS>}
    # in their image: directive without hardcoding the OCI path. The
    # Jenkins adapter (Lot 4) consumes the same SoT via
    # brikDriver.resolveImage. BRIK_IMG_STACK aliases BRIK_CI_IMAGE for
    # symmetric naming with the other classes.
    #
    # All five classes -- including the dynamic 'stack' -- are resolved
    # through registry.runner_class.image so that a single override file
    # (BRIK_RUNNER_CLASSES_FILE: an e2e stub fleet, a mirror, an air-gapped
    # registry) supersedes every image without editing the bundled default.
    # For 'stack' the default registry returns image_env BRIK_CI_IMAGE (the
    # dynamic image exported above), so default behaviour is unchanged; an
    # override that declares 'stack' as a static image wins.
    #
    # Note: 5 image vars + 15 base vars = 20 keys. GitLab's default
    # dotenv_variables PlanLimit is 20, hit as soon as release adds
    # BRIK_NEXT_VERSION. briklab raises this to 50 in
    # scripts/lib/setup/gitlab.sh::configure_dotenv_limit. Adopters
    # consuming Brik with a stock GitLab must apply the same bump
    # (documented in chantier 20260526).
    # Load the registry module that maps runner_class -> image. A silent
    # load failure here defeats the whole BRIK_RUNNER_CLASSES_FILE override
    # (every BRIK_IMG_* ends up empty and stages fall back to the default
    # image) with no operator signal, so surface it instead of discarding.
    if ! brik.use registry.registry; then
        log.warn "[init] registry module failed to load -- runner-class image overrides will not apply"
    fi

    # Resolve one runner_class image, capturing stderr+rc so a resolution
    # failure (missing/unreadable override file, unset image_env for a
    # dynamic class, yq absent, unknown class) is logged instead of silently
    # recording an empty value. log.warn writes to stderr, so it does not
    # pollute the value captured by the command substitution at the call
    # site. Prints the resolved image on stdout, or nothing on failure.
    _resolve_class() {
        local _class="$1" _out _rc
        _out="$(registry.runner_class.image "$_class" 2>&1)"; _rc=$?
        if [[ "$_rc" -ne 0 ]]; then
            log.warn "[init] runner_class.image ${_class} failed (rc=${_rc}): ${_out} [BRIK_RUNNER_CLASSES_FILE=${BRIK_RUNNER_CLASSES_FILE:-<unset>}]"
            return "$_rc"
        fi
        printf '%s' "$_out"
    }

    local _stack_image="$_stack_default"
    if declare -f registry.runner_class.image >/dev/null 2>&1; then
        local _resolved_stack
        _resolved_stack="$(_resolve_class stack)"
        [[ -n "$_resolved_stack" ]] && _stack_image="$_resolved_stack"
        _kv BRIK_IMG_BASE     "$(_resolve_class base)"
        _kv BRIK_IMG_ANALYSIS "$(_resolve_class analysis)"
        _kv BRIK_IMG_SCANNER  "$(_resolve_class scanner)"
        _kv BRIK_IMG_DEPLOY   "$(_resolve_class deploy)"
    fi
    _kv BRIK_CI_IMAGE            "$_stack_image"
    _kv BRIK_IMG_STACK           "$_stack_image"

    # Legacy quality and security gating env vars (BRIK_LINT_ENABLED,
    # BRIK_SAST_ENABLED, ...) are no longer emitted: stages always run
    # and the *.enabled=false opt-outs are surfaced as deprecation
    # warnings by _stages.init._warn_legacy_enabled_keys instead.

    # Git identity (already resolved + exported by _resolve_git_identity).
    _kv BRIK_GIT_USER_EMAIL "${BRIK_GIT_USER_EMAIL:-brik-ci@brik.local}"
    _kv BRIK_GIT_USER_NAME  "${BRIK_GIT_USER_NAME:-Brik CI}"

    # Release state (Phase 9.A). The planner stamps the same three values
    # into plan.json's release block; init mirrors them into the dotenv so
    # downstream stages (package, deploy, future promote) can read them as
    # CI variables without re-reading brik.yml or running git describe.
    brik.use transverse.release
    _kv BRIK_RELEASE_PROFILE "$(release.compute_profile)"
    _kv BRIK_PROJECT_VERSION "$(release.compute_version)"
    _kv BRIK_IS_CANDIDATE    "$(release.compute_is_candidate)"

    # Package / deploy gating (placeholder values that downstream CI rules
    # can read; chantier 9.B/E will refine these into the promote contract).
    _kv BRIK_PACKAGE_ENABLED "$(_stages.init._has_block '.package')"
    _kv BRIK_DEPLOY_ENABLED  "$(_stages.init._has_block '.deploy')"

    # Test reports opt-in (consumed by lib/stacks/<stack>.sh to inject
    # coverage/junit flags into the test command). Default: false ->
    # test runners keep their native defaults.
    _kv BRIK_TEST_REPORTS_ENABLED "$(config.get '.test.reports.enabled' 'false')"
    _kv BRIK_TEST_COVERAGE_FORMAT "$(config.get '.test.reports.coverage.format' 'auto')"
    _kv BRIK_TEST_COVERAGE_DIR    "$(config.get '.test.reports.coverage.output_dir' 'brik-artifacts/test/coverage')"
    _kv BRIK_TEST_JUNIT_PATH      "$(config.get '.test.reports.junit.output_path' 'brik-artifacts/test/junit.xml')"

    log.info "recorded 15 env keys for downstream stages"
}

# Fetch + compile the org policy file when the referential declares a
# Policy document. Silent no-op when no referential is configured or none
# declares a policy (the project keeps the built-in preset); fail-closed
# CONFIG_ERROR when a policy is declared but ambiguous, unreachable or
# invalid -- a governed project must never silently regress to defaults.
_stages.init._load_org_policy() {
    brik.use transverse.infra 2>/dev/null || return 0

    local names policy_name policy_url
    names="$(infra.policy_names 2>/dev/null)" || return 0
    [[ -n "$names" ]] || return 0

    if [[ "$(printf '%s\n' "$names" | wc -l)" -gt 1 ]]; then
        log.error "the referential declares several Policy documents (expected at most one): $(printf '%s' "$names" | tr '\n' ' ')"
        return "$BRIK_EXIT_CONFIG_ERROR"
    fi
    policy_name="$names"

    policy_url="$(infra.policy "$policy_name" | jq -r '.url')" || {
        log.error "cannot read the '${policy_name}' Policy document from the referential"
        return "$BRIK_EXIT_CONFIG_ERROR"
    }

    # Fail-closed: when a policy is declared, the org policy module MUST be
    # available. A stripped install or a corrupt module path silently
    # regressing to the built-in preset would defeat the governance gate.
    if ! brik.use transverse.findings.org_policy 2>/dev/null; then
        log.error "a Policy is declared but transverse.findings.org_policy is unavailable"
        return "$BRIK_EXIT_CONFIG_ERROR"
    fi
    if ! declare -f org_policy.load >/dev/null 2>&1; then
        log.error "a Policy is declared but org_policy.load is missing from the loader module"
        return "$BRIK_EXIT_CONFIG_ERROR"
    fi

    log.info "loading organizational policy '${policy_name}' from ${policy_url}"
    if ! org_policy.load "$policy_url"; then
        log.error "failed to load organizational policy: ${policy_url}"
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
