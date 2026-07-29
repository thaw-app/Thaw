# Thaw project governance

This document describes how the Thaw project makes decisions, who holds which
roles, and how the project continues if a key person is unavailable.

## Decision model

Thaw uses a **benevolent dictator / project-lead** model suitable for a small
maintainer team, backed by shared **organization admin** access:

1. **Day-to-day:** Maintainers with write access review and merge pull requests
   to `development`, triage issues, and ship routine releases according to
   established CI/release workflows. Informal coordination and design discussion
   often happen in the project [Discord](https://discord.gg/5cnKkKbMFd) (same
   invite as the README); GitHub issues and pull requests remain the record for
   decisions that affect the codebase or releases.
2. **Disputes and final decisions:** The **Project Lead** has final say on
   roadmap direction, breaking changes, security policy, licensing, and
   application-repository settings for [thaw-app/Thaw](https://github.com/thaw-app/Thaw).
3. **Consensus preferred:** Maintainers seek rough consensus in issues/PRs
   (and Discord when useful) before the Project Lead decides. Silence after a
   reasonable discussion window is treated as assent for non-breaking changes.
4. **Organization:** Shared project assets and CI building blocks already live
   under the [`thaw-app`](https://github.com/thaw-app) GitHub organization. Org
   **owners** can administer org settings and org-owned repositories if any one
   owner is unavailable. The application repository lives in the organization at
   [thaw-app/Thaw](https://github.com/thaw-app/Thaw) (see
   [Repository migration](#repository-migration)).
5. **Security:** Vulnerability handling follows
   [SECURITY.md](SECURITY.md). Public discussion of unfixed vulnerabilities is
   not appropriate.

Forking remains always available under the GPL-3.0 license; governance here
only describes how *this* project operates.

## Roles and responsibilities

| Role | Who (GitHub) | Responsibilities |
| --- | --- | --- |
| **Project Lead** | [@stonerl](https://github.com/stonerl) | Final product decisions; primary release authority for Thaw; app-repo admin; OpenSSF badge entry; security advisory publishing; release-secret stewardship (see below) |
| **Organization owner** | [@stonerl](https://github.com/stonerl), [@nightah](https://github.com/nightah), [@diazdesandi](https://github.com/diazdesandi) | Admin of [`thaw-app`](https://github.com/thaw-app): org settings, org-owned repos/assets (brand assets, shared CI, etc.), membership; home of the application repo; **continuity access** to release secrets and Environments under least privilege (see [Release secrets](#release-secrets)) |
| **Maintainer** | Write collaborators on the application repo ([thaw-app/Thaw](https://github.com/thaw-app/Thaw)) | Review/merge PRs; triage issues; approve routine releases when delegated; enforce Code of Conduct with Lead. **No** routine access to signing/notarization/Sparkle private keys |
| **Contributor** | Anyone submitting issues, PRs, Crowdin translations, or docs | Follow [CONTRIBUTING.md](CONTRIBUTING.md) and the [Code of Conduct](CODE_OF_CONDUCT.md) |
| **Security contact** | Project Lead (via [private vulnerability reporting](https://github.com/thaw-app/Thaw/security/advisories/new)) | Acknowledge and coordinate vulnerability reports |

Translations are reviewed via [Crowdin](https://crowdin.com/project/thaw), not
via translation PRs.

## Community channels

| Channel | Purpose |
| --- | --- |
| [GitHub Issues / PRs](https://github.com/thaw-app/Thaw) | Bugs, features, code review, durable decisions |
| [Discord](https://discord.gg/5cnKkKbMFd) | Day-to-day maintainer and community discussion |
| [Crowdin](https://crowdin.com/project/thaw) | Localization |

## Members with repository access

### `thaw-app` organization (admins / owners)

| GitHub login | Org role | Notes |
| --- | --- | --- |
| `stonerl` | Owner | Project Lead |
| `nightah` | Owner | Maintainer |
| `diazdesandi` | Owner | Maintainer |

Org profile: https://github.com/thaw-app

### Application repository

| Location | Status |
| --- | --- |
| [thaw-app/Thaw](https://github.com/thaw-app/Thaw) | Canonical app source, issues, releases, CI |

Write collaborators (in addition to the Project Lead) include maintainers such
as `nightah`, `diazdesandi`, and others granted write on the repo. Write access
alone does **not** include release-secret administration.

Public contributor history:
https://github.com/thaw-app/Thaw/graphs/contributors

## Release secrets

Credentials used to ship signed builds (Apple Developer ID certificate material,
notarization credentials, Sparkle EdDSA **private** key, and related CI tokens)
are treated as **release secrets**. They are injected only via GitHub Actions
Secrets / Environments — never committed to git.

### Who may access what (least privilege)

| Access | Who | Purpose |
| --- | --- | --- |
| **View / edit release secrets** | Organization owners (`stonerl`, `nightah`, `diazdesandi`), scoped to the repo or org secret store that holds them | Continuity: any one owner unavailable must not block a hotfix |
| **Trigger release workflows that consume secrets** | Project Lead by default; other org owners when delegated for a specific release | Cut signed/notarized builds |
| **Write collaborators / contributors** | Everyone else with repo write | Code and docs only — no secret read |

Prefer GitHub **Environments** (e.g. `release`) with required reviewers so
secret-consuming jobs need an org-owner approval. Prefer **org-owned** secrets
under [`thaw-app`](https://github.com/thaw-app) as migration progresses so
admin is not tied to one personal account.

### Approval path

1. Routine releases: Project Lead (or delegated org owner) starts the release
   workflow; Environment protection rules require approval from an org owner
   when configured.
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
  note or closed tracking issue — not in public issues with secret material.
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

If the Project Lead is unavailable, the remaining org owners must be able to:

1. Access the secret store (org/repo Secrets and/or Environment).
2. Approve or run the release workflow.
3. Publish the Sparkle appcast / GitHub Release artifacts.

Recovery of lost Apple account access follows Apple’s account recovery; Sparkle
key recovery requires the offline backup held by org owners (password manager or
equivalent). At least **two** owners must be able to recover signing material
without the third.

Document the private backup location among owners only — never in this repo.

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

1. **Organization owners:** Three people (`stonerl`, `nightah`, `diazdesandi`)
   are owners of [`thaw-app`](https://github.com/thaw-app). Loss of any one
   owner does not remove org admin capability. With the app repo in the org,
   single-namespace risk is removed: continuity rests on the three org owners
   plus write collaborators on `thaw-app/Thaw`.
2. **Repository access:** Multiple maintainers have **write** access on the
   application repo so issues and PRs are not single-person blocked.
3. **Admin / secrets:** Follow [Release secrets](#release-secrets). All three
   org owners have continuity access under least privilege; write collaborators
   do not. Prefer org-level secrets and Environment approvals under `thaw-app`
   as migration progresses.
4. **Release tags:** Important release tags are GPG-signed by the releaser.
5. **Update feed / Pages:** The Sparkle appcast is published to GitHub Pages
   (`stonerl.github.io/Thaw`). Continuity requires that at least one remaining
   admin can update that feed or redeploy Pages; relocating the feed under
   org-owned hosting is part of the gradual migration when safe.

## Bus factor

Thaw aims for a **bus factor of 2 or more**: more than one person understands
menu-bar layout, release CI, and contributor workflow well enough to keep the
project moving.

Evidence:

- Three `thaw-app` organization owners
- Multiple write collaborators on the application repo
- Active multi-author commit history on `development`
- Documented contribution and release automation under `.github/`
- Explicit plan to house the canonical repo under the multi-owner org
- Active maintainer discussion on Discord in addition to GitHub

## Related documents

- [CONTRIBUTING.md](CONTRIBUTING.md)
- [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md)
- [SECURITY.md](SECURITY.md)
- [docs/ARCHITECTURE.md](../docs/ARCHITECTURE.md)
- [docs/ASSURANCE_CASE.md](../docs/ASSURANCE_CASE.md)
