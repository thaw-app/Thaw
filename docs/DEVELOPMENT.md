# Developing Thaw

Contribution requirements, review expectations, and security reporting are in the shared [Thaw/Floe policies](https://github.com/thaw-app/.github).

## Requirements

- macOS 27.
- Xcode 27 or later. CI tests with Xcode 27.0.

This branch is Thaw 3, for macOS 27. Thaw 2, for macOS 15 and 26, is on `legacy/thaw-2`.

## Build

```sh
./scripts/devrun.sh          # Release, installed as /Applications/Thaw Debug.app
./scripts/devrun.sh --debug  # Debug, for the debugger
```

Thaw Debug has its own bundle identifier (`com.stonerl.Thaw.debug`), so it runs next to a released Thaw with separate settings and permissions. Run it from /Applications: macOS 27 only treats a status item as Thaw's when the app is there, so a build run straight from Xcode's build folder loses its own icon when it hides items. `open Thaw.xcodeproj` is still the way to edit and debug the code.

## Code style

[Coding standards](CODING_STANDARDS.md) covers how code is written here. Configuration lives in [`.swiftlint.yml`](../.swiftlint.yml) and [`.swiftformat`](../.swiftformat).

```sh
swiftformat .
sh scripts/lint.sh --strict
```

## Tests

Use Swift Testing (`@Test` and `#expect`), not XCTest. Tests live in `ThawTests` and package test targets.

```sh
xcodebuild test -project Thaw.xcodeproj -scheme Thaw -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```

## Project documentation

- [Architecture](ARCHITECTURE.md).
- [Coding standards](CODING_STANDARDS.md).
- [Assurance case](ASSURANCE_CASE.md).
- [Release verification](VERIFYING_RELEASES.md).
- [URI schemes](URI_SCHEMES.md).
- [Frequent issues](../FREQUENT_ISSUES.md).
