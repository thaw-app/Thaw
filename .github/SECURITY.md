# Security Policy

Thank you for helping keep Thaw secure. We take the security of our users and
their data seriously.

## Supported Versions

Thaw is a macOS menu bar manager. We primarily support security updates for the
**latest stable release**. Please run the most recent version before submitting
a vulnerability report. Upgrade via [GitHub Releases](https://github.com/thaw-app/Thaw/releases),
Homebrew, or in-app Sparkle updates.

| Version | Supported          |
| ------- | ------------------ |
| Latest  | :white_check_mark: |
| Older   | :x:                |

## Support window (EOL)

Only the **latest stable** Thaw release is supported for security fixes and
compatibility work. Older releases are end-of-life when a newer stable ships:
we do not backport security patches to abandoned versions. Beta / alpha /
experimental (for example macOS 27 preview) channels are best-effort and may
lag or diverge from stable.

Users should upgrade via [GitHub Releases](https://github.com/thaw-app/Thaw/releases),
Homebrew (`thaw` / `thaw@beta`), or in-app Sparkle updates.

## Security requirements (what users can and cannot expect)

This section is the project’s security requirements statement for the software
Thaw produces.

### You can expect

- **Local-first:** Thaw does not require an account and does not operate a
  first-party tracking or analytics backend.
- **Explicit permissions:** Features that need Accessibility or Screen Recording
  ask via normal macOS TCC prompts and do not work without those grants.
- **Guarded automation:** Settings changes via `thaw://` require a
  user-approved application allowlist and matching code-signing Team ID. See
  [docs/URI_SCHEMES.md](../docs/URI_SCHEMES.md).
- **Authenticated updates:** Release builds are Developer ID–signed and
  notarized. In-app updates use HTTPS + Sparkle EdDSA. See
  [docs/VERIFYING_RELEASES.md](../docs/VERIFYING_RELEASES.md).
- **Coordinated disclosure:** Private reporting channel and a target
  acknowledgement window (below).

### You cannot expect

- Protection against attackers who already control your unlocked Mac session,
  or who share the same powerful TCC rights.
- Server-style multi-tenant isolation (Thaw is a single-user desktop app).
- Security maintenance of outdated releases.
- That third-party menu bar apps Thaw interacts with are themselves secure.

A longer argument (threat model, trust boundaries, design principles) lives in
[docs/ASSURANCE_CASE.md](../docs/ASSURANCE_CASE.md). Architecture overview:
[docs/ARCHITECTURE.md](../docs/ARCHITECTURE.md).

## Scope of Security Reports

**In scope**

- Privilege escalation (e.g. escaping intended privilege boundaries, unauthorized
  root access).
- Unauthorized access to local user data managed by the app.
- Execution of arbitrary code via malicious input, crafted configuration, or
  abused `thaw://` automation.
- Bypass of settings-URI allowlist / code-signature checks.
- Compromised or forgeable update paths attributable to Thaw’s release process.

**Generally out of scope**

- Crashes without a viable exploit path.
- Issues requiring physical access to an unlocked Mac.
- Issues solely in third-party macOS components or other apps, unless Thaw needs
  a specific mitigation.
- Social engineering of maintainers outside the product.

## Reporting a Vulnerability

Please **do not** report security vulnerabilities through public GitHub issues.

Use [GitHub Private Vulnerability Reporting](https://github.com/thaw-app/Thaw/security/advisories/new)
when enabled for this repository.

If private vulnerability reporting is unavailable, contact the Project Lead
privately via the email or contact method on their GitHub profile.

Include:

- A detailed description of the vulnerability.
- Steps to reproduce.
- Your macOS version and Thaw version.
- Potential impact.

## Vulnerability response process

1. **Acknowledge** the report within **48 hours** (best effort).
2. **Triage** severity, affected versions, and exploitability.
3. **Fix** on a private branch when needed; prepare a release for the latest
   supported line.
4. **Credit** reporters in the advisory / release notes unless they request
   anonymity ([OpenSSF vulnerability_report_credit](https://www.bestpractices.dev/)).
5. **Disclose** via GitHub Security Advisories (and CVE when appropriate) after
   a fix is available or per coordinated timing with the reporter.
6. Ask reporters to keep issues confidential until a mitigating release ships.

We aim to fix critical, exploitable issues promptly; timelines depend on
complexity and whether an OS update is also required.

## Dependency SCA policy

Thaw automatically evaluates every proposed change for known-vulnerable
dependencies and blocks merge when the policy is violated. This is the project’s
software composition analysis (SCA) gate (OpenSSF Baseline **OSPS-VM-05.03**).

### What is evaluated

On every pull request and on pushes to `development`, the **Dependency SCA**
workflow (`.github/workflows/dependency-sca.yml`) runs a
version-and-SHA256–pinned [OSV-Scanner](https://google.github.io/osv-scanner/)
binary (same digest-pin pattern as Syft in the release workflow) against the
checked-in Swift `Package.resolved`. Findings are also uploaded to GitHub code
scanning when permissions allow.

Dependabot continues to open update PRs; those PRs are subject to the same gate.

### Pass / fail thresholds

| Finding | Gate behavior |
| --- | --- |
| Any **unsuppressed** vulnerability reported by OSV-Scanner for scanned artifacts | **Fail**: required check `dependency-sca` must be green to merge into `development` |
| Vulnerability listed in `osv-scanner.toml` with a documented **reason** and **ignoreUntil** expiry | **Pass** (suppressed): treated as an accepted residual risk |

There is no severity carve-out for High/Critical only: if OSV reports it and it
is not suppressed, the change does not merge. Malicious or compromised
dependency indicators that surface as OSV/advisory hits are handled the same way
(block until upgraded or explicitly suppressed).

### Suppressions (non-exploitable / accepted risk)

Suppressions are **checked in** under `osv-scanner.toml` at the repository root
so they are reviewable in the same PR as the waiver:

```toml
[[IgnoredVulns]]
id = "GHSA-xxxx-xxxx-xxxx"
ignoreUntil = 2026-12-31
reason = "Not exploitable in Thaw: …"
```

Rules for maintainers:

1. Prefer upgrading or removing the dependency over suppressing.
2. Every suppression needs a **reason** tied to Thaw’s threat model (e.g. not
   reachable, unused feature, fix not yet published).
3. Every suppression needs **`ignoreUntil`** (YYYY-MM-DD) so waivers expire and
   get revisited. The `dependency-sca` workflow rejects entries missing `reason`
   or `ignoreUntil`.
4. Suppressions require the same human review as any other change (non-author
   approval on `development`).

### Related docs

- Contributor expectations: [CONTRIBUTING.md](CONTRIBUTING.md) (§ SCA / SAST)
- Release verification / provenance: [docs/VERIFYING_RELEASES.md](../docs/VERIFYING_RELEASES.md)

## Public vulnerability history

Published advisories (when any exist):  
https://github.com/thaw-app/Thaw/security/advisories

If there are no published advisories, that means none have been disclosed yet, not
that the project ignores reports.
