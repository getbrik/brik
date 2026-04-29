# `notify` configuration

> Schema source: [`brik.schema.json#$defs/notify`](../../../schemas/config/v1/brik.schema.json)

The `notify` section declares one or more notification channels (Slack,
email, webhook) and the pipeline events that trigger them. Each channel
is independent and entirely optional.

Sensitive values (Slack webhook URLs, custom webhook URLs) are NEVER
read from `brik.yml`. They are resolved from CI environment variables
so secrets stay out of the source tree.

## Quick reference

<!-- BEGIN AUTO-GENERATED: quick-reference -->
### `notify.slack`

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `notify.slack.channel` | string | -- | Slack channel name including the # prefix (e.g. #deployments). |
| `notify.slack.on` | array of enum (`failure`, `success`, `always`) | -- | Pipeline events that trigger a Slack notification. |

### `notify.email`

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `notify.email.to` | string | -- | Recipient email address or comma-separated list of addresses. |
| `notify.email.on` | array of enum (`failure`, `success`, `always`) | -- | Pipeline events that trigger an email notification. |

### `notify.webhook`

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `notify.webhook.url` | string | -- | Webhook endpoint URL. |
| `notify.webhook.on` | array of enum (`failure`, `success`, `always`) | -- | Pipeline events that trigger a webhook call. |

<!-- END AUTO-GENERATED -->

Each `*.on` array accepts a non-empty, unique combination of:

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
