# Public API surface: `rollout`

> Source: `lib/rollout/**/*.sh`.

## Public functions

Format: `<notion>.<submodule>.<verb>` (convention layout.md).

<!-- BEGIN AUTO-GENERATED: public-api -->
| Function| Source file |
|---|---|
| `rollout.health.check` | `rollout/health.sh:19` |
| `_rollout.health._url_status_check` | `rollout/health.sh:69` |
| `rollout.health.wait` | `rollout/health.sh:82` |
| `rollout.health.k8s_wait` | `rollout/health.sh:132` |
| `rollout.profile.resolve` | `rollout/profile.sh:24` |
| `rollout.profile.merge` | `rollout/profile.sh:51` |
| `rollout.strategy.run` | `rollout/strategy.sh:30` |
| `_rollout.strategy._exec_rolling` | `rollout/strategy.sh:127` |
| `_rollout.strategy._exec_blue_green` | `rollout/strategy.sh:143` |
| `_rollout.strategy._exec_canary` | `rollout/strategy.sh:158` |
| `_rollout.strategy._try_rollback` | `rollout/strategy.sh:172` |
| `_rollout.strategy._rolling_kubectl` | `rollout/strategy.sh:198` |
| `_rollout.strategy._blue_green_kubectl` | `rollout/strategy.sh:255` |
| `_rollout.strategy._canary_kubectl` | `rollout/strategy.sh:318` |

## Total

**14 unique public functions** in notion `rollout`.
<!-- END AUTO-GENERATED -->
