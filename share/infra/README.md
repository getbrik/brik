# Bundled infrastructure referentials

## `p-local/` - built-in default for local execution

The instance Brik falls back to for **containerized local execution** on a bare
host when no referential is configured (`BRIK_INFRA_DIR` / `BRIK_INFRA_REPO`
both unset). It declares no endpoints, no credentials and no signing, so a plain
CI run (`brik integrate`, `brik stage`) needs zero setup while `init`/the
planner still journal its fingerprint into `plan.json`.

It is kept to a single `referential.yml` on purpose: its fingerprint must stay
a stable constant. Do not add secrets or environment-specific endpoints here.

To run `package`, `promote`, `deploy` or signing locally, scaffold your own
instance with `brik infra init` (writes to `.brik/infra/` by default) and point
`BRIK_INFRA_DIR` at it. See `docs/concepts/local-execution.md`.
