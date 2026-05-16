#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# @module transverse.config.exports.notify
# @description Exports BRIK_NOTIFY_* variables from brik.yml.

# Guard against double-sourcing
[[ -n "${_BRIK_CONFIG_EXPORTS_NOTIFY_LOADED:-}" ]] && return 0
_BRIK_CONFIG_EXPORTS_NOTIFY_LOADED=1

# Export notify-related variables from brik.yml.
# Sets: BRIK_NOTIFY_SLACK_*, BRIK_NOTIFY_EMAIL_*, BRIK_NOTIFY_WEBHOOK_*
config.export_notify_vars() {
    local val

    val="$(config.get '.notify.slack.channel' '')"
    [[ -n "$val" ]] && export BRIK_NOTIFY_SLACK_CHANNEL="$val"

    val="$(config.get '.notify.slack.on' '')"
    [[ -n "$val" ]] && export BRIK_NOTIFY_SLACK_ON="$val"

    val="$(config.get '.notify.email.to' '')"
    [[ -n "$val" ]] && export BRIK_NOTIFY_EMAIL_TO="$val"

    val="$(config.get '.notify.email.on' '')"
    [[ -n "$val" ]] && export BRIK_NOTIFY_EMAIL_ON="$val"

    val="$(config.get '.notify.webhook.url' '')"
    [[ -n "$val" ]] && export BRIK_NOTIFY_WEBHOOK_URL="$val"

    val="$(config.get '.notify.webhook.on' '')"
    [[ -n "$val" ]] && export BRIK_NOTIFY_WEBHOOK_ON="$val"

    return 0
}
