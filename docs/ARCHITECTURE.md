# Thaw architecture

A map of Thaw's main parts and where they trust each other, not an API
reference. It describes Thaw 3, on this branch. Thaw 2 is on `legacy/thaw-2`.

Thaw is a native macOS menu bar manager written in Swift with AppKit and
SwiftUI. It hides and shows menu bar items, finds them from the keyboard,
switches layouts with profiles and changes how the menu bar looks.

## Goals

- Keep the menu bar usable, hiding what people don't need and showing it on
  demand, without ever losing an item.
- Work only on the Mac: no accounts, no telemetry and no tracking server.
- When a `thaw://` link asks to change settings and Thaw can't confirm it is
  allowed, refuse it.
- Stay compatible with current macOS releases. Thaw 3, on this branch, targets macOS 27. Thaw 2, on `legacy/thaw-2`, targets macOS 15 and runs on 15 and 26.

## How the code is organized

Thaw doesn't follow a named pattern such as MVVM or Clean Architecture. The
code is arranged like this:

```text
SwiftUI / AppKit views
  → managers owned by AppState (@Observable)
    → pure planners and models (MenuBarModel, ThawLayout)
      → backend adapters (Thaw/MenuBar/Backends)
        → PlatformRuntimeKit, the helper processes, macOS
```

- Views read state straight from `@Observable` managers. There are no view
  models.
- `AppState` creates the long-lived managers (`MenuBarManager`,
  `MenuBarItemManager`, `ProfileManager`, `HIDEventManager` and others) and
  hands them to the rest of the app. Because almost everything reaches through
  it, new types should take the dependencies they need instead.
- Decisions, such as which section an item belongs in or what order to write,
  live in pure functions in `MenuBarModel` and `ThawLayout`, so they can be
  tested without a live menu bar.
- Calls into macOS go through protocols such as `MenuBarBackend`, implemented
  in `Thaw/MenuBar/Backends`. That keeps PlatformRuntimeKit's concrete types
  out of the managers.

A few types still do too much and are being broken up.
[Coding standards](CODING_STANDARDS.md#where-new-code-goes) lists them and says
where new code goes instead.

## Repository layout

| Path | What it holds | Depends on |
| --- | --- | --- |
| `Thaw/` | The app: menu bar logic, settings, panels, input, permissions | Everything below |
| `MenuBarModel/` | Menu bar items, sections, identity, move planning and the backend protocols | Nothing |
| `ThawLayout/` | The layout solver: saved section order, where new items go | `MenuBarModel` |
| `ThawCapture/` | Item image capture with ScreenCaptureKit, and the client for the capture service | `MenuBarModel`, `ThawConcurrency` |
| `ThawConcurrency/` | Timeouts and one-shot continuations | Nothing |
| `ThawAX/` | Accessibility reading: `ThawAXCore`, the `ThawAXHelper` process and its client | Nothing |
| `ThawExtras/` | `ThawExtraHelper`, stand-ins for Apple items Thaw hides (Focus, AirDrop and others) | Nothing |
| `ThawUI/` | Settings form and control components, with no knowledge of app state | CompactSlider |
| `ThawControls/` | Control Center controls that show hidden items or toggle Zen Mode | |
| `ThawCtl/` | A command-line tool that turns commands into `thaw://` URLs | |
| `MenuBarCaptureService/` | The XPC service that hosts capture | `ThawCapture` |
| `Shared/` | Accessibility helpers (`AXHelpers.swift`) | |
| `ThawTests/` | The Swift Testing suite run in CI | |
| `Fuzzing/` | libFuzzer targets; currently the `thaw://` settings URI parser | |
| `scripts/` | Lint, coverage and release helpers used by CI | |
| `docs/` | User and developer documentation | |
| `.github/` | CI, release, issue and pull request templates | |

The packages don't depend on the app, and only `ThawLayout` and `ThawCapture`
depend on other packages. Keep it that way: a package that needs app state is a
sign the code belongs in `Thaw/`. `ThawAX` and `ThawExtras` have no
dependencies at all, because their executables run on their own without an
rpath to load libraries from.

Outside packages are declared with Swift Package Manager and locked in
`Thaw.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`:
PlatformRuntimeKit (as the prebuilt `thaw-app/prk-bin`), Sparkle,
CompactSlider, Ifrit, swift-algorithms, swift-async-algorithms and
swift-subprocess.

### Inside `Thaw/`

| Folder | What it holds |
| --- | --- |
| `App/` | `AppDelegate`, `AppState`, App Intents, single-instance and quit handling |
| `Items/` | The item manager: reading, caching, moving, grouping, spacing and saving items |
| `MenuBar/` | Sections, the control items, appearance and backdrop, and the backends |
| `Environment/` | Reacting to display, Space and arrangement changes |
| `Input/` | Mouse and keyboard events, and hotkeys |
| `Panels/` | Search, the Thaw Bar, the Layout editor, the swap bar and other floating panels |
| `Settings/` | The settings model, profiles, the panes and settings search |
| `System/` | Permissions, updates, `thaw://` handling, script hooks and other system glue |
| `RecordingWatch/` | Noticing when the camera, microphone or screen recording is in use |
| `Onboarding/`, `UI/`, `Utilities/` | The first-run walkthrough, shared views and helpers |

## Runtime components

```text
┌──────────────────────────────────────────────────────────────┐
│                           Thaw.app                           │
│  AppDelegate / AppState and the managers                     │
│  PlatformRuntimeKit (linked in; hides items, reads the bar)  │
│      │ stdin/stdout      │ XPC                 │ launches     │
│      ▼                   ▼                     ▼              │
│  ThawAXHelper     MenuBarCaptureService   ThawExtraHelper     │
│  (Accessibility)  (capture; recycled)     (one app per        │
│                                            stand-in)          │
│  ThawControls (Control Center controls), ThawCtl (CLI)        │
└──────────────────────────────────────────────────────────────┘
          │                          │
          ▼                          ▼
   macOS MenuBarAgent,          HTTPS appcast
   WindowServer, Accessibility  (Sparkle updates)
```

### How Thaw works with macOS 27's menu bar

On macOS 27 the menu bar is drawn by Apple's MenuBarAgent, and items have no
windows of their own to move. Thaw works with it in four ways.

- Hiding: PlatformRuntimeKit, a closed component, asks MenuBarAgent to hide
  an app's items. macOS hides by app, so all of one app's items hide together.
  With the Native hiding method, Thaw uses the per-app switches in System
  Settings instead. [Frequent issues](../FREQUENT_ISSUES.md#known-macos-27-limitations)
  lists what each method can't do.
- Order: macOS keeps the menu bar's order in one file. With Menu Bar Layout
  Access, the user picks that file and Thaw writes positions into it, so items
  move without the pointer moving. Writes go through a permit
  (`Thaw/MenuBar/Backends`). Where a write can't place an item, Thaw falls back
  to a synthetic ⌘-drag.
- Reading: `ThawAXHelper` reads the menu bar through Accessibility in its
  own process and answers the app over a pipe. MenuBarAgent's own window lists
  every visible item with the process that owns it (`MenuBarAgentWindow.swift`
  in `ThawAXCore`).
- Stand-ins: macOS hides by the bundle that owns an item, so each
  replacement for an Apple item comes from its own small app built from
  `ThawExtraHelper`.

### Capture: `MenuBarCaptureService`

An XPC helper (`com.stonerl.Thaw.MenuBarCaptureService`) produces the images
Thaw draws for menu bar items. It hosts the ScreenCaptureKit capture core from
`ThawCapture`, so a leak in SkyLight, which loses a dictionary on every call, grows
in the helper instead of the app. The app sends a typed
`CaptureServiceRequest` (window IDs, a display's menu bar hosting window or
strip, or an owner's bar window) and gets back a `CaptureServiceReply` with one
frame or a failure. The helper exits after 1,800 successful captures or when
the last client session closes, and a watchdog exits it when one capture
outlives its budget; XPC relaunches it on the next call. The dictionary leak is
separate from the Core Animation fence-port leak tracked as issue #933.

Backdrop composites also run in this helper, even when the legacy
`CaptureViaXPCService` flag is off. They borrow a one-shot capture ticket so
closing the panels does not stop the menu-bar backdrop. The helper rechecks
window levels and bounds: ordinary windows are admitted only within a display's
menu-bar strip, while larger captures admit only desktop-level windows. Failed
backdrop requests return no image, never an in-process SkyLight fallback.

## External interfaces

| Interface | Direction | Notes |
| --- | --- | --- |
| `thaw://` URL scheme | Inbound | Automation and deep links. Only allowlisted settings can be changed, and Thaw checks the sending app's signature. See [URI schemes](URI_SCHEMES.md) |
| Sparkle appcast HTTPS | Outbound | Update metadata and downloads over TLS |
| Accessibility and Screen Recording | System | Accessibility is required to move items; Screen Recording is optional and used for captures |
| Menu Bar Layout Access | System | The one file where macOS 27 keeps the menu bar's order, picked by the user |
| Crowdin | Outside the app | Translations, never at runtime |
| GitHub Releases and Homebrew | Distribution | Install and upgrade channels |

## Data and persistence

- Settings and profiles are kept in `UserDefaults` and in Thaw's Application Support folder, on the Mac only.
- Diagnostic logs are local files, off unless turned on in Settings → Advanced → Diagnostics. Thaw never uploads them.
- Thaw has no server of its own and no user accounts.

## Build and release

- To work on Thaw, open `Thaw.xcodeproj` in Xcode 27 or later and run it. See [Development](DEVELOPMENT.md).
- CI: `.github/workflows/ci.yml` runs SwiftLint, the tests and SonarCloud. Actions shared across the organization live in [`thaw-app/org-ci`](https://github.com/thaw-app/org-ci).
- Releases are signed with a Developer ID, notarized, packaged as ZIP and DMG, and added to the Sparkle appcast. See [VERIFYING_RELEASES.md](VERIFYING_RELEASES.md) and [RELEASES.md](RELEASES.md).
- The source of record is [thaw-app/Thaw](https://github.com/thaw-app/Thaw).

## Related organization repositories

Thaw also ships from these repositories, which matters when reviewing the
supply chain:

| Repository | Role |
| --- | --- |
| [thaw-app/Thaw](https://github.com/thaw-app/Thaw) | Application source, issues, DMG releases, CI |
| [thaw-app/updates](https://github.com/thaw-app/updates) | The Sparkle appcast, update archives and deltas |
| [thaw-app/brand-assets](https://github.com/thaw-app/brand-assets) | Shared brand artwork and README badges |
| [thaw-app/org-ci](https://github.com/thaw-app/org-ci) | Reusable GitHub Actions, such as the Sparkle release |
| [thaw-app/raycast-extension](https://github.com/thaw-app/raycast-extension) | Official Raycast extension |

## Related documents

- [Assurance case](ASSURANCE_CASE.md): the threat model and the security argument
- [URI schemes](URI_SCHEMES.md): every `thaw://` link
- [Security Policy](https://github.com/thaw-app/.github/blob/main/.github/SECURITY.md), shared with Floe: reporting, support and dependency rules
- [Governance](../.github/GOVERNANCE.md): project roles and the organization's repositories
