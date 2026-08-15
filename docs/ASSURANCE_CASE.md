# Thaw security assurance case

This document argues that Thaw’s [security requirements](../.github/SECURITY.md)
are met for its intended environment: a **local macOS menu bar utility** used by
a single interactive user on their own Mac.

Update it when trust boundaries or major features change. It supports OpenSSF
Best Practices documentation criteria (`assurance_case`, security requirements,
architecture). OpenSSF Silver **`test_statement_coverage80` is claimed** — see
§6.4 for the measurement and the exclusion set it rests on.

## 1. Security requirements (summary)

Users **can** expect:

1. Thaw runs locally; no Thaw account and no first-party tracking backend.
2. Privileged OS permissions (Accessibility, Screen Recording) are requested
   explicitly and used for menu-bar management features.
3. Automation that **mutates settings** via `thaw://` requires an explicit
   user-approved allowlist and matching code signature / Team ID.
4. Software updates are delivered over HTTPS and authenticated with Sparkle
   EdDSA; release builds are Developer ID–signed and notarized.
5. Security issues can be reported privately; maintainers aim to acknowledge
   within 48 hours.

Users **cannot** expect:

1. Protection against an attacker who already controls their unlocked Mac
   session or who has been granted the same TCC permissions.
2. A hardened multi-tenant server security model (Thaw is not a network service).
3. Security fixes for abandoned old releases (only the latest stable is
   supported).
4. That third-party menu bar apps themselves are trustworthy.

## 2. Threat model

### Assets

| Asset | Why it matters |
| --- | --- |
| Integrity of menu bar layout / visibility | Unexpected hide/show can disrupt status indicators and user trust |
| User preferences and profiles | Local configuration; automation abuse could change behavior |
| Diagnostic logs | May contain environment details if logging is enabled |
| Update channel | Compromised updates → arbitrary code as the user |
| TCC permissions held by Thaw | AX / screen capture are powerful on macOS |

### Adversaries / scenarios

| ID | Scenario | Likelihood | Impact |
| --- | --- | --- | --- |
| T1 | Malicious local app sends `thaw://` settings URLs | Medium | Config abuse, UX disruption |
| T2 | Supply-chain compromise of a SwiftPM dependency or CI | Low–Med | Code execution in Thaw |
| T3 | Tampered download / MITM on update feed | Low (HTTPS + signatures) | Code execution |
| T4 | Malicious crafted profile / defaults data | Low–Med | Crash or unexpected layout |
| T5 | Confused-deputy via Accessibility APIs | Inherent | Thaw can affect other apps’ status items by design |
| T6 | Untrusted network attacker remote to the Mac | Low | Limited: no open server socket by design |

Out of scope: physical access to unlocked Mac; bugs in macOS itself; compromise
of Apple’s notarization infrastructure.

## 3. Trust boundaries

```text
  Untrusted local apps / scripts          User (interactive)
           │                                     │
           │ thaw://                             │ UI / TCC prompts
           ▼                                     ▼
  ┌────────────────── Settings URI handler ──────────────────┐
  │  allowlist + Team ID check  │  boolean/enum/range checks │
  └──────────────────────────────┬───────────────────────────┘
                                 │
                                 ▼
                    Thaw.app (user privileges)
                                 │
              ┌──────────────────┼──────────────────┐
              ▼                  ▼                  ▼
     MenuBarItemService     macOS TCC / AX     Sparkle (HTTPS)
     MenuBarCaptureService  WindowServer       EdDSA verify
```

| Boundary | What crosses | Controls |
| --- | --- | --- |
| External URL → settings | `thaw://set` etc. | Allowlisted keys; range checks; sender whitelist + `SecCode` Team ID binding |
| App ↔ XPC helper | Codable requests | Fixed service names; limited request vocabulary; capture requests accept only menu-bar window IDs, validated bounds, and BGRA size limits; same-team peer requirement when signed |
| App ↔ network | Appcast / downloads | HTTPS; Sparkle EdDSA (`SUPublicEDKey`); Apple notarization on shipped builds |
| App ↔ OS | AX / capture | Explicit TCC; features degrade without grants |

## 4. Secure design principles (Saltzer & Schroeder)

| Principle | How Thaw applies it |
| --- | --- |
| **Economy of mechanism** | Small XPC protocols; URI settings limited to known keys |
| **Fail-safe defaults** | Settings URI mutation denied unless allowlisted; permissions off until user grants |
| **Complete mediation** | Each settings URI request re-checks whitelist + signature; numeric keys clamped to ranges |
| **Open design** | GPL-3.0; public repo; security policy and this assurance case |
| **Separation of privilege** | XPC helpers separated from UI (PID lookup vs recyclable SkyLight capture); release signing keys not on the public download host as long-lived plaintext |
| **Least privilege** | Requests only needed TCC rights; no root requirement for normal use |
| **Least common mechanism** | Per-user install; no shared multi-user daemon for core features |
| **Psychological acceptability** | Clear permission prompts; authorize dialog lists what automation can do |

## 5. Common implementation weaknesses countered

Mapped loosely to CWE / OWASP-style classes relevant to a desktop app:

| Weakness | Countermeasure |
| --- | --- |
| Memory corruption (CWE-119 etc.) | Primary implementation in Swift (memory-safe); limited bridging |
| Injection via URLs / settings | Allowlist of keys; typed parsers; range validation (`SettingsURIHandler`) |
| Broken access control for automation | User confirm + persistent whitelist + Team ID re-verify |
| Insecure update / delivery | HTTPS + Sparkle EdDSA + Developer ID + notarization |
| Hard-coded secrets in repo | Signing material in GitHub Actions secrets, not source |
| Dependency vulnerabilities | SPM lockfile; CI; Dependabot (`.github/dependabot.yml`) |
| Overly verbose public logging of secrets | Diagnostic logging is optional and local; avoid logging secrets |

Static analysis (SonarCloud) and SwiftLint run in CI to catch a subset of
defect classes before merge.

## 6. Residual risks

1. Accessibility by design can manipulate other apps’ menu bar items — users
   must trust Thaw similarly to other AX utilities.
2. Private/undocumented WindowServer interactions increase compatibility and
   maintenance risk across macOS versions. Offscreen icon capture uses SkyLight
   in `MenuBarCaptureService` rather than the UI process; the helper is recycled
   after a capture budget because each `SLWindowListCreateImageFromArray` call
   leaks a small dictionary in the caller. That contains growth in Thaw but does
   not remove the leak from the platform API.
3. Update delivery depends on a GitHub Pages path. The Sparkle appcast is
   served from a `github.io` origin, which does **not** redirect across a
   repository owner transfer, so builds released before the move to
   [`thaw-app`](https://github.com/thaw-app) (three owners: `stonerl`,
   `nightah`, `diazdesandi`) rely on the previous path continuing to serve the
   feed. Moving the appcast to a project-controlled domain is planned.
4. **OpenSSF Silver statement coverage (`test_statement_coverage80`) is Met,
   against a documented exclusion set.** Statement coverage for `thaw-app_Thaw`
   is **80.8%** over 9,960 measured lines, from 1,893 tests. The suite is
   entirely Swift Testing; the last XCTest file was migrated in this cycle.

   The measurement excludes code whose substance cannot execute in a headless
   CI run — WindowServer/CGS private APIs, Accessibility permissions, Carbon
   hotkey registration, live display and running-app state, NSWindow/NSPanel
   subclasses, SwiftUI view bodies, XPC wiring, and `@main` entry points. The
   set and the rule governing it are in `sonar-project.properties`, which
   requires that pure value types, algorithms, Codable models and parsing stay
   measured even under a UI-sounding path. Two files that buried both kinds of
   code (`MenuBarSection`, `MenuBarItem`) were split along that seam rather
   than excluded whole, so their logic still counts.

   There is still **no enforced 80% gate** in CI; the figure is measured per
   analysis and this claim should be re-checked when it moves. The residual
   gap is concentrated in `ProfileManager` (about 700 lines reachable only
   through a live `AppState`, which no test can currently construct) — that is
   a testability limit, not an untested-logic claim, and narrowing those
   entry points is the route to raising it further.

## 7. Evidence pointers

| Claim | Evidence |
| --- | --- |
| Private vuln reporting + response SLA | `.github/SECURITY.md` |
| URI allowlist + signature binding | `Thaw/Utilities/SettingsURIHandler.swift`, `docs/URI_SCHEMES.md` |
| Update authenticity | `SUFeedURL` / `SUPublicEDKey` in `Thaw/Resources/Info.plist`; Sparkle release actions |
| Architecture | `docs/ARCHITECTURE.md` |
| Automated analysis | `.github/workflows/ci.yml`, SonarCloud project `thaw-app_Thaw` |
| Test coverage (Silver `test_statement_coverage80` Met) | SonarCloud `coverage` measure; CI `coverage.xml` — **80.8% over 9,960 measured lines, 1,893 tests**; exclusion set and its governing rule in `sonar-project.properties` |
| Dependency monitoring | `.github/dependabot.yml` |

## Revision

| Date | Note |
| --- | --- |
| 2026-08-15 | Documented `MenuBarCaptureService`: same-team XPC, menu-bar-only window IDs, BGRA size limits, and helper recycle to contain the SkyLight dictionary leak |
| 2026-07-27 | Initial version from `development` for OpenSSF docs |
| 2026-07-27 | Deferred Silver coverage claim; measured ~44% |
| 2026-07-31 | Claimed Silver `test_statement_coverage80`; measured 80.8% after migrating the suite to Swift Testing and documenting the exclusion set. Corrected the SonarCloud project key to `thaw-app_Thaw` |
