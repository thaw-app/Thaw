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
   application-repository settings for [stonerl/Thaw](https://github.com/stonerl/Thaw).
3. **Consensus preferred:** Maintainers seek rough consensus in issues/PRs
   (and Discord when useful) before the Project Lead decides. Silence after a
   reasonable discussion window is treated as assent for non-breaking changes.
4. **Organization:** Shared project assets and CI building blocks already live
   under the [`thaw-app`](https://github.com/thaw-app) GitHub organization. Org
   **owners** can administer org settings and org-owned repositories if any one
   owner is unavailable. The application repository is still
   [stonerl/Thaw](https://github.com/stonerl/Thaw); migrating it into `thaw-app`
   is a **planned, gradual** move (see [Repository migration](#repository-migration)).
5. **Security:** Vulnerability handling follows
   [SECURITY.md](SECURITY.md). Public discussion of unfixed vulnerabilities is
   not appropriate.

Forking remains always available under the GPL-3.0 license; governance here
only describes how *this* project operates.

## Roles and responsibilities

| Role | Who (GitHub) | Responsibilities |
| --- | --- | --- |
| **Project Lead** | [@stonerl](https://github.com/stonerl) | Final product decisions; release authority for Thaw; app-repo admin (today under `stonerl/`); OpenSSF badge entry; security advisory publishing |
| **Organization owner** | [@stonerl](https://github.com/stonerl), [@nightah](https://github.com/nightah), [@diazdesandi](https://github.com/diazdesandi) | Admin of [`thaw-app`](https://github.com/thaw-app): org settings, org-owned repos/assets (brand assets, shared CI, etc.), membership; eventual home for the application repo |
| **Maintainer** | Write collaborators on the application repo (today [stonerl/Thaw](https://github.com/stonerl/Thaw); later under `thaw-app`) | Review/merge PRs; triage issues; approve routine releases when delegated; enforce Code of Conduct with Lead |
| **Contributor** | Anyone submitting issues, PRs, Crowdin translations, or docs | Follow [CONTRIBUTING.md](CONTRIBUTING.md) and the [Code of Conduct](CODE_OF_CONDUCT.md) |
| **Security contact** | Project Lead (via [private vulnerability reporting](https://github.com/stonerl/Thaw/security/advisories/new)) | Acknowledge and coordinate vulnerability reports |

Translations are reviewed via [Crowdin](https://crowdin.com/project/thaw), not
via translation PRs.

## Community channels

| Channel | Purpose |
| --- | --- |
| [GitHub Issues / PRs](https://github.com/stonerl/Thaw) | Bugs, features, code review, durable decisions |
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

### Application repository (current and target)

| Stage | Location | Status |
| --- | --- | --- |
| **Current** | [stonerl/Thaw](https://github.com/stonerl/Thaw) | Canonical app source, issues, releases, CI |
| **Target** | `thaw-app/Thaw` (name TBD) under [`thaw-app`](https://github.com/thaw-app) | Planned transfer when release/signing/Pages dependencies are stable enough |

Sensitive Actions secrets for Developer ID signing, notarization, and Sparkle
EdDSA updates are configured on the application repository and/or org as
applicable. Write collaborators (in addition to the Project Lead) include
maintainers such as `nightah`, `diazdesandi`, and others granted write on the
repo.

Public contributor history:
https://github.com/stonerl/Thaw/graphs/contributors

## Repository migration

The long-term home for Thaw is the [`thaw-app`](https://github.com/thaw-app)
organization. Migration is **intentional and incremental**: pieces move when
they are safe to move, not as a single cutover.

Already under or consumed via `thaw-app` (examples; list may grow):

- Brand / marketing assets
- Shared CI building blocks used by release workflows

Still on the personal namespace until transfer is low-risk:

- Application git history, issues, Discussions, and GitHub Releases
- Release signing / notarization wiring and Sparkle appcast publish path
- User-facing URLs (clone URL, badge links, Homebrew taps, docs) that must be
  redirected without breaking installs or updates

Guiding rules until the app repo lives in the org:

1. Prefer extracting **shared, non-fragile** pieces into `thaw-app` first.
2. Keep a single canonical app repository at any time (no long-lived dual
   masters).
3. After transfer, GitHub’s repository redirect should preserve old
   `stonerl/Thaw` links; update Homebrew, Sparkle feed, and docs in the same
   release window as the move.
4. Org owners (`stonerl`, `nightah`, `diazdesandi`) jointly decide when the app
   repo is ready to transfer.

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
   owner does not remove org admin capability. Migrating the app repo into the
   org further reduces single-namespace risk; until then, continuity relies on
   write collaborators on `stonerl/Thaw` plus the three org owners for shared
   assets and planning.
2. **Repository access:** Multiple maintainers have **write** access on the
   application repo so issues and PRs are not single-person blocked.
3. **Admin / secrets:** Release-signing and notarization credentials used by
   GitHub Actions are available to the Project Lead and, for continuity, to
   the other org owners as needed so a release can still be cut if one person
   is unavailable. As workflows move to org-owned reusable actions/secrets,
   prefer **org-level** secrets owned by `thaw-app` so all three owners share
   administrative access without depending on one personal account.
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
