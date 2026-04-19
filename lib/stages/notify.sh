#!/usr/bin/env bash
# @module stages/notify
# @description Notify stage - pipeline summary and notifications.

# Notify stage: print pipeline summary and send notifications.
# Usage: stages.notify <context_file>
stages.notify() {
    local context_file="$1"

    config.export_notify_vars

    log.info "notify stage - pipeline summary"

    local project_name
    project_name="$(config.get '.project.name' 'unnamed')"

    echo "========================================"
    echo "  Brik Pipeline Summary"
    echo "========================================"
    echo "  Project : $project_name"
    echo "  Platform: ${BRIK_PLATFORM:-unknown}"
    echo "  Ref     : ${BRIK_COMMIT_REF:-unknown}"
    echo "  SHA     : ${BRIK_COMMIT_SHORT_SHA:-unknown}"
    echo "========================================"

    # Determine pipeline status from context
    local pipeline_status="success"
    if [[ -n "$context_file" && -f "$context_file" ]]; then
        local ctx_val
        # optional: key may not exist in context
        ctx_val="$(context.get "$context_file" "BRIK_PIPELINE_STATUS" 2>/dev/null)" || true
        [[ -n "$ctx_val" ]] && pipeline_status="$ctx_val"
    fi

    local summary_msg="Pipeline $pipeline_status for $project_name (${BRIK_COMMIT_REF:-unknown})"
    local level="info"
    [[ "$pipeline_status" == "failed" ]] && level="error"

    brik.use notify

    # Slack notification
    if [[ -n "${BRIK_NOTIFY_SLACK_CHANNEL:-}" ]]; then
        local slack_on="${BRIK_NOTIFY_SLACK_ON:-always}"
        if _notify._should_send "$slack_on" "$pipeline_status"; then
            notify.send --channel slack --message "$summary_msg" --level "$level" || \
                log.warn "slack notification failed (non-fatal)"
        fi
    fi

    # Email notification
    if [[ -n "${BRIK_NOTIFY_EMAIL_TO:-}" ]]; then
        local email_on="${BRIK_NOTIFY_EMAIL_ON:-always}"
        if _notify._should_send "$email_on" "$pipeline_status"; then
            notify.send --channel email --message "$summary_msg" --level "$level" || \
                log.warn "email notification failed (non-fatal)"
        fi
    fi

    # Webhook notification
    if [[ -n "${BRIK_NOTIFY_WEBHOOK_URL:-}" ]]; then
        local webhook_on="${BRIK_NOTIFY_WEBHOOK_ON:-always}"
        if _notify._should_send "$webhook_on" "$pipeline_status"; then
            notify.send --channel webhook --message "$summary_msg" || \
                log.warn "webhook notification failed (non-fatal)"
        fi
    fi

    return 0
}
