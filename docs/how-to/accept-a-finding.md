# Risk management with Brik

This document is the DSI and project-owner companion to
[policy.md](configure-org-policy.md). policy.md is the schema reference for
`brik-policy.yml`; this file is the operating guide that explains
**when** to write an entry, **what** to record in it, and **how** to
keep the allowlist honest over time.

## The principle: risk with traceability

Brik does not let projects bypass pipeline failures silently. Every
finding the pipeline cannot autofix should fall in one of two buckets:

- **Remediate**  the project upgrades the dependency, patches the
  Dockerfile, fixes the lint error, etc.
- **Accept**  the team explicitly records "we know about this CVE /
  rule / vulnerability, we have a stated reason not to fix it now, and
  we have a date by which we will revisit it".

The danger to avoid is the *watermelon* (green outside, red inside):
adding a CVE to an allowlist file without recording the reason, the
owner, and the expiration. Brik schemas refuse entries without an
`expires` field for exactly this reason.

## Decision tree

```
pipeline failed on a finding (CVE / rule / vulnerability)
        │
        ├── Does an upstream fix exist? (fix_classification = has_fix)
        │     │
        │     ├── yes -> remediate. Upgrade the dependency / patch the
        │     │           code / apply the fix in the next commit.
        │     │
        │     └── no  -> Is this a snapshot or release pipeline?
        │           │
        │           ├── snapshot -> business.status = warning. Acceptable
        │           │                in development. Plan the upgrade.
        │           │
        │           └── release  -> business.status = error. Either fix
        │                            or write a policy entry with
        │                            `expires`. Do not silently allowlist.
        │
        └── Is there NO upstream fix? (fix_classification = no_fix)
              │
              ├── Is the CVE actually reachable in this codebase?
              │     │
              │     ├── no  -> write a policy entry tagged
              │     │           policy.org.cve-allowlist with the
              │     │           non-reachability rationale and an
              │     │           `expires` set to the next review date.
              │     │
              │     └── yes -> mitigate at runtime (WAF rule, config
              │                 change, ...). If mitigation is in place,
              │                 record it as the reason. If not, treat
              │                 the CVE as has_fix-equivalent: fix or
              │                 accept the release-blocking outcome.
              │
              └── Vendor explicitly wont-fix?
                    -> write a policy entry. Capture the upstream link
                       (issue, advisory) as the rationale. Set `expires`
                       to a deliberate review date (90 / 180 / 365 days),
                       never indefinite.
```

## Writing a no_fix entry

A `brik-policy.yml` entry that records an accepted risk looks like:

```yaml
allow:
  cve:
    - id: CVE-2026-04141
      reason: |
        Reachable via the legacy /admin endpoint which is behind the
        internal VPN gateway; not exposed publicly. Upstream wont-fix
        because the affected version is past EOL.
        Upstream issue: https://github.com/example/lib/issues/4231
      expires: 2026-09-30
      projects:
        - getbrik/legacy-admin
```

The required fields per entry are the schema-level minimum
(`id`, `reason`, `expires` for CVEs; `glob`, `reason`, `expires` for
path entries) plus the discipline below.

| Field      | What to write                                                                                                      | Anti-pattern                                          |
|------------|---------------------------------------------------------------------------------------------------------------------|-------------------------------------------------------|
| `id`       | The exact CVE / advisory id Brik observes in the SARIF.                                                            | A regex bucket like `CVE-2026-*`.                     |
| `reason`   | The concrete reason this finding is accepted. Reference upstream ticket, mitigation in place, EOL status.          | "legacy code", "false positive", "low impact".        |
| `expires`  | A date no further than your next planned dependency audit. Default 90 days for has_fix, 180 days for no_fix.        | Two years out. Never indefinite.                      |
| `projects` | Optional. The exact `<group>/<repo>` pairs this entry applies to. Omit for org-wide.                                | Adding `*` or omitting when scoping was the intent.   |
| `paths`    | (path entries) Globs scoped narrowly to the actually-out-of-scope tree.                                            | `**` or `*.js` (too wide).                            |

## Where these entries surface

Once the referential's `Policy` document points at your policy file, every pipeline that
runs through Brik consumes it. The aggregate-report (Markdown / JSON)
that lands on every pipeline summarises both **Failing findings** and
**Ignored findings** with the per-source breakdown:

- `policy.org.cve-allowlist`  CVEs DSI deliberately allowlisted.
- `policy.org.path-allowlist`  path-scoped suppressions.
- `policy.built-in.no-upstream-fix` / `vendor-wont-fix` / `below-severity`
  the pragmatic preset defaults.
- `tool_native`  pre-existing suppressions emitted by the tool itself
  (eslint inline-disable, semgrep noqa, ...).

The **Expiring soon** section automatically lists every entry whose
`expires` date is within `BRIK_FINDINGS_EXPIRING_SOON_DAYS` (default 30)
of the current date, so the DSI sees upcoming churn before pipelines
turn red.

## Operating discipline

A no_fix allowlist is only useful if someone reviews it. The
suggested cadence:

| Cadence    | Action                                                                                                   |
|------------|----------------------------------------------------------------------------------------------------------|
| Per PR     | Reviewers refuse new entries that lack `reason` or set `expires` past the next planned audit.            |
| Weekly     | Read the **Expiring soon** section of any nightly aggregate-report; nominate owners for each expiry.     |
| Quarterly  | Walk the full `brik-policy.yml`; delete entries whose dependencies have been upgraded since.             |
| Annually   | Refresh the policy with the year's CVE backlog. Anything still active after a year is treated as has_fix in release context (set `expires` to a near date and re-evaluate). |

## When the matrix gets it wrong

Brik defaults are intentionally conservative:

- An unannotated failing finding maps to `fix_class = has_fix`  in
  release context it blocks. This forces the project to either fix or
  explicitly accept the risk; it never silently drops on the floor.
- The pragmatic preset filters below-severity findings. If your team
  needs critical+high only, this default is correct. If you need lower
  severities to block release, set `quality.findings.policy: strict`.
- The permissive preset effectively raises the floor to critical only.
  Use it sparingly  it removes most of the safety net.

When the matrix produces an outcome that does not match your team's
intent, the answer is almost always one of:

1. Write a policy entry (allowlist) with a clear rationale and
   `expires`  this is the supported path.
2. Adjust `quality.findings.policy` at the project level to pick a
   different preset.
3. Change the matrix itself: an org-wide policy shift decided
   outside an individual project.

Never disable the matrix by exporting `BRIK_CONTINUE_ON_ERROR=1` in CI.

## Gates during CD deployment

The CI findings gates sit in the **Build** and **Package** stages. A separate set
of gates runs in the **Deploy** stage, where the infrastructure referential takes
over:

- **`require_digest`**: the deploy must pin the exact digest produced by CI.
- **`require_attestation`**: the SBOM and SLSA provenance attached to that
  digest must be signed and verifiable against your trust material. The
  `expected_builder` regex and `expected_source` regex let you enforce that the
  builder identity matches your expectations.
- **`requires_eligibility`**: the digest must have a signed grant in the
  promotion journal (`brik authorize`) or a signed validation from a prior
  environment's successful deploy.

Every gate is fail-closed: missing evidence, an unverifiable signature, or
ineligibility refuses the deploy. This is independent of the CI findings matrix:
a perfectly-clean CI run cannot deploy without valid evidence and a signed
promotion.

For the full gate semantics and the builder-identity convention, see
[artifact attestation](../concepts/supply-chain.md).
that hides risk without recording it, which is the watermelon failure
mode this entire framework exists to prevent.

## Proof retention

The proofs live in two stores, and each store owns its garbage collection:

- the **registry** holds the published digests and their attestation
  referrers;
- the **git host** holds the state-repo (evidence files, promotion and
  deployment journals) behind branch protection.

Brik never purges anything. The org declares its retention posture in
`brik-policy.yml` under `retention:` (`registry_days`, `state_repo_days`,
0 = unlimited); the fields are **informative**: they document, in the one
governed file audits already read, what the registry GC and the git-host
policies are configured to do elsewhere. Two operating rules:

- A proof referenced by a journal event must outlive the deployments it
  vouches for: never let a registry GC delete a digest (or its referrers)
  that an environment still runs or that a grant still names.
- Journal events consumed by `requires_eligibility` are the source of truth
  for eligibility: purging state-repo history invalidates grants. Prefer
  unlimited retention on the state-repo; it is small, append-only text.

## References

- [policy.md](configure-org-policy.md): schema reference for `brik-policy.yml`.
- [findings.md](manage-findings.md): runtime behaviour, presets, gating semantics.
- [business-outcome.md / Decision matrix](../concepts/business-outcome.md#decision-matrix)
  (the 10-row business.evaluate matrix that consumes policy outputs).
