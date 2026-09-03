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
- Stay compatible with current macOS releases. The deployment target is macOS
  26; macOS 27 support is tracked in
  [#687](https://github.com/thaw-app/Thaw/issues/687).

## Repository layout

| Path | Role |
| --- | --- |
| `Thaw/` | Main application target (UI, menu bar logic, settings, events, permissions) |
| `Shared/` | Code shared between the app and helper processes (bridging, XPC client types, utilities) |
| `MenuBarItemService/` | XPC helper process that resolves menu bar item source PIDs off the main app |
| `MenuBarCaptureService/` | Recyclable XPC helper that runs SkyLight offscreen icon capture so the per-call dictionary leak stays out of the UI process |
| `ThawCtl/` | Small SwiftPM CLI / control utilities |
| `ThawTests/` | Swift Testing suite run in CI |
| `Fuzzing/` | SwiftPM libFuzzer targets; currently the `thaw://` settings URI parser |
| `scripts/` | Coverage, credits, and SwiftLint input helpers used by CI |
| `docs/` | User/developer documentation (e.g. URI schemes) |
| `.github/` | CI, release, contributing, security policy |

External dependencies are declared via Swift Package Manager and locked in
`Thaw.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`
(e.g. Sparkle, AXSwift, CompactSlider, Ifrit, LaunchAtLogin-Modern).

## Runtime components

```text
┌─────────────────────────────────────────────────────────────┐
│                           Thaw.app                          │
│  AppDelegate / AppState                                     │
│  ├── MenuBar (ItemManager, layout, IceBar/Thaw Bar, …)      │
│  ├── Events / Hotkeys / HID                                 │
│  ├── Triggers (condition monitors)                          │
│  ├── Settings + URI handler (thaw://)                       │
│  ├── Permissions (Accessibility, Screen Recording, …)       │
│  └── Updates (Sparkle)                                      │
│              │ XPC                    │ XPC                 │
│              ▼                        ▼                     │
│   MenuBarItemService.xpc      MenuBarCaptureService.xpc     │
│   (source PID resolution)     (offscreen capture; recycled) │
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
- **Triggers:** Condition monitors (power, network, Focus, schedule, and
  others) that reveal or hide an individual item. Everything except the
  battery and power conditions is off until enabled per condition from
  Developer settings.
- **Settings:** UserDefaults-backed configuration, profiles, onboarding.
- **Permissions:** Guides the user through TCC prompts required for AX and
  screen capture features.
- **Updates:** Sparkle client; feed URL and EdDSA public key live in
  `Thaw/Resources/Info.plist`.

### `MenuBarItemService` (XPC)

A separate process (`com.stonerl.Thaw.MenuBarItemService`) isolates
WindowServer and PID lookup work from the UI process. The shared protocol is a
small Codable request/response surface: `start`, `configureLogging`, and
`sourcePIDs`. Logging to a shared diagnostic file is configured by the main app
after launch.

### `MenuBarCaptureService` (XPC)

A second helper (`com.stonerl.Thaw.MenuBarCaptureService`) produces the images
Thaw draws for menu bar items. Its protocol adds `captureBatch` and `recycle`
to the same `start` and `configureLogging` pair. The app asks for one batch per
refresh rather than one call per window, and the helper exits once it has spent
its capture budget, which bounds the per-call leak in the underlying SkyLight
API to the helper's lifetime rather than the app's.

### `MenuBarCaptureService` (XPC)

A second Application XPC (`com.stonerl.Thaw.MenuBarCaptureService`) captures
offscreen Hidden / Always Hidden status-item windows via SkyLight. Each
successful `SLWindowListCreateImageFromArray` call leaks a small dictionary in
the caller; the helper exits after a capture budget (and when the last live
consumer closes) so that growth can be reclaimed. Requests carry a request ID
and window IDs only; the helper recomputes bounds, accepts only menu-bar item
windows, and returns cropped premultiplied-BGRA frames. Visible-section icons
stay on ScreenCaptureKit in the app. Always Hidden is capped at 1 fps;
Hidden follows the icon refresh slider. This dictionary leak is in the
capture caller (commit `0e045faf`); it is separate from the Core Animation
fence-port leak tracked as issue #933.

### External interfaces

| Interface | Direction | Notes |
| --- | --- | --- |
| `thaw://` URL scheme | Inbound | Automation / deep links; settings mutation is allowlisted + sender-signed; see [URI_SCHEMES.md](URI_SCHEMES.md) |
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
- **CI:** `.github/workflows/ci.yml` runs SwiftLint, `xcodebuild test`, and
  SonarCloud.
  Shared release/CI pieces live in [`thaw-app/org-ci`](https://github.com/thaw-app/org-ci).
- **Release:** Signed with Developer ID, notarized, packaged (ZIP/DMG), Sparkle
  appcast updated. See [VERIFYING_RELEASES.md](VERIFYING_RELEASES.md) and
  [RELEASES.md](RELEASES.md).
- **Hosting:** Canonical source is [thaw-app/Thaw](https://github.com/thaw-app/Thaw).

## Related organization repositories

Thaw’s product surface spans more than this git tree. Inventory for maintainers
and supply-chain review:

| Repository | Role |
| --- | --- |
| [thaw-app/Thaw](https://github.com/thaw-app/Thaw) | Application source, issues, DMG releases, CI |
| [thaw-app/updates](https://github.com/thaw-app/updates) | Sparkle appcast + update ZIP / deltas |
| [thaw-app/brand-assets](https://github.com/thaw-app/brand-assets) | Shared brand artwork and README badges |
| [thaw-app/org-ci](https://github.com/thaw-app/org-ci) | Reusable Actions (e.g. Sparkle release) |
| [thaw-app/raycast-extension](https://github.com/thaw-app/raycast-extension) | Official Raycast extension |

## Related documents

- [ASSURANCE_CASE.md](ASSURANCE_CASE.md): threat model and security argument
- [URI_SCHEMES.md](URI_SCHEMES.md): external URL/API surface
- [SECURITY.md](../.github/SECURITY.md): security requirements and reporting
- [GOVERNANCE.md](../.github/GOVERNANCE.md): project roles and org repo inventory
