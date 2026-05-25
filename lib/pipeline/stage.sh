#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# @module stage
# @description Stage lifecycle orchestrator for the Brik runtime.
#
# stage.run is the central entry point for every stage in the fixed flow.
# It manages context, logging, hooks, execution, summary, and cleanup.
#
# stage.run MUST NOT:
#   - contain business logic
#   - call exit
#   - depend on set -e

# Guard against double-sourcing
[[ -n "${_BRIK_STAGE_LOADED:-}" ]] && return 0
_BRIK_STAGE_LOADED=1

# Source all runtime modules
_stage._load_runtime() {
    local runtime_dir="${BASH_SOURCE[0]%/*}"
    # shellcheck source=version-info.sh
    [[ -z "${_BRIK_VERSION_INFO_LOADED:-}" ]] && . "${runtime_dir}/version-info.sh"
    # shellcheck source=logging.sh
    [[ -z "${_BRIK_LOGGING_LOADED:-}" ]] && . "${runtime_dir}/logging.sh"
    # shellcheck source=error.sh
    [[ -z "${_BRIK_ERROR_LOADED:-}" ]] && . "${runtime_dir}/error.sh"
    # shellcheck source=tools.sh
    [[ -z "${_BRIK_TOOLS_LOADED:-}" ]] && . "${runtime_dir}/tools.sh"
    # shellcheck source=context.sh
    [[ -z "${_BRIK_CONTEXT_LOADED:-}" ]] && . "${runtime_dir}/context.sh"
    # shellcheck source=hooks.sh
    [[ -z "${_BRIK_HOOKS_LOADED:-}" ]] && . "${runtime_dir}/hooks.sh"
    # shellcheck source=summary.sh
    [[ -z "${_BRIK_SUMMARY_LOADED:-}" ]] && . "${runtime_dir}/summary.sh"
    # shellcheck source=bootstrap.sh
    [[ -z "${_BRIK_BOOTSTRAP_LOADED:-}" ]] && . "${runtime_dir}/bootstrap.sh"
    # shellcheck source=pipeline-env.sh
    [[ -z "${_BRIK_PIPELINE_ENV_LOADED:-}" ]] && . "${runtime_dir}/pipeline-env.sh"
    # shellcheck source=banner.sh
    [[ -z "${_BRIK_BANNER_LOADED:-}" ]] && . "${runtime_dir}/banner.sh"
    # shellcheck source=report.sh
    [[ -z "${_BRIK_REPORT_LOADED:-}" ]] && . "${runtime_dir}/report.sh"
    # shellcheck source=business.sh
    [[ -z "${_BRIK_BUSINESS_LOADED:-}" ]] && . "${runtime_dir}/business.sh"
    # shellcheck source=../registry/registry.sh
    [[ -z "${_BRIK_REGISTRY_LOADED:-}" ]] && . "${runtime_dir}/../registry/registry.sh"
}

_stage._load_runtime

# Print the current Unix time in milliseconds as a 13-digit integer.
# Uses bash 5+ EPOCHREALTIME (fork-free) when available; falls back to
# date +%s * 1000 (second precision, last resort) otherwise. bin/brik
# enforces bash 5+ so the fallback should be unreachable in practice.
_helpers.epoch_ms() {
    # EPOCHREALTIME format: "<seconds>.<microseconds>" (always 6 frac digits
    # on bash 5+). Concatenate seconds with the first 3 fraction digits
    # as plain text to avoid arithmetic interpretation of leading zeros
    # (e.g. "012" being read as octal by printf %d). The dot check guards
    # against an externally-set EPOCHREALTIME without the expected shape.
    if [[ "${EPOCHREALTIME:-}" == *.* ]]; then
        local s="${EPOCHREALTIME%.*}"
        local f="${EPOCHREALTIME#*.}000"
        printf '%s%s\n' "$s" "${f:0:3}"
    else
        printf '%s000\n' "$(date +%s)"
    fi
}

# Export the named variable to the first non-empty candidate iff the
# variable is currently unset or empty. Leaves the variable untouched
# (still unset) when no candidate matches, so consumers can distinguish
# absent-from-environment ("omit field") from empty-string.
# Usage: _helpers.set_if_unset <var_name> <candidate1> [<candidate2>...]
_helpers.set_if_unset() {
    local var="$1"; shift
    [[ -n "${!var:-}" ]] && return 0
    local cand
    for cand in "$@"; do
        if [[ -n "$cand" ]]; then
            export "$var=$cand"
            return 0
        fi
    done
    return 0
}

# Detect CI metadata from the runtime environment and export normalized
# BRIK_PIPELINE_*/BRIK_COMMIT_*/BRIK_TRIGGERED_BY variables. Pre-set BRIK_*
# wins, so wrappers can override before detection runs.
#
# Sources by platform:
#   GitLab : CI_PIPELINE_ID, CI_PIPELINE_URL, CI_COMMIT_SHA,
#            CI_COMMIT_SHORT_SHA, CI_COMMIT_REF_NAME, CI_COMMIT_BRANCH,
#            CI_COMMIT_TAG, GITLAB_USER_LOGIN, CI_PIPELINE_SOURCE
#   Jenkins: BUILD_TAG, BUILD_NUMBER, BUILD_URL, GIT_COMMIT,
#            GIT_BRANCH (origin/-stripped), GIT_TAG, BUILD_USER_ID,
#            BUILD_CAUSE
#
# Lives in stage.sh (rather than pipeline.sh) so stage.dispatch can call
# it on every stage entry, covering both pipeline.run (multi-stage) and
# the CI single-job path.
_pipeline.detect_metadata() {
    # TODO: extend with BRIK_PROJECT_NAME from CI_PROJECT_NAME (GitLab) /
    # JOB_NAME (Jenkins). Currently sourced from .project.name in brik.yml
    # only (lib/transverse/config.sh). Tracked under chantier
    # 20260502_pipeline-report-followups Phase B.3 audit.
    _helpers.set_if_unset BRIK_PIPELINE_ID    "${CI_PIPELINE_ID:-}"   "${BUILD_TAG:-}"  "${BUILD_NUMBER:-}"
    _helpers.set_if_unset BRIK_PIPELINE_URL   "${CI_PIPELINE_URL:-}"  "${BUILD_URL:-}"
    _helpers.set_if_unset BRIK_COMMIT_SHA     "${CI_COMMIT_SHA:-}"    "${GIT_COMMIT:-}"

    # short_sha derives from BRIK_COMMIT_SHA when no native short var is set.
    # The set_if_unset call above runs export in the current shell, so
    # BRIK_COMMIT_SHA is already populated here when CI_COMMIT_SHA or
    # GIT_COMMIT was non-empty. Do not reorder these blocks without
    # preserving that read-after-export contract.
    local _short_fallback=""
    [[ -n "${BRIK_COMMIT_SHA:-}" ]] && _short_fallback="${BRIK_COMMIT_SHA:0:8}"
    _helpers.set_if_unset BRIK_COMMIT_SHORT_SHA "${CI_COMMIT_SHORT_SHA:-}" "$_short_fallback"

    _helpers.set_if_unset BRIK_COMMIT_REF     "${CI_COMMIT_REF_NAME:-}"

    # Jenkins GIT_BRANCH commonly carries an "origin/" prefix; strip it for
    # consistency with the GitLab CI_COMMIT_BRANCH form.
    local _branch="${CI_COMMIT_BRANCH:-${GIT_BRANCH:-}}"
    _branch="${_branch#origin/}"
    _helpers.set_if_unset BRIK_COMMIT_BRANCH  "$_branch"

    _helpers.set_if_unset BRIK_COMMIT_TAG     "${CI_COMMIT_TAG:-}"    "${GIT_TAG:-}"   "${BRIK_TAG:-}"
    _helpers.set_if_unset BRIK_TRIGGERED_BY   "${GITLAB_USER_LOGIN:-}" "${BUILD_USER_ID:-}" "${CI_PIPELINE_SOURCE:-}" "${BUILD_CAUSE:-}"

    # Author identity. GitLab provides CI_COMMIT_AUTHOR as "Name <email>" so
    # we split it into the two normalized fields. Jenkins has no equivalent
    # native var; both Jenkins and local fall back to git log against
    # BRIK_WORKSPACE.
    local _gl_author="${CI_COMMIT_AUTHOR:-}"
    local _gl_author_name="" _gl_author_email=""
    if [[ -n "$_gl_author" ]]; then
        # Literal '<' and '>' (no backslash). In bash ERE, '\<' and '\>'
        # are word-boundary anchors on GNU systems and silently break the
        # match. Use [^>]+ for the email so a name containing angle
        # brackets does not swallow the closing '>'.
        local _re='^(.*[^[:space:]])[[:space:]]+<([^>]+)>[[:space:]]*$'
        if [[ "$_gl_author" =~ $_re ]]; then
            _gl_author_name="${BASH_REMATCH[1]}"
            _gl_author_email="${BASH_REMATCH[2]}"
        else
            _gl_author_name="$_gl_author"
        fi
    fi

    local _git_author_name="" _git_author_email="" _git_timestamp="" _git_subject=""
    if command -v git >/dev/null 2>&1; then
        local _ws="${BRIK_WORKSPACE:-.}"
        if git -C "$_ws" rev-parse --git-dir >/dev/null 2>&1; then
            _git_author_name="$(git -C "$_ws" log -1 --format=%an 2>/dev/null || true)"
            _git_author_email="$(git -C "$_ws" log -1 --format=%ae 2>/dev/null || true)"
            _git_timestamp="$(git -C "$_ws" log -1 --format=%aI 2>/dev/null || true)"
            _git_subject="$(git -C "$_ws" log -1 --format=%s 2>/dev/null || true)"
        fi
    fi

    _helpers.set_if_unset BRIK_COMMIT_AUTHOR          "$_gl_author_name"  "$_git_author_name"
    _helpers.set_if_unset BRIK_COMMIT_AUTHOR_EMAIL    "$_gl_author_email" "$_git_author_email"
    _helpers.set_if_unset BRIK_COMMIT_TIMESTAMP       "${CI_COMMIT_TIMESTAMP:-}" "$_git_timestamp"
    _helpers.set_if_unset BRIK_COMMIT_MESSAGE_SUBJECT "${CI_COMMIT_TITLE:-}"     "$_git_subject"

    # Browseable repository URL. Resolution priority: CI_PROJECT_URL (GitLab),
    # GIT_URL (Jenkins Git plugin), then git config remote.origin.url. The raw
    # URL is normalized to HTTPS, credentials stripped, .git suffix dropped.
    local _git_remote_url=""
    if command -v git >/dev/null 2>&1; then
        local _ws_remote="${BRIK_WORKSPACE:-.}"
        if git -C "$_ws_remote" rev-parse --git-dir >/dev/null 2>&1; then
            _git_remote_url="$(git -C "$_ws_remote" config --get remote.origin.url 2>/dev/null || true)"
        fi
    fi
    local _raw_repo_url="${CI_PROJECT_URL:-${GIT_URL:-${_git_remote_url}}}"
    local _normalized_repo_url=""
    if [[ -n "$_raw_repo_url" ]]; then
        _normalized_repo_url="$(_pipeline._normalize_remote_url "$_raw_repo_url")"
    fi
    _helpers.set_if_unset BRIK_COMMIT_REPO_URL "$_normalized_repo_url"

    return 0
}

# Convert an arbitrary git remote URL to a browseable HTTPS form.
# Inputs (raw):
#   git@host:owner/repo.git
#   ssh://git@host/owner/repo.git
#   https://host/owner/repo.git
#   https://user:token@host/owner/repo.git
#   http://host:port/owner/repo.git
# Output: scheme://host[:port]/owner/repo (no credentials, no .git suffix).
# Unknown forms are returned unchanged. Always succeeds.
_pipeline._normalize_remote_url() {
    local url="$1"
    [[ -z "$url" ]] && { printf ''; return 0; }
    local scheme="" host="" path=""

    # SSH short form: git@host:owner/repo[.git]
    if [[ "$url" =~ ^[^@[:space:]]+@([^:/]+):(.+)$ ]]; then
        host="${BASH_REMATCH[1]}"
        path="${BASH_REMATCH[2]}"
        path="${path%.git}"
        printf 'https://%s/%s' "$host" "$path"
        return 0
    fi
    # SSH URL form: ssh://[user@]host/path[.git]
    if [[ "$url" =~ ^ssh://([^@/]+@)?([^/]+)/(.+)$ ]]; then
        host="${BASH_REMATCH[2]}"
        path="${BASH_REMATCH[3]}"
        path="${path%.git}"
        printf 'https://%s/%s' "$host" "$path"
        return 0
    fi
    # HTTPS/HTTP form, optionally with embedded credentials
    if [[ "$url" =~ ^(https?)://(([^@/]+)@)?(.+)$ ]]; then
        scheme="${BASH_REMATCH[1]}"
        path="${BASH_REMATCH[4]}"
        path="${path%.git}"
        path="${path%/}"
        printf '%s://%s' "$scheme" "$path"
        return 0
    fi
    printf '%s' "$url"
}

# Create a log file for a stage. Prints the path on stdout.
stage.create_log_file() {
    local stage_name="$1"
    local log_dir
    log_dir="$(_brik.log_dir._resolve)"
    mkdir -p "$log_dir" || {
        log.error "cannot create log directory: $log_dir"
        return "$BRIK_EXIT_IO_FAILURE"
    }
    local log_file
    log_file="$(mktemp "${log_dir}/${stage_name}-XXXXXX")" || {
        log.error "cannot create log file for stage: $stage_name"
        return "$BRIK_EXIT_IO_FAILURE"
    }
    mv "$log_file" "${log_file}.log" && log_file="${log_file}.log"
    printf '%s' "$log_file"
    return 0
}

# Execute a command while capturing all output to a log file.
# Preserves the command's exit status via PIPESTATUS.
stage.with_logging() {
    local log_file="$1"
    shift
    "$@" 2>&1 | tee -a "$log_file"
    return "${PIPESTATUS[0]}"
}

# Execute the stage logic function with proper scope.
#
# BRIK_STAGE_NAME mirrors BRIK_LOG_SCOPE for the duration of the stage:
# context.sh writes it to the context file (for stages that source the
# context), but consumers that read live env vars (e.g.
# report.render_aggregate_terminal showing the currently-running stage
# as RUNNING in its own table) need it exported. Jenkins' brikStage
# Groovy wrapper already injects this var; exporting here gives GitLab
# and local adapters the same guarantee at zero cost.
stage.execute() {
    local stage_name="$1"
    local logic_function="$2"
    local context_file="$3"
    shift 3

    local previous_scope="${BRIK_LOG_SCOPE:-}"
    local previous_stage_name="${BRIK_STAGE_NAME:-}"
    export BRIK_LOG_SCOPE="$stage_name"
    export BRIK_STAGE_NAME="$stage_name"

    if ! declare -f "$logic_function" >/dev/null 2>&1; then
        log.error "logic function not defined: $logic_function"
        export BRIK_LOG_SCOPE="$previous_scope"
        export BRIK_STAGE_NAME="$previous_stage_name"
        return "$BRIK_EXIT_INVALID_INPUT"
    fi

    local result=0
    "$logic_function" "$context_file" "$@" || result=$?

    export BRIK_LOG_SCOPE="$previous_scope"
    export BRIK_STAGE_NAME="$previous_stage_name"
    return "$result"
}

# Cleanup after stage execution.
# Per SC17: the per-stage context file is scratch state used to pass values
# between hooks; once summary.build has consumed it (always invoked before
# stage.cleanup), it must be deleted so brik-artifacts/ contains only the
# canonical summary fragment per stage. Leaving context-*-XXXXXX behind
# would force downstream consumers (E2E harness, CI artifact aggregators)
# to guess which file carries the source of truth.
stage.cleanup() {
    local context_file="$1"
    local log_file="$2"
    # best-effort: cleanup hook must not abort the stage
    hook.on_cleanup "${BRIK_LOG_SCOPE:-brik}" "$context_file" "$log_file" || true
    if [[ -n "$context_file" && -f "$context_file" ]]; then
        rm -f "$context_file" || true
    fi
    log.debug "stage cleanup complete"
    return 0
}

# Record the stage's terminal tech.* fields into the aggregate-report backend
# and emit the per-stage fragment for CI artifact aggregation. Idempotent
# when called repeatedly (report.record upserts).
#
# Behavior:
#   - No-op when the backend aggregate-report.json is absent (legacy callers
#     that bypass pipeline.run / stage.dispatch).
#   - Records tech.duration_ms, tech.exit_code, and tech.status (when not
#     already set by the stage itself, e.g. config-skip pattern).
#   - Calls report.write_fragment unless BRIK_DISABLE_REPORT_FRAGMENTS=1.
#   - Fragment write failures are non-fatal (log.warn) and never override
#     the stage exit code.
#
# Usage: _stage._finalize_fragment <stage_name> <exit_code> <stage_start_ms>
_stage._finalize_fragment() {
    local stage_name="$1"
    local exit_code="$2"
    local stage_start_ms="$3"

    local log_dir
    log_dir="$(_brik.log_dir._resolve)"
    local backend="${log_dir}/aggregate-report.json"
    [[ -f "$backend" ]] || return 0

    local stage_end_ms duration_ms
    stage_end_ms="$(_helpers.epoch_ms)"
    duration_ms=$(( stage_end_ms - stage_start_ms ))

    report.record "$stage_name" "tech" "duration_ms" "$duration_ms" 2>/dev/null || true
    report.record "$stage_name" "tech" "exit_code" "$exit_code" 2>/dev/null || true
    if ! report.has_status "$stage_name"; then
        if [[ "$exit_code" -eq 0 ]]; then
            report.record "$stage_name" "tech" "status" "success" 2>/dev/null || true
        else
            report.record "$stage_name" "tech" "status" "failed" 2>/dev/null || true
        fi
    fi

    # Per-stage dry-run marker. Stamps tech.dry_run=true on stages declared
    # as destructive in their manifest (spec.dry_run.destructive: true).
    # The list comes from the registry (D.3 of the architecture refactor
    # chantier); centralising the stamp here means renderers can rely on
    # the field being present for every impacted stage without each stage
    # having to remember to record it. report.record is an upsert so a
    # stage that records the field itself stays back-compat.
    if [[ "${BRIK_DRY_RUN:-}" == "true" ]] \
       && declare -f registry.stage.is_destructive >/dev/null 2>&1 \
       && registry.stage.is_destructive "$stage_name" 2>/dev/null; then
        report.record "$stage_name" "tech" "dry_run" "true" 2>/dev/null || true
    fi

    _stage._record_business "$stage_name" "$backend" || true

    [[ "${BRIK_DISABLE_REPORT_FRAGMENTS:-}" == "1" ]] && return 0
    # Capture stderr so the underlying jq/mkdir/mv error surfaces in the
    # build log. Silent swallowing here previously hid real bugs (notably
    # Jenkins parallel-verify producing fragments that never made it into
    # the aggregate report).
    local _wf_err
    _wf_err="$(report.write_fragment "$stage_name" 2>&1 1>/dev/null)" && _wf_err=""
    if [[ -n "$_wf_err" ]]; then
        log.warn "fragment write failed for stage ${stage_name} (non-fatal): ${_wf_err//$'\n'/ | }"
    fi
    return 0
}

# Compute and persist business.{status, reason} for the stage by feeding
# its tech.status, tech.kind, the resolved pipeline context, and the
# side-band findings.ignored.total signal into business.evaluate. Reads
# everything from the backend so a stage running standalone (CI single-job
# path) and a stage running under pipeline.run share the same logic.
#
# Best-effort: silent on missing jq, on a malformed business.evaluate
# payload, or on a missing tech.status. The caller already wraps this in
# `|| true`.
_stage._record_business() {
    local stage_name="$1"
    local backend="$2"

    command -v jq >/dev/null 2>&1 || return 0
    [[ -f "$backend" ]] || return 0

    local tech_status tech_kind findings_ignored
    tech_status="$(jq -r --arg s "$stage_name" \
        '.stages[]? | select(.name == $s) | .tech.status // empty' \
        "$backend" 2>/dev/null)" || tech_status=""
    [[ -n "$tech_status" ]] || return 0

    tech_kind="$(jq -r --arg s "$stage_name" \
        '.stages[]? | select(.name == $s) | .tech.kind // empty' \
        "$backend" 2>/dev/null)" || tech_kind=""

    findings_ignored="$(jq -r --arg s "$stage_name" \
        '.stages[]? | select(.name == $s) | .business.findings.ignored.total // 0' \
        "$backend" 2>/dev/null)" || findings_ignored="0"
    [[ "$findings_ignored" =~ ^[0-9]+$ ]] || findings_ignored="0"

    local failing_has_fix failing_no_fix failing_total failing_unknown
    failing_has_fix="$(jq -r --arg s "$stage_name" \
        '.stages[]? | select(.name == $s) | ((.business.findings.failing | objects | .has_fix) // 0)' \
        "$backend" 2>/dev/null)" || failing_has_fix="0"
    [[ "$failing_has_fix" =~ ^[0-9]+$ ]] || failing_has_fix="0"
    failing_no_fix="$(jq -r --arg s "$stage_name" \
        '.stages[]? | select(.name == $s) | ((.business.findings.failing | objects | .no_fix) // 0)' \
        "$backend" 2>/dev/null)" || failing_no_fix="0"
    [[ "$failing_no_fix" =~ ^[0-9]+$ ]] || failing_no_fix="0"
    failing_total="$(jq -r --arg s "$stage_name" \
        '.stages[]? | select(.name == $s) | ((.business.findings.failing | objects | .total) // (.business.findings.failing | numbers) // 0)' \
        "$backend" 2>/dev/null)" || failing_total="0"
    [[ "$failing_total" =~ ^[0-9]+$ ]] || failing_total="0"
    # Conservative default: any failing finding not annotated has_fix or
    # no_fix is unknown, which business.evaluate treats as has_fix (BLOCK
    # in release context).
    failing_unknown=$(( failing_total - failing_has_fix - failing_no_fix ))
    (( failing_unknown < 0 )) && failing_unknown=0

    local context="snapshot"
    [[ -n "${BRIK_COMMIT_TAG:-}" ]] && context="release"

    local payload status reason
    payload="$(business.evaluate \
        --tech-status "$tech_status" \
        --context "$context" \
        --findings-ignored "$findings_ignored" \
        --findings-failing-has-fix "$failing_has_fix" \
        --findings-failing-no-fix  "$failing_no_fix" \
        --findings-failing-unknown "$failing_unknown" \
        --tech-kind "$tech_kind" 2>/dev/null)" || return 0
    [[ -n "$payload" ]] || return 0

    status="$(jq -r '.status // empty' <<<"$payload" 2>/dev/null)" || status=""
    reason="$(jq -r '.reason // ""' <<<"$payload" 2>/dev/null)" || reason=""
    [[ -n "$status" ]] || return 0

    report.record "$stage_name" "business" "status" "$status" 2>/dev/null || true
    report.record "$stage_name" "business" "reason" "$reason" 2>/dev/null || true
    return 0
}

# Project the env section of a stage's report entry into BRIK_PIPELINE_ENV
# so downstream stages see the variables when they call pipeline.env.load.
# Silently no-op when the report backend or jq is absent, when the stage has
# no env section, or when no env keys were recorded for that stage.
#
# Values are read via NUL-separated jq output and forwarded to
# _pipeline.env.append, which uses printf '%s=%q\n' so newlines, tabs,
# quotes and equal signs round-trip through pipeline.env.load.
_stage.run._project_env() {
    local stage_name="$1"
    [[ -n "$stage_name" ]] || return 0

    command -v jq >/dev/null 2>&1 || return 0

    local log_dir
    log_dir="$(_brik.log_dir._resolve)"
    local backend="${log_dir}/aggregate-report.json"
    [[ -f "$backend" ]] || return 0

    if [[ -z "${BRIK_PIPELINE_ENV:-}" ]]; then
        pipeline.env.init >/dev/null 2>&1 || return 0
    fi

    local key value
    while IFS= read -r -d '' key && IFS= read -r -d '' value; do
        [[ -z "$key" ]] && continue
        _pipeline.env.append "$key" "$value" 2>/dev/null || true
    done < <(jq -j --arg s "$stage_name" \
        '.stages[]? | select(.name == $s) | (.env // {}) | to_entries[]
         | "\(.key)\u0000\(.value)\u0000"' \
        "$backend" 2>/dev/null)

    return 0
}

# Main entry point for stage execution.
# Usage: stage.run <stage_name> <logic_function> [args...]
stage.run() {
    local stage_name="$1"
    local logic_function="$2"
    shift 2
    local -a args=("$@")

    local context_file=""
    local log_file=""
    local exit_code=0
    local stage_start_ms
    stage_start_ms="$(_helpers.epoch_ms)"

    banner.stage "$stage_name" "${BRIK_RUNNER_IMAGE:-}"
    log.info "starting stage: $stage_name"

    # Create execution context
    context_file="$(context.create "$stage_name")" || return "$BRIK_EXIT_INVALID_ENV"
    # context_file now exists; the early-return paths below must remove it
    # so the SC17 contract (no context-<stage>-XXXXXX left behind) holds on
    # every exit path, not just the ones that reach stage.cleanup.
    log_file="$(stage.create_log_file "$stage_name")" || {
        rm -f "$context_file"
        return "$BRIK_EXIT_IO_FAILURE"
    }
    _context._set "$context_file" "BRIK_LOG_FILE" "$log_file" || {
        rm -f "$context_file"
        return "$BRIK_EXIT_IO_FAILURE"
    }

    # Pre-stage hook (can abort)
    hook.pre_stage "$stage_name" "$context_file" "$log_file" || {
        exit_code=$?
        log.warn "pre-stage hook failed with code $exit_code, aborting stage"
        # best-effort: finalization must not mask the pre-stage hook error
        summary.build "$stage_name" "$context_file" "$log_file" "$exit_code" || true
        _stage._finalize_fragment "$stage_name" "$exit_code" "$stage_start_ms" || true
        _stage.run._project_env "$stage_name" || true
        stage.cleanup "$context_file" "$log_file" || true
        return "$exit_code"
    }

    # Execute stage logic with logging
    stage.with_logging "$log_file" \
        stage.execute "$stage_name" "$logic_function" "$context_file" "${args[@]}"
    exit_code=$?

    # best-effort: finalization below must not override the stage exit code
    _context._set "$context_file" "BRIK_FINISHED_AT" "$(date +"%Y-%m-%dT%H:%M:%S%z")" || true

    if [[ $exit_code -eq 0 ]]; then
        # Check if the stage recorded a "skipped" status in the pipeline
        # report (config-skip pattern, e.g. quality.lint.enabled=false).
        # Falls back silently to "completed successfully" if the report is
        # absent or jq is unavailable (stage run standalone outside pipeline).
        local _report_path _stage_status=""
        _report_path="$(_brik.log_dir._resolve)/aggregate-report.json"
        if [[ -f "$_report_path" ]] && command -v jq >/dev/null 2>&1; then
            _stage_status="$(jq -r --arg s "$stage_name" \
                '.stages[] | select(.name == $s) | .tech.status // empty' \
                "$_report_path" 2>/dev/null)" || _stage_status=""
        fi
        case "$_stage_status" in
            disabled)
                log.info "stage $stage_name skipped (disabled)"
                ;;
            not-applicable)
                log.info "stage $stage_name skipped (not configured)"
                ;;
            skipped)
                log.info "stage $stage_name skipped (no config detected)"
                ;;
            *)
                log.success "stage $stage_name completed successfully"
                ;;
        esac
        hook.on_success "$stage_name" "$context_file" "$log_file" || true
    else
        log.error "stage $stage_name failed with exit code $exit_code"
        hook.on_failure "$stage_name" "$context_file" "$log_file" "$exit_code" || true
    fi

    hook.post_stage "$stage_name" "$context_file" "$log_file" "$exit_code" || true

    summary.build "$stage_name" "$context_file" "$log_file" "$exit_code" || true
    _stage._finalize_fragment "$stage_name" "$exit_code" "$stage_start_ms" || true
    _stage.run._project_env "$stage_name" || true
    stage.cleanup "$context_file" "$log_file" || true

    return "$exit_code"
}

# Map a stage name (kebab-case) to its business-logic function (stages.<snake>),
# show the Brik banner once before the first stage, load cross-stage pipeline
# env, and dispatch to stage.run. This is the business-logic dispatcher shared
# by the lib-level pipeline.run orchestrator and the wrapper-level
# brik.wrapper.run_stage entry point.
#
# Precondition: wrapper setup has exported BRIK_WORKSPACE and BRIK_CONFIG_FILE.
# Backward-compat aliases quality->lint and security->scan are deprecated.
# Usage: stage.dispatch <stage_name>
# Returns: stage.run exit code, or BRIK_EXIT_INVALID_INPUT for empty/unknown stage.
stage.dispatch() {
    local stage_name="$1"

    if [[ -z "$stage_name" ]]; then
        log.error "stage name is required"
        return "$BRIK_EXIT_INVALID_INPUT"
    fi

    # Normalize CI metadata (BRIK_PIPELINE_*/BRIK_COMMIT_*/BRIK_TRIGGERED_BY)
    # before any stage logic runs so report.aggregate_fragments and any other
    # consumer reads from a single, populated source. Idempotent (pre-set
    # BRIK_* wins) so repeated dispatches in the same shell are safe.
    _pipeline.detect_metadata

    # Show the Brik logo once, before the first stage.
    if [[ "$stage_name" == "init" ]]; then
        banner.brik "${BRIK_VERSION:-}"
    fi

    # Load cross-stage variables from previous stages.
    pipeline.env.load

    # Ensure the pipeline report exists so stages can report.record. When
    # invoked via pipeline.run, report.init was already called; in the
    # single-stage path (brik.wrapper.run_stage) we lazily initialize here.
    local _report_path
    _report_path="$(_brik.log_dir._resolve)/aggregate-report.json"
    [[ -f "$_report_path" ]] || report.init >/dev/null 2>&1 || true

    # Resolve <stage_name> -> <logic_function> via the registry (D.3 of the
    # architecture refactor chantier). The registry is the source of truth
    # for stage IDs, aliases (e.g. quality -> lint, security -> scan), and
    # their Bash logic function name. Adding a builtin stage means publishing
    # a manifest + module, no change here.
    local logic_function=""
    if declare -f registry.stage.function >/dev/null 2>&1; then
        logic_function="$(registry.stage.function "$stage_name" 2>/dev/null || true)"
    fi
    if [[ -z "$logic_function" ]]; then
        log.error "unknown stage: $stage_name"
        if declare -f registry.stage.list >/dev/null 2>&1; then
            local _known
            _known="$(registry.stage.list 2>/dev/null | paste -sd, -)"
            [[ -n "$_known" ]] && log.error "valid stages: $_known"
        fi
        return "$BRIK_EXIT_INVALID_INPUT"
    fi

    # The manifest may reference a logic function not yet provided by any
    # loaded module (e.g. a builtin stage shipped without a body, or a
    # third-party stage whose module hasn't been brik.use'd yet). Surface
    # this as a clear error instead of letting stage.run fail opaquely.
    if ! declare -f "$logic_function" >/dev/null 2>&1; then
        brik.use "stages.${stage_name//-/_}" 2>/dev/null || true
    fi
    if ! declare -f "$logic_function" >/dev/null 2>&1; then
        log.error "logic function not defined for stage $stage_name: $logic_function"
        return "$BRIK_EXIT_CONFIG_ERROR"
    fi

    stage.run "$stage_name" "$logic_function" "${BRIK_WORKSPACE}" "${BRIK_CONFIG_FILE}"
}
