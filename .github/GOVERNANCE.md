# Thaw project governance

This document describes how the Thaw project makes decisions, who holds which
roles, and how the project continues if a key person is unavailable.

## Decision model

Thaw is run by a **small lead team** with shared **organization admin** access.
Product, platform, and engineering each have a named lead; the three org owners
share continuity for secrets and org settings:

1. **Day-to-day:** Maintainers with write access review and merge pull requests
   to `development`, triage issues, and ship routine releases according to
   established CI/release workflows. Informal coordination and design discussion
   often happen in the project [Discord](https://discord.gg/5cnKkKbMFd) (same invite as the README); GitHub issues and pull requests remain the record for decisions that affect the codebase or releases.
2. **Domain ownership:** Leads decide within their domain (see [Roles](#roles-and-responsibilities)). Cross-cutting changes (roadmap, licensing, security policy, breaking product behavior) need agreement among the reachable leads; the **Project Lead** has final say when consensus fails.
3. **Consensus preferred:** Leads and maintainers seek rough consensus in issues/PRs (and Discord when useful) before escalating. Silence after a reasonable discussion window is treated as assent for non-breaking changes.
4. **Organization:** Shared project assets and CI building blocks live under the
   [`thaw-app`](https://github.com/thaw-app) GitHub organization. All three **org owners** can administer org settings and org-owned repositories if any one owner is unavailable. The application repository is
   [thaw-app/Thaw](https://github.com/thaw-app/Thaw) (see [Repository migration](#repository-migration)).
5. **Security:** Vulnerability handling follows [SECURITY.md](SECURITY.md). Public discussion of unfixed vulnerabilities is not appropriate.

Forking remains always available under the GPL-3.0 license; governance here
only describes how *this* project operates.

## Roles and responsibilities

| Role                   | Who (GitHub)                                                 | Responsibilities                                             |
|------------------------|--------------------------------------------------------------|--------------------------------------------------------------|
| **Project Lead**       | [@stonerl](https://github.com/stonerl)                       | Original project owner; final product and roadmap decisions when leads disagree; primary app release authority; security advisory publishing; release-secret stewardship with the other org owners |
| **Platform Lead**      | [@diazdesandi](https://github.com/diazdesandi)               | CI/CD and release engineering (signing, notarization, packaging, Sparkle/updates, `org-ci`); quality systems and QA; developer experience and maintainer operations; org/supply-chain work (OpenSSF, brand assets); ecosystem integrations and localization support. Primary steward of org-level repos; app releases stay with the Project Lead unless delegated |
| **Development Lead**   | [@nightah](https://github.com/nightah)                       | Engineering leadership for application code direction, review standards, and technical architecture |
| **Organization owner** | [@stonerl](https://github.com/stonerl), [@nightah](https://github.com/nightah), [@diazdesandi](https://github.com/diazdesandi) | Admin of [`thaw-app`](https://github.com/thaw-app): org settings, membership, org-owned repos/assets; **continuity access** to release secrets and Environments under least privilege (see [Release secrets](#release-secrets)). The three leads above are the org owners |
| **Maintainer**         | Write collaborators on [thaw-app/Thaw](https://github.com/thaw-app/Thaw) (including the leads) | Review/merge PRs; triage issues; approve routine releases when delegated; enforce Code of Conduct with the leads. **No** routine access to signing/notarization/Sparkle private keys unless also an org owner |
| **Contributor**        | Anyone submitting issues, PRs, Crowdin translations, or docs | Follow [CONTRIBUTING.md](CONTRIBUTING.md) and the [Code of Conduct](CODE_OF_CONDUCT.md) |
| **Security contact**   | Project Lead (via [private vulnerability reporting](https://github.com/thaw-app/Thaw/security/advisories/new)); other leads may acknowledge and escalate | Acknowledge and coordinate vulnerability reports |

Translations are reviewed via [Crowdin](https://crowdin.com/project/thaw), not via translation PRs.

### Coverage when a lead is unavailable

Lead titles describe primary focus, not exclusive ownership. If any lead is away,
slow to respond, or otherwise unavailable, **any other lead** (and, for routine
work, any maintainer with write access) may step in: answer questions, review
PRs, triage issues, run platform or release tasks they are authorized for, and
keep the project moving. Prefer the domain lead when they are reachable; do not
block on them. Cross-cutting or disputed calls still follow the decision model
above (consensus among reachable leads; Project Lead as final say).

## Community channels

| Channel | Purpose |
| --- | --- |
| [GitHub Issues / PRs](https://github.com/thaw-app/Thaw) | Bugs, features, code review, durable decisions |
| [Discord](https://discord.gg/5cnKkKbMFd) | Day-to-day maintainer and community discussion |
| [Crowdin](https://crowdin.com/project/thaw) | Localization |

## Members with repository access

### `thaw-app` organization (admins / owners)

| GitHub login  | Org role | Lead role        |
|---------------|----------|------------------|
| `stonerl`     | Owner    | Project Lead     |
| `diazdesandi` | Owner    | Platform Lead    |
| `nightah`     | Owner    | Development Lead |

Org profile: https://github.com/thaw-app

All three owners are **organization admins** for continuity. Lead titles describe
primary responsibility, not a separate GitHub permission tier and not a gate that
blocks other leads from helping (see [Coverage when a lead is unavailable](#coverage-when-a-lead-is-unavailable)).

### Application repository

| Location | Status |
| --- | --- |
| [thaw-app/Thaw](https://github.com/thaw-app/Thaw) | Canonical app source, issues, releases, CI |

### Related organization repositories

These repos are part of the Thaw product / supply chain but are not the
application source tree. The **Platform Lead** is the primary steward for
org-level and integration repos; the **Project Lead** remains primary for
application releases from `thaw-app/Thaw`.

| Repository | Role |
| --- | --- |
| [thaw-app/updates](https://github.com/thaw-app/updates) | Sparkle appcast (GitHub Pages) and update ZIP / delta assets |
| [thaw-app/brand-assets](https://github.com/thaw-app/brand-assets) | Shared logos, headers, badges |
| [thaw-app/org-ci](https://github.com/thaw-app/org-ci) | Shared GitHub Actions used by app release/CI |
| [thaw-app/raycast-extension](https://github.com/thaw-app/raycast-extension) | Official Raycast extension (`thaw://` client) |

Write access on `thaw-app/Thaw` alone does **not** include release-secret administration. Additional write collaborators beyond the three leads may be granted at the leads’ discretion.

Public contributor history:
https://github.com/thaw-app/Thaw/graphs/contributors

## Release secrets

Credentials used to ship signed builds (Apple Developer ID certificate material,
notarization credentials, Sparkle EdDSA **private** key, and related CI tokens)
are treated as **release secrets**. They are injected only via GitHub Actions
Secrets / Environments, never committed to git.

### Who may access what (least privilege)

| Access | Who | Purpose |
| --- | --- | --- |
| **View / edit release secrets** | Organization owners (`stonerl`, `nightah`, `diazdesandi`), scoped to the repo or org secret store that holds them | Continuity: any one owner unavailable must not block a hotfix |
| **Dispatch `release.yml`** | Anyone with permission to run `workflow_dispatch` on this repo. Policy: Project Lead by default; Platform Lead for platform/update-path releases or when delegated; other org owners when delegated for a specific release | Start a release or dry-run workflow run |
| **Approve / consume release secrets in CI** | Required reviewer on the GitHub **`release` Environment**: `diazdesandi`. The release job sets `environment: release`, so signing and publication steps do not run, and secrets are not injected into that job, until that reviewer approves. Other org owners (`stonerl`, `nightah`) are not listed as reviewers (avoids approval spam) but may still unblock via Environment **admin bypass** when needed | Cut signed/notarized builds and publish update assets |
| **Write collaborators / contributors** | Everyone else with repo write | Code and docs only: no secret read; cannot approve the `release` Environment |

Prefer **org-owned** secrets under [`thaw-app`](https://github.com/thaw-app) so admin
is not tied to one personal account. Add a second Environment reviewer only when
you intentionally want two-person approval (and accept the extra notifications).

### Approval path

1. Routine application releases: Project Lead (or Platform Lead / delegated org
   owner) starts the release workflow; the `release` Environment requires
   approval from the designated reviewer before the job runs.
2. Secret create / rotate / delete: proposed by an org owner; a **second** org
   owner confirms out-of-band (Discord or GitHub) before the change is applied,
   except true emergencies (compromised key) where one owner may rotate
   immediately and must notify the others within 24 hours.
3. Granting a new person secret access requires unanimous agreement of the
   current org owners and an update to this document.

### Audit and logging

- Prefer GitHub’s built-in audit log / Actions run history for who approved
  Environment jobs and which workflow run used secrets (values are never logged).
- Record secret rotations (what rotated, by whom, when) in a private maintainer
  note or closed tracking issue, not in public issues with secret material.
- Do not print secret values in workflow logs.

### Rotation

- Rotate after known or suspected compromise immediately.
- Rotate when an owner leaves the project or loses devices used for 2FA.
- Periodic rotation of long-lived credentials is encouraged (at least annually
  for notarization app-specific passwords / similar); Apple certificates follow
  Apple’s expiry and re-issuance cycle.
- After rotation, update GitHub Secrets, confirm a dry-run or staging release
  path still works, then ship.

### Recovery and continuity

If any one lead is unavailable, the remaining org owners must be able to:

1. Access the secret store (org/repo Secrets and/or Environment).
2. Approve or run the release workflow.
3. Publish the Sparkle appcast / GitHub Release artifacts.
4. Administer `thaw-app` org settings and related repos.

Recovery of lost Apple account access follows Apple’s account recovery; Sparkle
key recovery requires the offline backup held by org owners (password manager or
equivalent). At least **two** owners must be able to recover signing material
without the third.

Document the private backup location among owners only, never in this repo.

## Repository migration

Thaw now lives in the [`thaw-app`](https://github.com/thaw-app) organization.
Migration was **intentional and incremental**: shared assets moved first, and
the application repository transferred once release and signing wiring was
stable.

Now under or consumed via `thaw-app`:

- Brand / marketing assets
- Shared CI building blocks used by release workflows
- Application git history, issues, Discussions, and GitHub Releases
- Release signing / notarization wiring and Sparkle appcast publish path

Rules that continue to apply:

1. Keep a single canonical app repository at any time (no long-lived dual
   masters).
2. Prefer **org-owned** secrets, assets, and Environments over personally owned
   equivalents, so admin is never tied to one account.
3. Org owners (`stonerl`, `nightah`, `diazdesandi`) jointly decide any future
   moves.

### Lessons from the transfer

GitHub’s repository redirect preserves old `github.com` links, but that
redirect is not a substitute for updating references, and it does **not** cover
everything:

- **GitHub Pages does not redirect across an owner transfer.** The Sparkle
  appcast published to Pages changed origin, which broke update checks for
  already-installed builds until the old path was served again. Any future move
  must treat the appcast URL as a blocking migration step, and the feed should
  live on a project-controlled domain rather than a `github.io` path.
- **Release asset URLs embedded in a published appcast** keep pointing at the
  old owner and survive only via the repository redirect. Rewrite them before
  reclaiming the old namespace.
- Update Homebrew, the Sparkle feed, and docs in the same release window as any
  move.

## Access continuity

The project MUST be able to continue with minimal interruption if any one
person is unavailable (illness, departure, etc.). Within about one week the
remaining maintainers should still be able to:

- Create and close issues
- Accept pull requests
- Cut a release (or publish a hotfix)
- Administer `thaw-app` org-owned assets

### Continuity measures

1. **Organization owners:** Three people (`stonerl`, `diazdesandi`, `nightah`)
   are owners of [`thaw-app`](https://github.com/thaw-app). Loss of any one
   owner does not remove org admin capability. Continuity rests on the three
   org owners plus write collaborators on `thaw-app/Thaw`.
2. **Repository access:** Multiple maintainers have **write** access on the
   application repo so issues and PRs are not single-person blocked.
3. **Admin / secrets:** Follow [Release secrets](#release-secrets). All three
   org owners have continuity access under least privilege; write collaborators
   do not. Prefer org-level secrets and Environment approvals under `thaw-app`.
4. **Release tags:** Important release tags are GPG-signed by the releaser.
5. **Update feed / Pages:** The Sparkle appcast is published under
   [`thaw-app/updates`](https://github.com/thaw-app/updates) (GitHub Pages at
   `thaw-app.github.io/updates`). Continuity requires that at least one
   remaining owner can update that feed; relocating to a project-controlled
   domain remains desirable when practical. Already-installed legacy builds
   poll `stonerl.github.io/Thaw/appcast.xml`, which GitHub Pages does **not**
   redirect (see [Lessons from the transfer](#lessons-from-the-transfer)); the
   release workflow mirrors the same signed `appcast.xml` to `stonerl/Thaw`
   `main` to keep those installs updating. Continuity therefore also requires
   a working mirror token; see [RELEASES.md](../docs/RELEASES.md) under
   *Legacy installs*.

## Bus factor

Thaw aims for a **bus factor of 2 or more**: more than one person understands
menu-bar layout, release CI, and contributor workflow well enough to keep the
project moving.

Evidence:

- Three `thaw-app` organization owners with distinct lead roles (Project,
  Platform, Development)
- Multiple write collaborators on the application repo
- Active multi-author commit history on `development`
- Documented contribution and release automation under `.github/`
- Canonical app repo under the multi-owner org
- Active maintainer discussion on Discord in addition to GitHub
- Leads cover for each other when someone is unavailable

## Related documents

- [CONTRIBUTING.md](CONTRIBUTING.md)
- [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md)
- [SECURITY.md](SECURITY.md)
- [docs/ARCHITECTURE.md](../docs/ARCHITECTURE.md)
- [docs/ASSURANCE_CASE.md](../docs/ASSURANCE_CASE.md)
