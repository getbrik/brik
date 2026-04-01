#!/usr/bin/env bash
# @module stages/notify
# @description Notify stage - pipeline summary and notification wiring.

# Notify stage: print pipeline summary and prepare notifications.
# Usage: stages.notify <context_file>
stages.notify() {
    # shellcheck disable=SC2034
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

    # Slack notification wiring
    if [[ -n "${BRIK_NOTIFY_SLACK_CHANNEL:-}" ]]; then
        log.info "would notify slack channel: $BRIK_NOTIFY_SLACK_CHANNEL (on: ${BRIK_NOTIFY_SLACK_ON:-always})"
    fi

    # Email notification wiring
    if [[ -n "${BRIK_NOTIFY_EMAIL_TO:-}" ]]; then
        log.info "would notify email: $BRIK_NOTIFY_EMAIL_TO (on: ${BRIK_NOTIFY_EMAIL_ON:-always})"
    fi

    # Webhook notification wiring
    if [[ -n "${BRIK_NOTIFY_WEBHOOK_URL:-}" ]]; then
        log.info "would notify webhook: $BRIK_NOTIFY_WEBHOOK_URL (on: ${BRIK_NOTIFY_WEBHOOK_ON:-always})"
    fi

    return 0
}
