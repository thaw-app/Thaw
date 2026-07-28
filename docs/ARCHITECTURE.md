# Thaw architecture

High-level design of the software produced by the Thaw project. This is a map
of major components and trust boundaries, not an API reference.

Thaw is a native **macOS menu bar manager** (Swift / AppKit / SwiftUI). It
hides and shows menu bar items, provides search and hotkeys, supports layout
profiles, and customizes menu bar appearance. It is a maintained fork of
[Ice](https://github.com/jordanbaird/Ice).

## Goals

- Keep the menu bar usable (hide clutter, reveal on demand) without surprising
  loss of status items.
- Prefer local-only operation: no accounts, no telemetry/tracking backend.
- Fail closed for privileged automation surfaces (`thaw://` settings APIs).
- Stay compatible with current macOS releases (26+; experimental 27 work on a
  feature branch).

## Repository layout

| Path | Role |
| --- | --- |
| `Thaw/` | Main application target (UI, menu bar logic, settings, events, permissions) |
| `Shared/` | Code shared between the app and helper processes (bridging, XPC client types, utilities) |
| `MenuBarItemService/` | XPC helper process for menu-bar item source PID resolution and related work off the main app |
| `ThawCtl/` | Small SwiftPM CLI / control utilities |
| `ThawTests/` | XCTest suite run in CI |
| `docs/` | User/developer documentation (e.g. URI schemes) |
| `.github/` | CI, release, contributing, security policy |

External dependencies are declared via Swift Package Manager and locked in
`Thaw.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`
(e.g. Sparkle, AXSwift, CompactSlider, Ifrit, LaunchAtLogin-Modern).

## Runtime components

```text
┌─────────────────────────────────────────────────────────────┐
│                        Thaw.app                             │
│  AppDelegate / AppState                                     │
│  ├── MenuBar (ItemManager, layout, IceBar/Thaw Bar, …)      │
│  ├── Events / Hotkeys / HID                                 │
│  ├── Settings + URI handler (thaw://)                       │
│  ├── Permissions (Accessibility, Screen Recording, …)       │
│  └── Updates (Sparkle)                                      │
│                         │ XPC                               │
│                         ▼                                   │
│              MenuBarItemService.xpc                         │
│              (source PID cache / listener)                  │
└─────────────────────────────────────────────────────────────┘
          │                         │
          ▼                         ▼
   macOS WindowServer /        HTTPS appcast
   Accessibility /             (Sparkle updates)
   private menu-bar APIs
```

### Main app (`Thaw/`)

- **MenuBar:** Enumerates and moves status items, maintains hidden /
  always-hidden sections, layout reconciliation, spacing, appearance overlay,
  and the Thaw Bar (IceBar) UI.
- **Events / Hotkeys:** User input paths that show or hide sections without
  going through the settings UI.
- **Settings:** UserDefaults-backed configuration, profiles, onboarding.
- **Permissions:** Guides the user through TCC prompts required for AX and
  screen capture features.
- **Updates:** Sparkle client; feed URL and EdDSA public key live in
  `Thaw/Resources/Info.plist`.

### `MenuBarItemService` (XPC)

A separate process (`com.stonerl.Thaw.MenuBarItemService`) isolates some
WindowServer / PID lookup work from the UI process. The shared protocol is a
small Codable request/response surface (`start`, `configureLogging`,
`sourcePID` / `sourcePIDs`). Logging to a shared diagnostic file is configured
by the main app after launch.

### External interfaces

| Interface | Direction | Notes |
| --- | --- | --- |
| `thaw://` URL scheme | Inbound | Automation / deep links; settings mutation is allowlisted + sender-signed — see [URI_SCHEMES.md](URI_SCHEMES.md) |
| Sparkle appcast HTTPS | Outbound | Update metadata and downloads over TLS |
| Accessibility / Screen Recording | System | Required for core menu-bar manipulation and capture |
| Crowdin | Out-of-band | Localization workflow (not runtime) |
| GitHub Releases / Homebrew | Distribution | Install and upgrade channels |

## Data and persistence

- Preferences and profiles: `UserDefaults` / app support files on the local Mac.
- Diagnostic logs: optional local files (General settings); not uploaded by Thaw.
- No first-party cloud backend; no user accounts.

## Build and release

- **Dev loop:** Open `Thaw.xcodeproj` in Xcode 26+, build/run.
- **CI:** `.github/workflows/ci.yml` — SwiftLint, `xcodebuild test`, SonarCloud.
  Shared release/CI pieces are gradually moving into the
  [`thaw-app`](https://github.com/thaw-app) org.
- **Release:** Signed with Developer ID, notarized, packaged (ZIP/DMG), Sparkle
  appcast updated. See [VERIFYING_RELEASES.md](VERIFYING_RELEASES.md).
- **Hosting:** Canonical source is [stonerl/Thaw](https://github.com/stonerl/Thaw)
  today; governance targets a later transfer into `thaw-app` once fragile
  release paths are stable (see [GOVERNANCE.md](../.github/GOVERNANCE.md)).

## Related documents

- [ASSURANCE_CASE.md](ASSURANCE_CASE.md) — threat model and security argument
- [URI_SCHEMES.md](URI_SCHEMES.md) — external URL/API surface
- [SECURITY.md](../.github/SECURITY.md) — security requirements and reporting
- [GOVERNANCE.md](../.github/GOVERNANCE.md) — project roles
