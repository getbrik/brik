# Brik Organisational Policy

This guide is for **DSI / security teams** distributing a centralised
findings-management policy across many Brik projects. The policy file
(`brik-policy.yml`) lets the org allow-list specific CVEs and file paths,
override the built-in preset, and document why an exception exists -- all
without touching individual project configuration.

For project-side knobs and the SARIF pipeline overview, see
[`findings.md`](findings.md).

## How it fits

Brik runs a layered policy hierarchy on every finding:

```
1. Native suppressions[]          -- pre-existing tool allowlist, never touched
2. Org policy CVE allowlist       -> tagged policy.org.cve-allowlist
3. Org policy path allowlist      -> tagged policy.org.path-allowlist
4. Built-in preset (pragmatic|strict|permissive)
                                  -> tagged policy.built-in.<reason>
otherwise                         -> failing
```

The org policy lives at one URL (the referential's `Policy` document); every Brik runner
fetches, validates, compiles and caches it once at the **init** stage.

## Schema

The full schema is at `schemas/policy/v1/brik-policy.schema.json`.
A minimal valid file:

```yaml
# brik-policy.yml -- schema version is the URL path (v1/), not an in-file field
preset: pragmatic           # optional: overrides project-level preset

allow:
  cve:
    - id: CVE-2025-15366
      reason: "False positive on python:3.13 base; tracked in BRIK-1234"
      expires: 2026-09-30
      projects:             # optional allowlist scope
        - python-complete
        - python-minimal    # exact match in v1; wildcards reserved for v2
  paths:
    - glob: "tests/fixtures/**"
      reason: "Synthetic vulnerable code used to test the SARIF pipeline"
      expires: 2026-12-31
```

Required fields per CVE entry: `id` (CVE-XXXX-N..), `reason`, `expires`
(YYYY-MM-DD). Required for path entries: `glob`, `reason`, `expires`.
Wildcards in `projects[]` are not supported in v1 -- use exact matches.

Beyond findings management, the file also carries two CD governance knobs:

```yaml
state_repo_protection: required   # required | warn | off (absent = warn)

retention:                        # informative: documents the GC configured
  registry_days: 730              # on the registry and the git host; brik
  state_repo_days: 0              # never purges (0 = unlimited)
```

`state_repo_protection` gates the deploy on the state-repo branch protection
(fail-closed when `required`). `retention` is declarative only -- see
[proof retention](risk-management.md#proof-retention) for the operating
rules.

## Distribution and infrastructure referential

The `url` of the infrastructure referential's `Policy` document points the
runner at the policy file. The Policy document is one of several documents in
the referential (Endpoints, Credentials, TrustMaterial, Policy); Brik validates
the entire referential at init and deploy, and every plan carries the
referential's fingerprint for audit. Three common deployments:

| Use case          | URL example                              | Notes |
|-------------------|------------------------------------------|-------|
| Dev / briklab     | `file:///etc/brik/policy/brik-policy.yml` | Mounted as a Docker volume in the runner. |
| GitLab self-host  | `https://gitlab.example.com/api/v4/projects/.../raw/main/brik-policy.yml` | Token-protected when private. |
| GitHub raw        | `https://raw.githubusercontent.com/org/policy/main/brik-policy.yml` | Public or PAT-authenticated. |

Set the variable in the CI platform's group-level configuration so every
project picks it up automatically. Brik fetches once per pipeline; the
result lands in the per-run cache (see Debugging below) and is consumed
by every stage in that pipeline.

## Validation

The runner validates the YAML against the JSON Schema (`jv` + the bundled
schema) before compiling. Validation errors are **fail-closed**: an
invalid `brik-policy.yml` aborts the init stage with `BRIK_EXIT_CONFIG_ERROR`
rather than silently falling back to the built-in preset. This guarantees
that a project that opted into org policy never silently regresses to
defaults.

## Caching

The compiled, project-filtered policy lands at:

```
${BRIK_WORKSPACE}/.brik-logs/policy.cache.json
```

Override the path with `BRIK_POLICY_CACHE_PATH` if you want the cache in
a different location.

The cache is regenerated on every pipeline (no TTL) so an updated policy
is in effect on the next CI run -- no per-project bump required.

## Debugging

Inspect the compiled cache:

```bash
cat .brik-logs/policy.cache.json | jq
# {
#   "preset_override": "pragmatic",
#   "cve_allowlist": ["CVE-2025-15366"],
#   "path_globs": [{"regex": "^tests/fixtures/.*$", "glob": "tests/fixtures/**"}],
#   "cve_entries": [...],
#   "path_entries": [...],
#   "loaded_at": "2026-05-08T18:00:00Z"
# }
```

Track allowlist usage in the aggregate report:

```bash
jq '.stages[].business.findings.ignored.by_source' brik-artifacts/aggregate-report.json
# {
#   "policy.org.cve-allowlist":  3,
#   "policy.built-in.below-severity": 11
# }
```

## Expiration

Every allowlist entry **must** carry `expires` -- the schema makes
the field mandatory. The runner emits a non-blocking warning at
init when an entry expires within `BRIK_FINDINGS_EXPIRING_SOON_DAYS`
(default 30) and lists it in the aggregate report's "Expiring soon"
section. Past `expires` -> the entry is silently dropped and the
corresponding finding repasses failing on the next run.

## Adding a converter

Tools that emit JSON or NDJSON (not SARIF) need a converter so their
output joins the SARIF pipeline. Drop a new file at:

```
lib/transverse/findings/converters/<tool>.sh
```

exposing `findings.converters.<tool>.to_sarif <input> <output>`. Look at
`junit.sh`, `ruff.sh`, or `bandit.sh` for the structure. The dispatcher
auto-discovers the file -- no further wiring needed.

For each converter ship a synthetic JSON fixture under
`spec/fixtures/json/<tool>.json` and a matching ShellSpec under
`spec/transverse/findings_converters_<tool>_spec.sh`.

## References

- Schema       : `schemas/policy/v1/brik-policy.schema.json`
- Loader       : `lib/transverse/findings/org_policy.sh`
- Apply policy : `lib/transverse/findings.sh` (`findings.apply_policy`)
- Aggregator   : `lib/transverse/findings.sh` (`findings.merge_pipeline`)
- Exporter     : `lib/transverse/findings/exporters/gitlab.sh`
- User-side guide: [`findings.md`](findings.md)
- Operating discipline (when to allowlist, cadence, anti-patterns):
  [`risk-management.md`](risk-management.md)
