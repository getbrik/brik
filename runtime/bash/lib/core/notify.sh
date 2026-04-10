#!/usr/bin/env bash
# @module notify
# @description Notification dispatcher for Slack, email, and webhook.

# Guard against double-sourcing
[[ -n "${_BRIK_CORE_NOTIFY_LOADED:-}" ]] && return 0
_BRIK_CORE_NOTIFY_LOADED=1

# Check if a notification should be sent based on the 'on' condition and pipeline status.
# Usage: _notify._should_send <on_condition> <pipeline_status>
# on_condition: "always", "failure", "success" (or comma-separated list)
# pipeline_status: "success" or "failed"
_notify._should_send() {
    local on_condition="$1"
    local pipeline_status="$2"

    [[ "$on_condition" == "always" ]] && return 0
    [[ "$on_condition" == *"$pipeline_status"* ]] && return 0
    [[ "$on_condition" == *"failure"* && "$pipeline_status" == "failed" ]] && return 0

    return "$BRIK_EXIT_FAILURE"
}

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

# Send a Slack notification via Incoming Webhook.
# Usage: notify.slack --message <text> [--webhook-var <VAR>] [--channel <channel>]
#        [--level <info|warn|error>] [--dry-run]
# Reads defaults from BRIK_NOTIFY_SLACK_* environment variables.
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

    # Resolve webhook URL from variable
    local webhook_url="${!webhook_var:-}"
    if [[ -z "$webhook_url" ]]; then
        log.warn "Slack webhook variable '$webhook_var' is not set, skipping"
        return 0
    fi

    # Map level to Slack color
    local color
    case "$level" in
        info)  color="#36a64f" ;;  # green
        warn)  color="#daa520" ;;  # gold
        error) color="#cc0000" ;;  # red
        *)     color="#36a64f" ;;
    esac

    # Build JSON payload (escape message to prevent injection)
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

    runtime.require_tool curl || return "$BRIK_EXIT_MISSING_DEP"

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

    # Try sendmail, then mail, then log a warning
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

# Send a webhook notification via HTTP POST.
# Usage: notify.webhook --message <text> [--url-var <VAR>] [--dry-run]
# Reads default URL from BRIK_NOTIFY_WEBHOOK_URL or the variable named by --url-var.
notify.webhook() {
    local message="" url_var="" dry_run="${BRIK_DRY_RUN:-}"
    local url="${BRIK_NOTIFY_WEBHOOK_URL:-}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --message) message="$2"; shift 2 ;;
            --url-var) url_var="$2"; shift 2 ;;
            --url) url="$2"; shift 2 ;;
            --dry-run) dry_run="true"; shift ;;
            *) log.error "unknown option: $1"; return "$BRIK_EXIT_INVALID_INPUT" ;;
        esac
    done

    if [[ -z "$message" ]]; then
        log.error "webhook message is required"
        return "$BRIK_EXIT_INVALID_INPUT"
    fi

    # Resolve URL from variable if specified
    if [[ -n "$url_var" ]]; then
        url="${!url_var:-}"
    fi

    if [[ -z "$url" ]]; then
        log.warn "no webhook URL configured, skipping"
        return 0
    fi

    # Escape message to prevent JSON injection
    local safe_message="${message//\\/\\\\}"
    safe_message="${safe_message//\"/\\\"}"
    local payload="{\"text\":\"${safe_message}\",\"project\":\"${BRIK_PROJECT_NAME:-unknown}\",\"platform\":\"${BRIK_PLATFORM:-unknown}\"}"

    if [[ "$dry_run" == "true" ]]; then
        log.info "[dry-run] webhook POST to $url"
        return 0
    fi

    runtime.require_tool curl || return "$BRIK_EXIT_MISSING_DEP"

    curl --silent --max-time 10 --connect-timeout 5 \
        -H "Content-Type: application/json" \
        -d "$payload" \
        "$url" >/dev/null || {
        log.error "webhook notification failed"
        return "$BRIK_EXIT_EXTERNAL_FAIL"
    }

    log.info "webhook notification sent"
    return 0
}
