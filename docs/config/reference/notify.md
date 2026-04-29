# `notify` configuration

> Schema source: [`brik.schema.json#$defs/notify`](../../../schemas/config/v1/brik.schema.json)

The `notify` section declares one or more notification channels (Slack,
email, webhook) and the pipeline events that trigger them. Each channel
is independent and entirely optional.

Sensitive values (Slack webhook URLs, custom webhook URLs) are NEVER
read from `brik.yml`. They are resolved from CI environment variables
so secrets stay out of the source tree.

## Quick reference

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `notify.slack.channel` | string | -- | Slack channel including the `#` prefix. Used as the display channel on the message. |
| `notify.slack.on` | string array | -- | Events that trigger a Slack notification. |
| `notify.email.to` | string | -- | Recipient address, or comma-separated list. |
| `notify.email.on` | string array | -- | Events that trigger an email notification. |
| `notify.webhook.url` | string (uri) | -- | Webhook endpoint URL. |
| `notify.webhook.on` | string array | -- | Events that trigger a webhook call. |

The `on` arrays accept any non-empty unique combination of:

| Event | Meaning |
|-------|---------|
| `failure` | Send when at least one stage failed. |
| `success` | Send when all stages succeeded. |
| `always` | Send regardless of pipeline outcome. |

## Secrets and environment

The actual transport credentials live outside `brik.yml`:

| Channel | Variable | Purpose |
|---------|----------|---------|
| Slack | `SLACK_WEBHOOK_URL` (or the name set via `BRIK_NOTIFY_SLACK_WEBHOOK_VAR`) | Incoming-webhook URL used to post the message. |
| Email | -- | Uses the runner's `sendmail` then `mail` binary. If neither is present the channel logs a warning and skips. |
| Webhook | `BRIK_NOTIFY_WEBHOOK_URL` (or the name passed via `--url-var`) | URL the message is POSTed to. |

If a Slack notification is declared in `brik.yml` but `SLACK_WEBHOOK_URL`
is not set in the CI environment, the notification is skipped with a
warning -- the pipeline does not fail.

## Examples

### Slack on failure

```yaml
version: 1
project:
  name: my-app
notify:
  slack:
    channel: "#deployments"
    on:
      - failure
```

### Email recap on every run

```yaml
version: 1
project:
  name: my-app
notify:
  email:
    to: oncall@example.com
    on:
      - always
```

### Multiple channels in one config

```yaml
version: 1
project:
  name: my-app
notify:
  slack:
    channel: "#deployments"
    on:
      - failure
      - success
  webhook:
    url: https://hooks.example.com/notify
    on:
      - failure
```

The Slack channel announces both green and red runs while the webhook
fires only on red ones.

## See also

- [`reference/deploy.md`](deploy.md) - environments and rollout outcomes feeding the notification status
- [`reference/release.md`](release.md) - the release stage emits structured events that the notify stage relays
- [`overview.md`](../overview.md) - declarative model
