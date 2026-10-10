# Developing Thaw

Contribution requirements, review expectations, and security reporting are in the shared [Thaw/Floe policies](https://github.com/thaw-app/.github).

## Requirements

- macOS 26 or 27.
- Xcode 26.3 or later. CI tests with Xcode 26.6 and 27.0.

Thaw 2.x ships for macOS 26; 3.0 ships for macOS 27.

## Build

```sh
open Thaw.xcodeproj
```

## Code style

Configuration lives in [`.swiftlint.yml`](../.swiftlint.yml) and [`.swiftformat`](../.swiftformat).

```sh
swiftformat .
swiftlint lint --strict
```

## Tests

Use Swift Testing (`@Test` and `#expect`), not XCTest. Tests live in `ThawTests` and package test targets.

```sh
xcodebuild test -project Thaw.xcodeproj -scheme Thaw -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```

## Project documentation

- [Architecture](ARCHITECTURE.md).
- [Assurance case](ASSURANCE_CASE.md).
- [Release verification](VERIFYING_RELEASES.md).
- [URI schemes](URI_SCHEMES.md).
- [Frequent issues](../FREQUENT_ISSUES.md).
