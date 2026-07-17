# AGENTS.md

Guidance for AI agents and contributors working in this repository.

## Project

Thaw is a Swift 6.0 macOS menu bar management app, forked from Ice. It uses
SwiftUI, AppKit, and a small amount of Objective-C. The project is GPL-3.0.

Targets are macOS 26+. macOS 27 "Golden Gate" support is in development on the
`feat/macos-27-experimental` branch.

## Prerequisites

- Xcode 27+ on macOS 26+ (matches the `prk-bin` XCFramework toolchain).
- CI uses the `xcode-27` runner and pins `/Applications/Xcode_27.0.app`.
- `PlatformRuntimeKit` is a **public** binary Swift package
  (`thaw-app/prk-bin`, minimum **0.0.4** on `feat/macos-27-experimental`). Xcode resolves the XCFramework from
  GitHub Releases with no authentication. Local kit work: check out the private
  source repo as a sibling (`../PlatformRuntimeKit`), then open
  `ThawDev.xcworkspace` or run `./scripts/thaw-devrun.sh` (symlinks the sibling
  into `.swiftpm-overrides/prk-bin`). Without that sibling, `thaw-devrun.sh`
  falls back to `Thaw.xcodeproj` and the published packages. CI always uses the
  published binary. Alternately set `PRK_DEVELOPMENT=1` in the
  PlatformRuntimeKit repo.

## Menu Bar Packages

OS policy is split so macOS 26 can be retired without cluttering the app:

| Package | Path | Role |
|---------|------|------|
| `MenuBarModel` | `MenuBarModel/` | Shared domain + `MenuBarBackend` protocol/enums |
| `MenuBarHost` | `MenuBarHost/` | `HostMenuBarBackend` (host-native / spatial policy) |
| `PlatformRuntimeKit` | remote XCFramework | `RuntimeMenuBarBackend` + runtime controllers |

Thaw selects the backend via `MenuBarBackendProvider` in
`Thaw/MenuBar/Backends/`. The XCFramework dynamically links
`MenuBarModel` (shipped as a dynamic library product from this repo).

## Build And Test

Use this exact invocation for unsigned CI-style builds:

```bash
xcodebuild test -project Thaw.xcodeproj -scheme Thaw -derivedDataPath Build/ -destination 'platform=macOS' CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```

`CODE_SIGNING_ALLOWED=NO` is required for CI-style local builds.

## Lint And Format

SwiftLint must pass in strict mode, matching CI:

```bash
swiftlint --strict
```

CI runs SwiftLint with `ghcr.io/realm/swiftlint:0.63.3`. Config lives in
`.swiftlint.yml`.

Run SwiftFormat before committing:

```bash
swiftformat .
```

Config lives in `.swiftformat`.

## Code Conventions

- Swift files require the GPL header enforced by SwiftLint `file_header` and
  SwiftFormat `--header`:

```swift
//
//  <FILENAME>
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under GNU GPLv3
```

- Use 4-space indentation and no tabs.
- Keep trailing commas where SwiftFormat requires them.
- Use implicit `self` where possible; SwiftFormat removes unnecessary `self`.
- Use K&R braces.
- There is no line-length limit.
- Use conventional commit messages such as `fix(scope):`, `feat(scope):`,
  `test(scope):`, `docs(scope):`, or `chore(scope):`.

## Git Workflow

- Open pull requests against `stonerl/Thaw:development`, not `main`.
- Do not commit translations. They are managed through Crowdin.
- Do not push or open pull requests unless explicitly instructed.

## Agent Command Wrapping

This repository has RTK command-compression guidance in `.cursorrules`. When
`rtk` is installed, prefix shell commands with it, including each segment in a
command chain. For debugging, or when `rtk` is unavailable, use the raw command.

## macOS 27 Hiding Invariants

Before touching menu bar hiding code, preserve these invariants:

- `MenuBarSectionController.applyExperimentalWindowHiding` pass ordering is
  load-bearing: plist, then CGS, then AX, then position-lock. Reordering can
  regress the iStat ghosting fix.
- macOS 27 hiding paths must stay gated to macOS 27+. macOS 26 keeps native
  menu bar machinery; do not port 27-only behavior back to 26.
- Keep assignment hideability separate from physical reorderability. Some
  system items are assignment-only while MenuBarAgent items may be physically
  orderable.
- Hidden and Always Hidden reveal semantics are distinct. Do not use one
  section's temporary reveal behavior as a shortcut for the other.
- Capture paths should preserve display identity from the item cache when
  available, instead of recomputing the active menu bar display mid-capture.
- Masked backend work should prefer overlay concealment and avoid rewriting
  MenuBarAgent positions during reveal or hide cycles.

## Maintenance

Update this file when CI commands, SwiftLint version, copyright years, branch
targets, or macOS 27 hiding invariants change.
