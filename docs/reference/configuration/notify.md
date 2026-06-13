# `notify`

> [!NOTE]
> Announce the pipeline outcome over one or more channels (Slack, email,
> webhook).

**Section:** `notify` (optional) &nbsp;·&nbsp; **Schema:** [`brik.schema.json#$defs/notify`](../../../schemas/config/v1/brik.schema.json)

## What it is for

Tell people (or another system) when a run finishes, and on which outcomes you
want to hear about it.

You declare one or more channels and, per channel, the events that trigger a
message. Each channel is independent and entirely optional.

## What it does

- Sends a message on Slack, by email, or to a webhook endpoint, according to the
  `on` events you list (`failure`, `success`, `always`).
- Resolves transport credentials (Slack webhook URL, custom webhook URL) from CI
  environment variables, never from a value stored in `brik.yml`.
- Skips a channel with a warning when its credential variable is unset. The
  pipeline does not fail.

## When it runs

The Notify stage runs last, after every other stage has settled, so it can
report the final pipeline outcome. It is the closing step of both the CI and the
CD flows.

## How to configure

Declare a sub-object per channel you want to notify. Each field's type and
default is in the table; its description follows below.

<!-- BEGIN AUTO-GENERATED: quick-reference -->
### `notify.slack`

Slack notification configuration.

| Field | Type | Default |
|-------|------|---------|
| `notify.slack.channel` | `string` | -- |
| `notify.slack.on` | array of enum (`failure`, `success`, `always`) | -- |

- **`notify.slack.channel`**

  Slack channel name including the # prefix (e.g. #deployments).

- **`notify.slack.on`**

  Pipeline events that trigger a Slack notification.

  - **`failure`**: send only when the run fails
  - **`success`**: send only when the run succeeds
  - **`always`**: send on every run, success or failure


*Example*

```yaml
notify:
  slack:
    channel: #deployments
```

### `notify.email`

Email notification configuration.

| Field | Type | Default |
|-------|------|---------|
| `notify.email.to` | `string` | -- |
| `notify.email.on` | array of enum (`failure`, `success`, `always`) | -- |

- **`notify.email.to`**

  Recipient email address or comma-separated list of addresses.

- **`notify.email.on`**

  Pipeline events that trigger an email notification.

  - **`failure`**: send only when the run fails
  - **`success`**: send only when the run succeeds
  - **`always`**: send on every run, success or failure


*Example*

```yaml
notify:
  email:
    to: oncall@example.com
```

### `notify.webhook`

Webhook notification configuration.

| Field | Type | Default |
|-------|------|---------|
| `notify.webhook.url` | `string` | -- |
| `notify.webhook.on` | array of enum (`failure`, `success`, `always`) | -- |

- **`notify.webhook.url`**

  Webhook endpoint URL.

- **`notify.webhook.on`**

  Pipeline events that trigger a webhook call.

  - **`failure`**: send only when the run fails
  - **`success`**: send only when the run succeeds
  - **`always`**: send on every run, success or failure


*Example*

```yaml
notify:
  webhook:
    url: https://hooks.example.com/notify
```

<!-- END AUTO-GENERATED -->

Each `*.on` array accepts a non-empty, unique combination of:

| Event | Meaning |
|-------|---------|
| `failure` | Send when at least one stage failed. |
| `success` | Send when all stages succeeded. |
| `always` | Send regardless of pipeline outcome. |

The transport credentials live outside `brik.yml`:

| Channel | Variable | Purpose |
|---------|----------|---------|
| Slack | `SLACK_WEBHOOK_URL` (or the name set via `BRIK_NOTIFY_SLACK_WEBHOOK_VAR`) | Incoming-webhook URL used to post the message. |
| Email | (none) | Uses the runner's `sendmail` then `mail` binary. If neither is present the channel logs a warning and skips. |
| Webhook | `BRIK_NOTIFY_WEBHOOK_URL` (or the name passed via `--url-var`) | URL the message is POSTed to. |

If a Slack notification is declared in `brik.yml` but `SLACK_WEBHOOK_URL` is not
set in the CI environment, the notification is skipped with a warning. The
pipeline does not fail.

### Examples

Per-field examples are under each field above. These are whole-section scenarios
that those do not show.

Multiple channels in one config. The Slack channel announces both green and red
runs while the webhook fires only on red ones:

```yaml
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

## See also

- [`deploy`](deploy.md) - environments and rollout outcomes feeding the notification status
- [`release`](release.md) - the release stage emits structured events that the notify stage relays
- [Fixed flows](../../concepts/fixed-flows.md) - where the Notify stage sits in the flow
- [`brik.yml` reference](README.md) - all top-level sections
