# Artifact attestation and deploy gates

CI produces one immutable artifact and attaches signed proofs to its digest;
CD verifies those proofs before deploying. Three orthogonal gates each answer
one question about the artifact at deploy time:

| Gate | Question | Proof | Verified against |
|---|---|---|---|
| `require_digest` | is this exactly **this content**? | registry content-addressing | the digest resolved via `accepts_channel` |
| `require_attestation` | where does it come from, **who attests it**? | signed in-toto attestations attached to the digest | the referential's trust material, plus the deploy expectations |
| `requires_eligibility` | does it have the **blessing** for this environment? | signed PromotionJournal events bound to the digest | the environment's `all_of` list |

The gates run in a fixed order: channel resolution, `require_digest`,
`require_attestation`, `requires_eligibility`, then the pinned injection,
rollout and digest read-back. Every gate is fail-closed: missing trust
material, an unreachable journal or an unverifiable proof refuses the deploy,
never a silent pass.

**Attestation is not eligibility.** The attestation is produced by CI and
travels with the artifact (it says where it comes from). Eligibility is a
posterior decision -- `brik authorize`, or a validated deploy on the previous
environment -- recorded in the journal (it says where it may go). A perfectly
attested artifact may not be eligible for production, and a grant never
replaces the authenticity check.

## The builder-identity convention

The SLSA provenance predicate CI emits carries a verifiable builder identity:

- `runDetails.builder.id` = `<orchestrator-url>/-/brik/<runner-class>` --
  the orchestrator base URL (`CI_SERVER_URL` on GitLab, `JENKINS_URL` on
  Jenkins; local runs root at `https://brik.sh/local`) and the runner class
  the stage's registry manifest declares.
- `runDetails.builder.version.brik` = the brik version that ran the build.
- `buildDefinition.externalParameters.version` = the git tag being built.
- `buildDefinition.resolvedDependencies[0].uri` = the source repository.

`require_attestation` checks, on the cosign-verified payload only:

1. the predicate's version is the version being deployed (anti-substitution,
   tolerant of the configured `release.tag_prefix`);
2. the builder id is non-empty, and matches `gates.expected_builder` when
   configured;
3. the source repository matches `gates.expected_source` when configured.

```yaml
deploy:
  environments:
    production:
      accepts_channel: release
      gates:
        require_digest: true
        require_attestation: true
        expected_builder: "^https://gitlab\\.example\\.com/-/brik/"
        expected_source: "gitlab\\.example\\.com/team/app$"
        requires_eligibility: [artifact_authorized_for]
```

## Eligibility and the promotion journal

The PromotionJournal lives in the project's state-repo
(`artifacts.evidence.repo`) as append-only, file-per-event records under
`promotions/`. Every event binds to the image digest: a grant on a version
name alone could be replayed against a different artifact.

`requires_eligibility` clones the journal, verifies the tip signature when
the project declares signed evidence, and requires every listed event type
for the digest and the target environment. Grants are written by
`brik authorize --version <v> --for <env>` (`artifact_authorized_for`) and,
for declarative chains, by a validated deploy on the previous environment
(`artifact_validated_for`).

## Re-entry semantics

Re-running `brik deploy` for the same (version, environment) converges: the
per-environment lock serializes concurrent runs, the gates re-evaluate
against the same digest, the apply is idempotent, and the read-back reports
the same deployed digest. Journal and evidence writes are append-only --
a re-run never rewrites history, it adds to it.
