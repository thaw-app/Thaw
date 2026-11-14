# Developing Thaw

Contribution requirements, review expectations, and security reporting are in the shared [Thaw/Floe policies](https://github.com/thaw-app/.github).

## Requirements

- macOS 27.
- Xcode 27 or later. CI tests with Xcode 27.0.

This branch is Thaw 3, for macOS 27. Thaw 2, for macOS 15 and 26, is on `legacy/thaw-2`.

## Setup

```sh
brew install actionlint
sh scripts/install-swiftlint.sh    # pinned versions, in ~/.local/bin
sh scripts/install-swiftformat.sh
```

The Xcode build runs SwiftLint, so its version must match `.swiftlint-version`. CI checks formatting with the SwiftFormat version in `.swiftformat-version`; other versions format differently, so `scripts/format.sh` refuses to run them.

Outside the Thaw team, `devrun.sh` retries with a local signature when team signing fails. We've confirmed that build compiles, but not how the running app behaves, including its permissions.

## Build

```sh
./scripts/devrun.sh           # Release, installed as /Applications/Thaw Debug.app
./scripts/devrun.sh --debug   # Debug, for the debugger
./scripts/devrun.sh --ad-hoc  # Sign locally without trying the team first
```

Thaw Debug has its own bundle identifier (`com.stonerl.Thaw.debug`), so it runs next to a released Thaw with separate settings and permissions. Run it from /Applications: macOS 27 only treats a status item as Thaw's when the app is there, so a build run straight from Xcode's build folder loses its own icon when it hides items. `open Thaw.xcodeproj` is still the way to edit and debug the code.

## Xcode previews

Open `Thaw.xcodeproj`, select the Thaw scheme with the Debug configuration, and open a file containing `#Preview`. Show Xcode's Canvas and resume the preview. Use the canvas appearance controls to check both light and dark mode. A preview builds the view without installing or launching Thaw Debug through `devrun.sh`.

### Views to start with

The rows in [Visibility](../Thaw/Settings/SettingsPanes/Visibility) can render without a live menu bar:

- `VisibilityTimingRows.swift`: hover delay, name delay, timed rehide delay and the swap-on-click switch.
- `RecordingAlertRows.swift`: recording-alert controls. Its screen picker reads the connected display names, but does not start recording detection or display an alert.

These previews use their own `VisibilitySettings` model and the `com.stonerl.Thaw.visibility-previews` preferences suite, which is cleared when a new preview model is created. Sliders and toggles can be tried without changing the app's saved settings. The model is not set up to receive app events, and no menu bar managers are started.

### Adding a preview

Keep the preview and its helpers inside `#if DEBUG`. Preview macros participate in compilation; the guard keeps preview code and fixtures out of Release builds.

A fresh settings model is not enough to isolate a preview: its property setters still write through `Defaults`. Redirect that store to a dedicated preview suite before creating or editing the model. If the view uses `@AppStorage`, also supply that suite with `.defaultAppStorage(store)`.

For example, a standalone preview for the hover-delay row is:

```swift
#if DEBUG
    #Preview("Hover delay") {
        let domain = "com.stonerl.Thaw.hover-preview"
        guard let store = UserDefaults(suiteName: domain) else {
            preconditionFailure("Could not create the preview preferences")
        }
        store.removePersistentDomain(forName: domain)
        Defaults.store = store
        let settings = VisibilitySettings()
        settings.showOnHover = true
        return ThawForm {
            ThawSection {
                HoverDelayRow(settings: settings)
            }
        }
        .defaultAppStorage(store)
        .frame(width: 680, height: 300)
    }
#endif
```

`Defaults.store` is process-wide. Change it only in a preview host or an isolated test, never as part of the running app's UI. The Visibility previews share the setup in their folder rather than repeating it for each row.

### Views that need more isolation

[AppDelegate](../Thaw/App/AppDelegate.swift) skips normal setup when Xcode sets `XCODE_RUNNING_FOR_PREVIEWS` or `XCODE_RUNNING_FOR_PLAYGROUNDS`. That protects the app startup path; a view's own tasks, managers and button actions can still have side effects.

A view that reads `@Environment(AppState.self)` needs that environment supplied explicitly. For example, `GeneralSettingsPane` includes login and icon rows that read it; constructing `GeneralSettings` alone does not supply it. Keep any preview AppState unstarted and inspect the view's tasks and actions before enabling interaction. Do not call `launch`, manager `performSetup` methods, real layout writes or `thaw://` actions merely to make a preview work. Use sample data and disabled or substituted actions for those dependencies.

Layout and Simple Mode preload captures from the live bar, so their pages need more isolation than a settings model and an environment value. Use the existing [offscreen settings tests](../ThawTests/Settings/SettingsPanes/SettingsPaneRenderTests.swift) as a guide to which pages can be rendered without starting the app. Live opening, hiding and item moves still need manual validation under the [agent workflow](../AGENTS.md#build-and-run).

## Code style

[Coding standards](CODING_STANDARDS.md) covers how code is written here. Configuration lives in [`.swiftlint.yml`](../.swiftlint.yml) and [`.swiftformat`](../.swiftformat).

```sh
sh scripts/format.sh
sh scripts/lint.sh --strict
```

## Tests

Use Swift Testing (`@Test` and `#expect`), not XCTest. Tests live in `ThawTests` and package test targets.

```sh
xcodebuild test -project Thaw.xcodeproj -scheme Thaw -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```

The app tests don't run a package's own test targets. To test a package you changed, name its folder:

```sh
swift test --package-path packages/ThawConcurrency
```

To run every package's tests, as CI does, use `sh scripts/test-packages.sh`. Name packages to run only those: `sh scripts/test-packages.sh ThawLayout ThawCapture`.

## Project documentation

- [Architecture](ARCHITECTURE.md).
- [Coding standards](CODING_STANDARDS.md).
- [Assurance case](ASSURANCE_CASE.md).
- [Release verification](VERIFYING_RELEASES.md).
- [URI schemes](URI_SCHEMES.md).
- [Frequent issues](../FREQUENT_ISSUES.md).
