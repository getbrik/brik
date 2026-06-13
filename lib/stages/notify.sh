#!/usr/bin/env bash
# @module stages/notify
# @description Notify stage - pipeline summary and notifications (Slack, email, webhook).

# Guard against double-sourcing.
[[ -n "${_BRIK_STAGES_NOTIFY_LOADED:-}" ]] && return 0
_BRIK_STAGES_NOTIFY_LOADED=1

# -----------------------------------------------------------------------------
# Private helpers
# -----------------------------------------------------------------------------

# (Historical: _notify._emit_recap_table rendered a Unicode summary
# table on stderr alongside the markdown report on stdout. Removed
# 2026-05-23: the Business + Metrics columns it surfaced were folded
# into the markdown Stages table -- see _report._render_aggregate_md
# in lib/pipeline/report.sh -- so the recap was duplicating
# information that glow now renders inline.)

# Detect "CI aggregation mode" by looking for at least one valid fragment
# file in <dir>. Per-stage fragments produced by report.write_fragment in
# upstream stages have a stable signature (.stage + .schema_version).
# aggregate-report.json (the aggregate target) is filtered out by basename so
# a previous run does not re-trigger aggregation in local mode.
#
# Usage: _notify._is_ci_aggregation_mode <dir>
# Returns: 0 if at least one fragment with the signature is present,
#          1 otherwise (including missing or empty directory).
_notify._is_ci_aggregation_mode() {
    local dir="$1"
    [[ -d "$dir" ]] || return 1
    command -v jq >/dev/null 2>&1 || return 1

    shopt -s nullglob
    local f base
    for f in "$dir"/*/*.json; do
        base="$(basename "$f")"
        [[ "$base" == "aggregate-report.json" ]] && continue
        if jq -e 'type == "object" and has("stage") and has("schema_version")' \
                "$f" >/dev/null 2>&1; then
            shopt -u nullglob
            return 0
        fi
    done
    shopt -u nullglob
    return 1
}

# Build the pipeline.notify metadata blob from the live env vars and the
# pipeline business outcome. Surfaces channel configuration intent, the
# BRIK_NOTIFY_*_ON policy each channel uses, and a `would_send` flag
# computed against the pipeline_status derived from business_status. The
# blob captures intent (not delivery confirmation): a `true` would_send
# means stages.notify will attempt the send, regardless of any later
# network or transport failure.
#
# Usage: _notify._build_notify_metadata <business_status>
# business_status: success|warning|error (from .pipeline.business.status)
# Emits: JSON {channels:[...], gatekeeper:{...}} on stdout.
_notify._build_notify_metadata() {
    local business_status="$1"
    local pipeline_status="success"
    [[ "$business_status" == "error" ]] && pipeline_status="failed"

    local slack_chan="${BRIK_NOTIFY_SLACK_CHANNEL:-}"
    local slack_on="${BRIK_NOTIFY_SLACK_ON:-always}"
    local slack_configured=false slack_would=false
    if [[ -n "$slack_chan" ]]; then
        slack_configured=true
        _notify._should_send "$slack_on" "$pipeline_status" && slack_would=true
    fi

    local email_to="${BRIK_NOTIFY_EMAIL_TO:-}"
    local email_on="${BRIK_NOTIFY_EMAIL_ON:-always}"
    local email_configured=false email_would=false
    if [[ -n "$email_to" ]]; then
        email_configured=true
        _notify._should_send "$email_on" "$pipeline_status" && email_would=true
    fi

    local webhook_url="${BRIK_NOTIFY_WEBHOOK_URL:-}"
    # A declared webhook Notification endpoint configures the channel even
    # without the legacy variable (the send path resolves it the same way).
    if [[ -z "$webhook_url" ]]; then
        webhook_url="$(_notify._webhook_endpoint 2>/dev/null | jq -r '.url // empty' 2>/dev/null)"
    fi
    local webhook_on="${BRIK_NOTIFY_WEBHOOK_ON:-always}"
    local webhook_configured=false webhook_would=false
    if [[ -n "$webhook_url" ]]; then
        webhook_configured=true
        _notify._should_send "$webhook_on" "$pipeline_status" && webhook_would=true
    fi

    local decision="pass"
    [[ "$business_status" == "error" ]] && decision="fail"

    # KCOV_EXCL_START -- jq metadata body is not bash code
    jq -c -n \
        --arg slack_on "$slack_on" --argjson slack_cfg "$slack_configured" --argjson slack_send "$slack_would" \
        --arg email_on "$email_on" --argjson email_cfg "$email_configured" --argjson email_send "$email_would" \
        --arg webhook_on "$webhook_on" --argjson webhook_cfg "$webhook_configured" --argjson webhook_send "$webhook_would" \
        --arg decision "$decision" --arg bstatus "$business_status" '
        {
            channels: [
                {type:"slack",   configured:$slack_cfg,   on:$slack_on,   would_send:$slack_send},
                {type:"email",   configured:$email_cfg,   on:$email_on,   would_send:$email_send},
                {type:"webhook", configured:$webhook_cfg, on:$webhook_on, would_send:$webhook_send}
            ],
            gatekeeper: {decision:$decision, business_status:$bstatus}
        }'
    # KCOV_EXCL_STOP
}

# Patch aggregate-report.json with .pipeline.notify = <metadata blob> and
# re-render the HTML view so the notify panel reflects the dispatch
# decision. Best-effort: a missing report, missing jq, or any I/O failure
# logs a non-fatal warning and leaves the on-disk artefacts intact.
# Returns 0 in every recoverable case so notify's gatekeeper exit stays
# the single source of truth for stage success.
#
# Usage: _notify._inject_notify_metadata <aggregate_json> <business_status>
_notify._inject_notify_metadata() {
    local report="$1"
    local business_status="$2"
    [[ -f "$report" ]] || return 0
    command -v jq >/dev/null 2>&1 || return 0

    local meta
    meta="$(_notify._build_notify_metadata "$business_status")" || {
        log.warn "could not build notify metadata (non-fatal)"
        return 0
    }

    local tmp
    tmp="$(mktemp)" || return 0
    if jq -c --argjson meta "$meta" '.pipeline.notify = $meta' "$report" > "$tmp" 2>/dev/null; then
        mv "$tmp" "$report" || {
            rm -f "$tmp"
            log.warn "could not write patched aggregate-report.json (non-fatal)"
            return 0
        }
    else
        rm -f "$tmp"
        log.warn "could not patch aggregate-report.json with notify metadata (non-fatal)"
        return 0
    fi

    # Re-render the HTML so the notify panel reflects the patched JSON.
    # _report._render_html is sourced via report.sh; declare -f guards
    # against test contexts that source notify.sh in isolation.
    local html="${report%.json}.html"
    if declare -f _report._render_html >/dev/null 2>&1; then
        _report._render_html "$report" > "$html" 2>/dev/null || \
            log.warn "could not re-render aggregate-report.html after notify injection (non-fatal)"
    fi

    return 0
}

# Check if a notification should be sent based on the 'on' condition and
# pipeline status.
# Usage: _notify._should_send <on_condition> <pipeline_status>
# on_condition: "always", "failure", "success" (or comma-separated list)
_notify._should_send() {
    local on_condition="$1"
    local pipeline_status="$2"

    [[ "$on_condition" == "always" ]] && return 0
    [[ "$on_condition" == *"$pipeline_status"* ]] && return 0
    [[ "$on_condition" == *"failure"* && "$pipeline_status" == "failed" ]] && return 0

    return "$BRIK_EXIT_FAILURE"
}

# _notify._webhook_endpoint - echo (as JSON) the referential's Notification
# endpoint of service webhook, or nothing when none is declared (the
# BRIK_NOTIFY_WEBHOOK_URL variable remains the legacy path). Slack and email
# stay variable-delivered: a Slack incoming-webhook URL embeds its token, and
# the referential holds references, never secret values. Fail-closed when
# several webhook endpoints are declared.
_notify._webhook_endpoint() {
    brik.use transverse.infra 2>/dev/null || true
    declare -f infra.root >/dev/null 2>&1 || return 0
    # No referential configured -> legacy BRIK_NOTIFY_WEBHOOK_URL path (silent).
    [[ -n "${BRIK_INFRA_DIR:-}" || -n "${BRIK_INFRA_REPO:-}" ]] || return 0

    local root
    if ! root="$(infra.root 2>/dev/null)"; then
        # Configured but unreadable: warn rather than skip in silence, so a
        # mistyped BRIK_INFRA_DIR does not quietly drop webhook delivery.
        log.warn "notify: a referential is configured but could not be read -- skipping webhook endpoint discovery"
        return 0
    fi

    local file found=""
    for file in "${root}/endpoints"/*.yml "${root}/endpoints"/*.yaml; do
        [[ -f "$file" ]] || continue
        [[ "$(yq '.kind // ""' "$file")" == "Notification" ]] || continue
        [[ "$(yq '.service // ""' "$file")" == "webhook" ]] || continue
        if [[ -n "$found" ]]; then
            log.error "multiple webhook Notification endpoints declared in the referential (expected at most one)"
            return "$BRIK_EXIT_CONFIG_ERROR"
        fi
        found="$file"
    done
    [[ -z "$found" ]] && return 0
    yq -o json '.' "$found"
}

# Send a Slack notification via Incoming Webhook.
# Usage: notify.slack --message <text> [--webhook-var <VAR>] [--channel <channel>]
#        [--level <info|warn|error>] [--dry-run]
notify.slack() {
    local message="" webhook_var="${BRIK_NOTIFY_SLACK_WEBHOOK_VAR:-SLACK_WEBHOOK_URL}"
    local channel="${BRIK_NOTIFY_SLACK_CHANNEL:-}" level="info" dry_run="${BRIK_DRY_RUN:-}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --message) message="$2"; shift 2 ;;
            --webhook-var) webhook_var="$2"; shift 2 ;;
            --channel) channel="$2"; shift 2 ;;
            --level) level="$2"; shift 2 ;;
            --dry-run) dry_run="true"; shift ;;
            *) log.error "unknown option: $1"; return "$BRIK_EXIT_INVALID_INPUT" ;;
        esac
    done

    if [[ -z "$message" ]]; then
        log.error "message is required for Slack notification"
        return "$BRIK_EXIT_INVALID_INPUT"
    fi

    brik.use transverse.env
    local webhook_url
    webhook_url="$(transverse.env.resolve_indirect "$webhook_var")"
    if [[ -z "$webhook_url" ]]; then
        log.warn "Slack webhook variable '$webhook_var' is not set, skipping"
        return 0
    fi

    # Map level to Slack color.
    local color
    case "$level" in
        info)  color="#36a64f" ;;  # green
        warn)  color="#daa520" ;;  # gold
        error) color="#cc0000" ;;  # red
        *)     color="#36a64f" ;;
    esac

    # Build JSON payload (escape message to prevent injection).
    local safe_message="${message//\\/\\\\}"
    safe_message="${safe_message//\"/\\\"}"
    local payload
    payload="{\"attachments\":[{\"color\":\"${color}\",\"text\":\"${safe_message}\""
    [[ -n "$channel" ]] && payload+=",\"channel\":\"${channel}\""
    payload+="}]}"

    if [[ "$dry_run" == "true" ]]; then
        log.info "[dry-run] slack notification: $message"
        return 0
    fi

    pipeline.require_tool curl || return "$BRIK_EXIT_MISSING_DEP"

    curl --silent --max-time 10 --connect-timeout 5 \
        -H "Content-Type: application/json" \
        -d "$payload" \
        "$webhook_url" >/dev/null || {
        log.error "slack notification failed"
        return "$BRIK_EXIT_EXTERNAL_FAIL"
    }

    log.info "slack notification sent"
    return 0
}

# Send an email notification.
# Usage: notify.email --body <text> [--to <address>] [--subject <text>]
#        [--level <info|warn|error>] [--dry-run]
notify.email() {
    local body="" to="${BRIK_NOTIFY_EMAIL_TO:-}" subject="Brik Pipeline Notification"
    local level="info" dry_run="${BRIK_DRY_RUN:-}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --body) body="$2"; shift 2 ;;
            --to) to="$2"; shift 2 ;;
            --subject) subject="$2"; shift 2 ;;
            --level) level="$2"; shift 2 ;;
            --dry-run) dry_run="true"; shift ;;
            *) log.error "unknown option: $1"; return "$BRIK_EXIT_INVALID_INPUT" ;;
        esac
    done

    if [[ -z "$body" ]]; then
        log.error "email body is required"
        return "$BRIK_EXIT_INVALID_INPUT"
    fi

    if [[ -z "$to" ]]; then
        log.warn "no email recipient configured, skipping"
        return 0
    fi

    if [[ "$dry_run" == "true" ]]; then
        log.info "[dry-run] email to $to: $subject"
        return 0
    fi

    # Try sendmail, then mail, then log a warning.
    if command -v sendmail >/dev/null 2>&1; then
        printf 'Subject: %s\nTo: %s\n\n%s\n' "$subject" "$to" "$body" | sendmail "$to" || {
            log.error "sendmail failed"
            return "$BRIK_EXIT_EXTERNAL_FAIL"
        }
    elif command -v mail >/dev/null 2>&1; then
        printf '%s\n' "$body" | mail -s "$subject" "$to" || {
            log.error "mail command failed"
            return "$BRIK_EXIT_EXTERNAL_FAIL"
        }
    else
        log.warn "no mail tool available (sendmail or mail), skipping email notification"
        return 0
    fi

    log.info "email notification sent to $to"
    return 0
}

# notify.webhook_configured - succeed when a webhook destination exists
# (variable or declared Notification endpoint). Lets verb-side callers skip
# silently instead of warning on every run without a webhook.
notify.webhook_configured() {
    [[ -n "${BRIK_NOTIFY_WEBHOOK_URL:-}" ]] && return 0
    [[ -n "$(_notify._webhook_endpoint 2>/dev/null | jq -r '.url // empty' 2>/dev/null)" ]]
}

# Send a webhook notification via HTTP POST.
# Usage: notify.webhook --message <text> | --payload <json>
#        [--url-var <VAR>] [--url <URL>] [--dry-run]
# Reads default URL from BRIK_NOTIFY_WEBHOOK_URL or the variable named by --url-var.
# --payload posts the given JSON document verbatim (the structured CD
# notifications: deploy outcome, promotion, authorization) instead of the
# text envelope; destination and transport posture resolve identically.
notify.webhook() {
    local message="" payload="" url_var="" dry_run="${BRIK_DRY_RUN:-}"
    local url="${BRIK_NOTIFY_WEBHOOK_URL:-}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --message) message="$2"; shift 2 ;;
            --payload) payload="$2"; shift 2 ;;
            --url-var) url_var="$2"; shift 2 ;;
            --url) url="$2"; shift 2 ;;
            --dry-run) dry_run="true"; shift ;;
            *) log.error "unknown option: $1"; return "$BRIK_EXIT_INVALID_INPUT" ;;
        esac
    done

    if [[ -z "$message" && -z "$payload" ]]; then
        log.error "webhook message or payload is required"
        return "$BRIK_EXIT_INVALID_INPUT"
    fi
    if [[ -n "$payload" ]] && ! printf '%s' "$payload" | jq -e . >/dev/null 2>&1; then
        log.error "webhook payload is not valid JSON"
        return "$BRIK_EXIT_INVALID_INPUT"
    fi

    # Resolve URL from variable if specified.
    if [[ -n "$url_var" ]]; then
        brik.use transverse.env
        url="$(transverse.env.resolve_indirect "$url_var")"
    fi

    # Referential absorption: a declared webhook Notification endpoint is the
    # single source of truth for the destination and its transport posture; a
    # variable pointing somewhere else is a contradiction, not an override.
    local -a transport=()
    local _ep
    _ep="$(_notify._webhook_endpoint)" || return "$?"
    if [[ -n "$_ep" ]]; then
        local _ep_url _ep_trust
        _ep_url="$(printf '%s' "$_ep" | jq -r '.url')"
        if [[ -n "$url" && "$url" != "$_ep_url" ]]; then
            log.error "webhook URL '${url}' contradicts the referential's Notification endpoint '${_ep_url}' -- failing closed"
            return "$BRIK_EXIT_CONFIG_ERROR"
        fi
        url="$_ep_url"
        _ep_trust="$(printf '%s' "$_ep" | jq -r '.tls.trust // "system"')"
        if [[ "$url" == http://* ]]; then
            log.warn "webhook endpoint is declared over plain http (legal but insecure)"
        elif [[ "$_ep_trust" == "insecure" ]]; then
            log.warn "webhook endpoint is declared with tls.trust: insecure (legal but insecure)"
            transport+=(--insecure)
        elif [[ "$_ep_trust" == "custom-ca" ]]; then
            local _ep_ca
            _ep_ca="$(infra.tls_ca "$_ep")" || return "$?"
            transport+=(--cacert "$_ep_ca")
        fi
    fi

    if [[ -z "$url" ]]; then
        log.warn "no webhook URL configured, skipping"
        return 0
    fi

    if [[ -z "$payload" ]]; then
        # Escape message to prevent JSON injection.
        local safe_message="${message//\\/\\\\}"
        safe_message="${safe_message//\"/\\\"}"
        payload="{\"text\":\"${safe_message}\",\"project\":\"${BRIK_PROJECT_NAME:-unknown}\",\"platform\":\"${BRIK_PLATFORM:-unknown}\"}"
    fi

    if [[ "$dry_run" == "true" ]]; then
        log.info "[dry-run] webhook POST to $url"
        return 0
    fi

    pipeline.require_tool curl || return "$BRIK_EXIT_MISSING_DEP"

    local _curl_rc=0
    curl --silent --max-time 10 --connect-timeout 5 \
        ${transport[@]+"${transport[@]}"} \
        -H "Content-Type: application/json" \
        -d "$payload" \
        "$url" >/dev/null || _curl_rc=$?
    if [[ "$_curl_rc" -ne 0 ]]; then
        # The curl exit code names the failure mode (6 dns, 7 refused,
        # 28 timeout, 60 tls) -- without it a dead webhook is undebuggable.
        log.error "webhook notification failed (curl rc=${_curl_rc})"
        return "$BRIK_EXIT_EXTERNAL_FAIL"
    fi

    log.info "webhook notification sent"
    return 0
}

# -----------------------------------------------------------------------------
# Public: notify.send dispatcher (kept as convenience for hooks / external callers).
# -----------------------------------------------------------------------------

# Send a notification via the specified channel.
# Usage: notify.send --channel <slack|email|webhook> --message <text>
#        [--level <info|warn|error>] [--dry-run]
notify.send() {
    local channel="" message="" level="info" dry_run="${BRIK_DRY_RUN:-}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --channel) channel="$2"; shift 2 ;;
            --message) message="$2"; shift 2 ;;
            --level) level="$2"; shift 2 ;;
            --dry-run) dry_run="true"; shift ;;
            *) log.error "unknown option: $1"; return "$BRIK_EXIT_INVALID_INPUT" ;;
        esac
    done

    if [[ -z "$channel" ]]; then
        log.error "notification channel is required (--channel)"
        return "$BRIK_EXIT_INVALID_INPUT"
    fi

    if [[ -z "$message" ]]; then
        log.error "notification message is required (--message)"
        return "$BRIK_EXIT_INVALID_INPUT"
    fi

    case "$channel" in
        slack)   notify.slack --message "$message" --level "$level" ${dry_run:+--dry-run} ;;
        email)   notify.email --body "$message" --level "$level" ${dry_run:+--dry-run} ;;
        webhook) notify.webhook --message "$message" ${dry_run:+--dry-run} ;;
        *)
            log.error "unsupported notification channel: $channel"
            return "$BRIK_EXIT_CONFIG_ERROR"
            ;;
    esac
    return $?
}

# -----------------------------------------------------------------------------
# stages.notify - print pipeline summary and send notifications.
# -----------------------------------------------------------------------------

# Usage: stages.notify <context_file>
stages.notify() {
    # context_file positionally passed by stage.run; unused here after §4.2
    # step 7 (dead BRIK_PIPELINE_STATUS read replaced by aggregate-report.json
    # query).
    # shellcheck disable=SC2034
    local context_file="$1"

    config.export_notify_vars

    log.info "notify stage - pipeline summary"

    local project_name
    project_name="$(config.get '.project.name' 'unnamed')"

    local _log_dir
    _log_dir="$(_brik.log_dir._resolve)"
    local _report_md="${_log_dir}/aggregate-report.md"
    local _report_json="${_log_dir}/aggregate-report.json"

    # CI mode: per-stage fragments shipped via job artifacts must be merged
    # before the rest of stages.notify runs (cat, status derivation,
    # workspace copy). report.aggregate_fragments writes the aggregated
    # aggregate-report.{md,json} into BRIK_LOG_DIR. In local mode (no
    # fragments to merge) this branch is a no-op and the existing
    # pipeline.run-produced report is preserved.
    local _ci_fragments_dir="${BRIK_WORKSPACE:-}/brik-artifacts"
    if [[ -n "${BRIK_WORKSPACE:-}" ]] && \
       _notify._is_ci_aggregation_mode "$_ci_fragments_dir"; then
        # Write notify's own fragment BEFORE aggregating (I10 of the
        # chantier 20260526). Without this, the aggregator sees no notify
        # fragment and the render falls back to "RUNNING" (because notify
        # is the in-flight stage at render time) -- producing the orphan
        # row observed on GitLab pipeline #3715 and the entirely-missing
        # notify row on Jenkins. tech.kind=in-flight marks this as "stage
        # is still running its own body but has reached a stable success
        # contract"; the post-stage _finalize_fragment hook overwrites
        # status with the real outcome.
        #
        # Located INSIDE the CI-aggregation branch so local mode
        # (brik integrate) stays untouched: in local mode the framework
        # builds the aggregate directly via report.record per stage, and
        # the post-stage hook records notify itself.
        report.record "notify" "tech" "status" "success"   || true
        report.record "notify" "tech" "kind"   "in-flight" || true
        report.write_fragment "notify" || \
            log.warn "could not write notify pre-fragment (non-fatal)"

        report.aggregate_fragments "$_ci_fragments_dir" || \
            log.warn "fragment aggregation failed (non-fatal)"
    fi

    # Pipeline-level SARIF aggregation + GitLab non-Ultimate exporter
    # (chantier 20260508 P6.E). Both are best-effort: a missing module or
    # an upstream stage that did not emit SARIF leaves the existing
    # notify behaviour intact. The aggregate lands at
    # brik-artifacts/aggregate.sarif and the GitLab report at
    # brik-artifacts/gl-sast-report.json so artifacts.reports.sast in
    # the GitLab notify job can publish either one.
    if [[ -n "${BRIK_WORKSPACE:-}" ]]; then
        _notify._merge_findings_pipeline "${BRIK_WORKSPACE}"
        _notify._export_gitlab_sast "${BRIK_WORKSPACE}"
    fi

    # Read the gatekeeper signal from the aggregate before any side effect
    # uses it. pipeline.business.status is the worst stage business status
    # (error > warning > success); it is the canonical pipeline outcome.
    # Defaults to "success" when no report, no jq, or no business field.
    local business_status="success"
    if [[ -f "$_report_json" ]] && command -v jq >/dev/null 2>&1; then
        local _bs
        _bs="$(jq -r '.pipeline.business.status // empty' "$_report_json" 2>/dev/null)"
        case "$_bs" in
            success|warning|error) business_status="$_bs" ;;
        esac
    fi

    # Inject pipeline.notify metadata (channel intent + gatekeeper) into the
    # aggregate JSON and re-render the HTML so archived artefacts surface
    # the notification dispatch decision. Runs before the md/html copy into
    # brik-artifacts/ so the published report is the patched one.
    _notify._inject_notify_metadata "$_report_json" "$business_status"

    # Emit the rendered aggregate-report on stdout so the full stage table +
    # business outcome are visible in CI job logs. Delegates to
    # report.render_aggregate_terminal which uses the centralized render
    # lib (ASCII box-drawing, computed column widths, render.status colors)
    # for visual consistency with the other CI surfaces (banner.stage,
    # cli.plan output, report.render_terminal). The markdown archive at
    # aggregate-report.md remains untouched for HTML report and downstream
    # tooling. Falls back to a minimal banner when the JSON aggregate is
    # missing (very rare; report not generated upstream).
    if [[ -f "$_report_json" ]]; then
        brik.use pipeline.report 2>/dev/null || true
        report.render_aggregate_terminal "$_report_json" || cat "$_report_md" 2>/dev/null
    else
        echo "========================================"
        echo "  Brik Pipeline Summary"
        echo "========================================"
        echo "  Project : $project_name"
        echo "  Platform: ${BRIK_PLATFORM:-unknown}"
        echo "  Ref     : ${BRIK_COMMIT_REF:-unknown}"
        echo "  SHA     : ${BRIK_COMMIT_SHORT_SHA:-unknown}"
        echo "========================================"
    fi

    # (The per-stage recap table previously emitted here was folded into
    # the markdown Stages section -- see _report._render_aggregate_md
    # for the Business + Metrics columns. Avoids the duplicated
    # information in the CI log.)

    # Map business status to the legacy {success|failed} channel labels for
    # downstream notification helpers (Slack/email/webhook subjects).
    local pipeline_status="success"
    [[ "$business_status" == "error" ]] && pipeline_status="failed"

    local summary_msg="Pipeline $pipeline_status for $project_name (${BRIK_COMMIT_REF:-unknown})"
    local level="info"
    case "$business_status" in
        warning) level="warn"  ;;
        error)   level="error" ;;
    esac

    # Copy pipeline report into workspace for CI artifact upload.
    # BRIK_LOG_DIR lives outside the workspace (/tmp/brik/logs by default),
    # so the GitLab/Jenkins "artifacts: brik-artifacts/" archive cannot find
    # it. Copying the report here makes it downloadable from the CI job
    # artifact URL and removes the "no matching files" warning that fired
    # on every notify run. I/O failures are non-fatal (notify is best-effort)
    # but surfaced as warnings so operators do not lose visibility.
    local _report_html="${_log_dir}/aggregate-report.html"
    if [[ -n "${BRIK_WORKSPACE:-}" ]] && \
       [[ -f "$_report_md" || -f "$_report_json" || -f "$_report_html" ]]; then
        local _artifacts_dir="${BRIK_WORKSPACE}/brik-artifacts"
        if ! mkdir -p "$_artifacts_dir" 2>/dev/null; then
            log.warn "could not create brik-artifacts/ at ${_artifacts_dir} (non-fatal)"
        else
            if [[ -f "$_report_md" ]]; then
                cp "$_report_md" "$_artifacts_dir/" 2>/dev/null || \
                    log.warn "could not copy aggregate-report.md to brik-artifacts/ (non-fatal)"
            fi
            if [[ -f "$_report_json" ]]; then
                cp "$_report_json" "$_artifacts_dir/" 2>/dev/null || \
                    log.warn "could not copy aggregate-report.json to brik-artifacts/ (non-fatal)"
            fi
            if [[ -f "$_report_html" ]]; then
                cp "$_report_html" "$_artifacts_dir/" 2>/dev/null || \
                    log.warn "could not copy aggregate-report.html to brik-artifacts/ (non-fatal)"
                # Surface the HTML location to operators reading CI logs.
                # The path is workspace-relative so it matches the CI artifact
                # download URL once the job uploads brik-artifacts/.
                log.info "html report available at brik-artifacts/aggregate-report.html"
            fi
        fi
    fi

    # Slack notification.
    if [[ -n "${BRIK_NOTIFY_SLACK_CHANNEL:-}" ]]; then
        local slack_on="${BRIK_NOTIFY_SLACK_ON:-always}"
        if _notify._should_send "$slack_on" "$pipeline_status"; then
            notify.send --channel slack --message "$summary_msg" --level "$level" || \
                log.warn "slack notification failed (non-fatal)"
        fi
    fi

    # Email notification.
    if [[ -n "${BRIK_NOTIFY_EMAIL_TO:-}" ]]; then
        local email_on="${BRIK_NOTIFY_EMAIL_ON:-always}"
        if _notify._should_send "$email_on" "$pipeline_status"; then
            notify.send --channel email --message "$summary_msg" --level "$level" || \
                log.warn "email notification failed (non-fatal)"
        fi
    fi

    # Webhook notification: configured by the legacy variable or by a
    # declared webhook Notification endpoint of the referential.
    local _webhook_dest="${BRIK_NOTIFY_WEBHOOK_URL:-}"
    if [[ -z "$_webhook_dest" ]]; then
        _webhook_dest="$(_notify._webhook_endpoint 2>/dev/null | jq -r '.url // empty' 2>/dev/null)"
    fi
    if [[ -n "$_webhook_dest" ]]; then
        local webhook_on="${BRIK_NOTIFY_WEBHOOK_ON:-always}"
        if _notify._should_send "$webhook_on" "$pipeline_status"; then
            notify.send --channel webhook --message "$summary_msg" || \
                log.warn "webhook notification failed (non-fatal)"
        fi
    fi

    # Gatekeeper: propagate a non-zero exit when the pipeline business
    # outcome is error so the CI job (and pipeline.run when notify is
    # invoked at end of run) reflects the real pipeline result.
    if [[ "$business_status" == "error" ]]; then
        return "$BRIK_EXIT_FAILURE"
    fi
    return 0
}

# Merge per-stage SARIF documents into brik-artifacts/aggregate.sarif via
# transverse.findings.merge_pipeline. Best-effort: when the module is not
# loaded (e.g. a stripped-down install) or no SARIF exists upstream, the
# call is a no-op. Logs at debug only so a happy path stays quiet.
_notify._merge_findings_pipeline() {
    local workspace="$1"
    [[ -d "${workspace}/brik-artifacts" ]] || return 0

    brik.use transverse.findings 2>/dev/null || return 0
    if ! declare -f findings.merge_pipeline >/dev/null 2>&1; then
        return 0
    fi
    # Keep stderr visible so a real failure (jq error, IO problem) lands
    # in the CI job log instead of being swallowed and reported only as
    # a generic "non-fatal" warning the operator cannot diagnose.
    if findings.merge_pipeline "$workspace" >/dev/null; then
        log.info "wrote brik-artifacts/aggregate.sarif"
    else
        log.warn "findings.merge_pipeline failed (non-fatal)"
    fi
}

# Convert the aggregate SARIF to a GitLab gl-sast-report.json so
# non-Ultimate GitLab MR widgets surface findings without the SARIF
# overlay. Best-effort; silent skip when no aggregate.sarif exists.
_notify._export_gitlab_sast() {
    local workspace="$1"
    local agg="${workspace}/brik-artifacts/aggregate.sarif"
    local out="${workspace}/brik-artifacts/gl-sast-report.json"
    [[ -f "$agg" ]] || return 0

    brik.use transverse.findings.exporters.gitlab 2>/dev/null || return 0
    if ! declare -f findings.exporters.gitlab.from_sarif >/dev/null 2>&1; then
        return 0
    fi
    if findings.exporters.gitlab.from_sarif "$agg" "$out" >/dev/null; then
        log.info "wrote brik-artifacts/gl-sast-report.json"
    else
        log.warn "findings.exporters.gitlab.from_sarif failed (non-fatal)"
    fi
}
