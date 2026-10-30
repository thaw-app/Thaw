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
- Stay compatible with current macOS releases. Thaw 3, on this branch, targets macOS 27. Thaw 2, on `legacy/thaw-2`, runs on macOS 26. Thaw 2.2 adds macOS 15.

## How the code is organized

Thaw doesn't follow a named pattern such as MVVM or Clean Architecture. The
code is arranged like this:

```text
SwiftUI / AppKit views
  → managers owned by AppState
      ├─ pure planners and models (MenuBarModel, ThawLayout, app-local rules)
      └─ backend adapters and service clients
          → PlatformRuntimeKit, helper processes, macOS
```

The arrows show who calls whom. Managers gather observations, ask the pure
code for decisions, and apply those decisions through adapters. Pure planners
must not call the adapters or read app state.

- Views generally read state straight from `@Observable` managers. There is
  no required view-model layer.
- `AppState` creates the long-lived managers (`MenuBarManager`,
  `MenuBarItemManager`, `ProfileManager`, `HIDEventManager` and others) and
  hands them to the rest of the app. Because almost everything reaches through
  it, new types should take the dependencies they need instead.
- Decisions, such as which section an item belongs in or what order to write,
  live in pure functions in `MenuBarModel`, `ThawLayout` and app-local rule
  types, so they can be tested without a live menu bar.
- Protocols such as `MenuBarBackend` live in `MenuBarModel`.
  `Thaw/MenuBar/Backends` selects runtime implementations and wraps operations
  such as position-store writes. These boundaries limit coupling to
  PlatformRuntimeKit, but the separation is incomplete: some managers and
  system code still import it directly. Prefer the existing boundaries when
  adding behavior.

A few types still combine too many responsibilities.
[Coding standards](CODING_STANDARDS.md#where-new-code-goes) lists them and says
where new code goes instead.

## Repository layout

| Path | What it holds | Package dependencies |
| --- | --- | --- |
| `Thaw/` | The app: menu bar logic, settings, panels, input, permissions | Local libraries and external runtime/UI packages |
| `MenuBarModel/` | Menu bar items, sections, identity, move planning and the backend protocols | Nothing |
| `ThawLayout/` | The layout solver: saved section order, where new items go | `MenuBarModel` |
| `ThawCapture/` | Item image capture with ScreenCaptureKit, and the client for the capture service | `MenuBarModel`, `ThawConcurrency` |
| `ThawConcurrency/` | Timeouts and one-shot continuations | Nothing |
| `ThawAX/` | Accessibility reading: `ThawAXCore`, `ThawAXClient` and the `ThawAXHelper` process | No other package; client and helper use `ThawAXCore` |
| `ThawExtras/` | `ThawExtraHelper`, stand-ins for Apple items Thaw hides (Focus, AirDrop and others) | Nothing |
| `ThawUI/` | Settings form and control components, with no knowledge of app state | CompactSlider |
| `ThawControls/` | Control Center controls that show hidden items or toggle Zen Mode | |
| `ThawCtl/` | A command-line tool that turns commands into `thaw://` URLs | |
| `MenuBarCaptureService/` | The XPC service that hosts capture | `ThawCapture` |
| `Shared/` | Accessibility helpers (`AXHelpers.swift`) | |
| `ThawTests/` | App-level Swift Testing tests; packages also have their own test targets | App and library modules |
| `Fuzzing/` | libFuzzer targets; currently the `thaw://` settings URI parser | |
| `scripts/` | Lint, coverage and release helpers used by CI | |
| `docs/` | User and developer documentation | |
| `.github/` | CI, release, issue and pull request templates | |

The table lists package dependencies, not Apple frameworks or every Xcode
target relationship. `Package.swift` files and the Xcode project are the source
of truth for the build graph.

Local packages do not depend on the app. `ThawLayout` and `ThawCapture` depend
on other local packages; `ThawUI` uses the external CompactSlider package.
Keep app state out of packages. `ThawAX` and `ThawExtras` have no external
package dependencies. Helper packaging and library search paths matter:
`ThawAX` declares a static core product and an Xcode helper rpath in its
[manifest](../ThawAX/Package.swift).

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

### Where to start a change

| Concern | Entry points |
| --- | --- |
| Startup and subsystem lifetime | [`AppDelegate`](../Thaw/App/AppDelegate.swift), [`AppState`](../Thaw/App/AppState.swift) |
| Item inventory and cache | [`Items/Manager`](../Thaw/Items/Manager), [`Items/Model`](../Thaw/Items/Model) |
| Saved order and move planning | [`ThawLayout`](../ThawLayout/Sources/ThawLayout), [`LayoutMoveSequencePlanner`](../MenuBarModel/Sources/MenuBarModel/LayoutMoveSequencePlanner.swift) |
| Layout writes and automatic repair | [`RepairOrchestrator`](../Thaw/Items/Manager/RepairOrchestrator.swift), [`MenuBarPositionStoreProvider`](../Thaw/MenuBar/Backends/MenuBarPositionStoreProvider.swift) |
| Hide, reveal and section policy | [`MenuBarManager`](../Thaw/MenuBar/MenuBarManager.swift), [`RuntimeSectionContextAdapter`](../Thaw/MenuBar/RuntimeSectionContextAdapter.swift) |
| Item images | [`Items/Capture`](../Thaw/Items/Capture), [`ThawCapture`](../ThawCapture), [`MenuBarCaptureService`](../MenuBarCaptureService) |
| Display and Space changes | [`Environment`](../Thaw/Environment) |
| Settings and profiles | [`Settings/Models`](../Thaw/Settings/Models), [`Defaults`](../Thaw/System/Defaults.swift) |
| Automation and sender authorization | [`SettingsURIParser`](../Thaw/System/SettingsURIParser.swift), [`SettingsURIHandler`](../Thaw/System/SettingsURIHandler.swift), [`SettingsURISender`](../Thaw/System/SettingsURISender.swift) |

## Runtime components

PlatformRuntimeKit is linked into the app process. The helpers below run in
separate processes; being shipped inside the app bundle does not make them
in-process services.

| Component | Connection to the app | Responsibility |
| --- | --- | --- |
| `ThawAXHelper` | Standard input/output pipes through `ThawAXClient` | Accessibility observations |
| `MenuBarCaptureService` | XPC | Image capture in a recyclable process |
| `ThawExtraHelper` | Launched as separate stand-in apps | Apple-item replacements with separate owning bundles |
| Settings child process | Standard input/output pipes | Optional `SettingsInOwnProcess` mode; exits when its last window closes |
| `ThawControls` | Darwin notifications for commands, App Group snapshot for state | Control Center controls |
| `ThawCtl` | `thaw://` URLs | Command-line entry into app automation |

### Startup and ownership

`AppDelegate` owns `AppState`. The normal menu bar stack starts only after the
required permissions are available. `AppState.bootstrapTask` is a shared lazy
task, so callers wait for the same setup rather than starting it twice.
Settings and display state start before the menu bar stack, the item manager
starts before image capture, and observers are installed after setup.

Keep this ordering when changing startup. Creating a manager must not assume
that permission checks have passed or that its sibling managers are ready.
The reduced-permission mode and the optional settings child process have
separate startup paths; don't start the full menu bar stack in either just to
obtain a dependency.

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

### Layout writes

The position table is shared system state, not an ordinary app preference.
App code uses [`MenuBarPositionStoreProvider`](../Thaw/MenuBar/Backends/MenuBarPositionStoreProvider.swift),
which exposes a `PermittedPositionStore`. Its write methods require a
[`StoreWritePermit`](../Thaw/MenuBar/Backends/StoreWritePermit.swift).

- `RepairOrchestrator` schedules repair and layout work through `RepairLane`.
  Item moves can obtain a permit while holding the move semaphore.
- Manual arrangement selects `ReadOnlyPositionStore`. Explicit Layout edits
  use the scoped `forLayoutEdit` path; automatic repair must remain read-only.
- A permit records admission to a write path. It does not prove that an old
  plan is still valid after waiting. Callers must honor cancellation and the
  orchestrator's generation and interruption checks.
- `StoreWritePermit.unsequenced` exists for remaining unsequenced writers and
  does not serialize them. It is migration debt, not a shortcut for new code.

These rules prevent automatic repair from undoing a person's newer edit or
bypassing their choice of Manual arrangement. SwiftLint's
`store_write_needs_permit` rule checks direct store access outside the allowed
boundary.

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
| Sparkle appcast HTTPS | Outbound | Update metadata and downloads over TLS, controlled by update consent and settings |
| What's New HTTPS | Outbound | Release notes from `raw.githubusercontent.com`, controlled by the separate notes setting. See [Network access](NETWORK.md) |
| Accessibility and Screen Recording | System | Accessibility is required to move items; Screen Recording is optional and used for captures |
| Menu Bar Layout Access | System | The one file where macOS 27 keeps the menu bar's order, picked by the user |
| Crowdin | Outside the app | Translations, never at runtime |
| GitHub Releases and Homebrew | Distribution | Install and upgrade channels |

## Data and persistence

- Settings use `UserDefaults`; profiles also use Thaw's Application Support folder. Both stay on the Mac. `Defaults.Key` raw values and encoded profile fields are compatibility contracts, not names to change during cleanup.
- The system position table and Control Center's app visibility preferences are separate from Thaw's own settings. Access to one file does not grant access to the other.
- Diagnostic logs are local files. Release builds follow the saved logging setting; Debug builds enable logging during bootstrap. Thaw never uploads them.
- Thaw has no server of its own and no user accounts.

## Build and release

- Use Xcode to edit the project, and `scripts/devrun.sh` to build, install and launch Thaw Debug from `/Applications`. The script also stops an existing Thaw Debug. Ask before running it: separate app settings do not isolate the live menu bar. See [Development](DEVELOPMENT.md).
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

- [Agent workflow](../AGENTS.md): approvals, checks and reporting
- [Coding standards](CODING_STANDARDS.md): implementation, tests and writing
- [Development](DEVELOPMENT.md): build and test commands
- [Assurance case](ASSURANCE_CASE.md): the threat model and the security argument
- [URI schemes](URI_SCHEMES.md): every `thaw://` link
- [Security Policy](https://github.com/thaw-app/.github/blob/main/.github/SECURITY.md), shared with Floe: reporting, support and dependency rules
- [Governance](../.github/GOVERNANCE.md): project roles and the organization's repositories
