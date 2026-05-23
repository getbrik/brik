# Security Policy

## Supported Versions

Only the latest minor release of Brik receives security updates. Older minors are not patched.

| Version | Supported |
|---|---|
| 0.5.x | Yes |
| < 0.5  | No  |

## Reporting a Vulnerability

If you discover a security vulnerability in Brik, please report it privately so we can address it before public disclosure.

Use GitHub's **Private Vulnerability Reporting**:

1. Go to https://github.com/getbrik/brik/security/advisories/new
2. Fill in the form with as much detail as possible: affected component, reproduction steps, impact, and any suggested mitigation.
3. We aim to acknowledge reports within 5 business days and to provide a remediation plan within 15 business days, depending on severity.

Do not open public issues for security reports.

## Scope

In scope:

- The Brik runtime (`bin/brik`, `lib/`, `shared-libs/`).
- The Brik runner images published from the `brik-images` repository (`ghcr.io/getbrik/brik-runner-*`).
- The Homebrew formula published in the `homebrew-tap` repository.

Out of scope:

- Vulnerabilities in third-party tools invoked by Brik stages (report upstream). Examples: Grype, Syft, Semgrep, Trivy, hadolint, dockle, cosign.
- Vulnerabilities specific to a CI/CD platform (GitLab, Jenkins, GitHub Actions) that Brik integrates with.
- Vulnerabilities in the demo lab (`briklab`) only reproducible against a development setup, not against a production deployment of Brik.

## Disclosure Policy

We follow a coordinated disclosure model. Once a fix is available and released, we will publish a GitHub Security Advisory (GHSA) describing the vulnerability, the affected versions, and the mitigation. Credit will be given to the reporter unless they request otherwise.

## Threat Model Notes

Brik runs as a CI/CD pipeline orchestrator. Its execution context is the CI runner (GitLab Runner, Jenkins agent, GitHub Actions runner, or local shell). The primary security boundary is the trust placed in:

1. The Brik runner images (signed with cosign, attested with SLSA provenance, scanned weekly).
2. The shared library wrappers (`shared-libs/gitlab/`, `shared-libs/jenkins/`, `shared-libs/local/`).
3. The `brik.yml` file declared by the project under CI.

Compromises to any of these three layers can lead to arbitrary code execution in the CI runner. Mitigations are documented in `brik/docs/security.md` (when present) and in the chantiers under `docs/chantiers/` related to image pinning and supply-chain hardening.
