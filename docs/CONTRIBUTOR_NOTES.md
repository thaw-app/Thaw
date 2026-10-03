# Contributing to Thaw

The [organization contribution policy](https://github.com/thaw-app/.github/blob/main/.github/CONTRIBUTING.md) covers review expectations, DCO sign-off, and AI-assisted work. These notes cover Thaw-specific requirements.

## Issues and pull requests

- Target `development`, not `main`, unless a maintainer asks otherwise.
- Find tasks in [Ways to contribute (#316)](https://github.com/thaw-app/Thaw/issues/316).
- Search the [issue tracker](https://github.com/thaw-app/Thaw/issues) and [Frequent Issues](../FREQUENT_ISSUES.md) before reporting bugs. Attach a crash log from Settings when relevant.
- Use the [pull request template](../.github/pull_request_template.md). Include `Closes: #123`, or `Closes: N/A` for agreed changes without an issue.

Thaw's PR Metadata check enforces DCO sign-off: every non-merge commit needs a `Signed-off-by` trailer matching the author email. Bot and automation commits are exempt. Use `git commit -s`; existing commits can be signed off with `git rebase --signoff`.

## Translations

Translate through [Crowdin](https://crowdin.com/project/thaw). Translation pull requests are not accepted; Crowdin keeps review and synchronization in one place.

## Building and code style

Requirements: macOS 26 or 27 and Xcode 26.3 or later. CI tests with Xcode 26.6 and 27.0. Thaw 2.x ships for macOS 26; 3.0 ships for macOS 27.

```sh
open Thaw.xcodeproj
swiftformat .
swiftlint lint --strict
```

Configuration lives in [`.swiftlint.yml`](../.swiftlint.yml) and [`.swiftformat`](../.swiftformat).

## Tests and review

Use Swift Testing (`@Test` and `#expect`), not XCTest. Add tests in `ThawTests` or the relevant package target for substantial new behavior, and regression tests for fixes when practical. If no useful test seam exists, discuss that with a maintainer.

```sh
xcodebuild test -project Thaw.xcodeproj -scheme Thaw -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```

Menu bar hiding and layout, the Thaw Bar, triggers, logging, and permissions receive deeper review. CodeRabbit and SonarCloud findings are part of the review requirements unless a maintainer marks them as not applicable or accepts the risk.

## Dependency and security checks

Dependency SCA runs on pull requests and `development` pushes. Fix findings or document a suppression in the root `osv-scanner.toml`; each suppression needs `reason` and `ignoreUntil`. See [security notes](SECURITY_NOTES.md#dependency-sca-policy) for thresholds and review requirements.

Dependabot changes must pass the same checks. Address CodeQL high/critical findings and new SonarCloud findings, or discuss false positives with maintainers. Do not merge with failing required checks.

## Project documentation

- [Governance](../.github/GOVERNANCE.md).
- [Architecture](ARCHITECTURE.md).
- [Security notes](SECURITY_NOTES.md).
- [URI schemes](URI_SCHEMES.md).
- [Code of Conduct](https://github.com/thaw-app/.github/blob/main/.github/CODE_OF_CONDUCT.md).
