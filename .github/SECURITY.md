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

## Public vulnerability history

Published advisories (when any exist):  
https://github.com/thaw-app/Thaw/security/advisories

If there are no published advisories, that means none have been disclosed yet—not
that the project ignores reports.
