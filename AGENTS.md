# AGENTS.md

Notes for AI coding agents and the people driving them. Read this before changing code.

Thaw 2 (macOS 26) lives on `development`. Thaw 3 (macOS 27) lives on `feat/thaw-3`. Open the PR against the branch for the line you changed. Where the two branches differ, this file says so.

## Don't add responsibilities to the big types

We are breaking up a handful of types that do too much. Bug fixes are still the priority, but no change should give these types more to do. This applies on both branches, and matters most on `feat/thaw-3`, where the breakup is happening.

| Type | What it does today |
|---|---|
| `MenuBarItemManager` | The worst one, split over many extension files that share one pool of state: item cache, moves, section order, repair, startup, persistence, clicks, failure tracking |
| `MenuBarItemImageCache` | Captures and caches item images, schedules recaptures, and also reveals hidden items to capture them |
| `MenuBarManager` | Showing and hiding sections, rehide timers, app-menu hiding, profile application, overlay state |
| `HIDEventManager` | Every input path: click, hover, scroll, drag, Clock and Notification Center taps |
| `ControlItem` | The status item, its look, its recovery and its length changes |
| `ProfileManager` | Stores profiles, switches them by display, Space or Focus, applies layout and spacing |

The rule: don't add new responsibilities to these types. A stored property and a few forwarding calls to plug in an extracted module are fine. If a bug fix has to change one of them in place, keep it small and say why in the PR.

Where new behavior goes:

1. Extend an existing focused module when the responsibility fits there.
2. Otherwise, extract the behavior together with the state it owns, behind a small interface.
3. Avoid wrappers that only forward calls. Moving a method out while its state stays behind doesn't make the big type any smaller.
4. Keep decision logic in pure functions that take values and return values, and test the module through its interface.

`AppState` is small but works as a service locator: almost everything reaches through `appState.menuBarManager`, `appState.itemManager` or `appState.settings`. Give a new type the dependencies it needs instead of adding another reach through `AppState`.

These are large but fine as they are, so don't split them for the sake of it: `MenuBarItemAXProvider` and `SettingsURIHandler` (stateless), `MenuBarOverlayPanel.swift` (several views in one file), `LayoutBarPaddingView` and `SearchIndex`.

## SonarCloud

New code needs at least 80% test coverage; that is the project's policy. The SonarCloud scan reports coverage along with duplicated code and new bugs, vulnerabilities and code smells, so keep those at zero on what you add.

CI skips the analysis for pull requests from forks and from Dependabot. A skipped Sonar check means nothing was analyzed, not that the change passed.

Don't add files to `sonar.coverage.exclusions` in `sonar-project.properties` to get under the bar. That list is for code that can only run against a live menu bar, and the PR has to say why a file belongs there.

Additional team conventions:

- Code comments are plain sentences: no headings, bold, bullet lists or tables.
- If you'd copy a block, pull it into a shared function instead.

## Lint

Lint locally, then let CI confirm. A green Xcode build is not proof that lint passed. Don't disable rules or add suppressions just to make a change pass.

On `development`:

- Run `swiftlint lint --strict`. CI runs the same.
- The Xcode build phase runs `swiftlint` without `--strict` and always marks itself done, so it doesn't reliably stop the build.
- When you add, delete or rename a Swift file in a linted directory, regenerate the input list with `bash scripts/generate-swiftlint-inputs.sh`. The script reads Git-tracked paths, so stage new files first. CI regenerates the list and fails if it differs from `scripts/swiftlint-inputs.xcfilelist`.

On `feat/thaw-3`:

- Run `sh scripts/lint.sh --strict`. It checks that the SwiftLint version matches `.swiftlint-version`, and CI runs the same.
- The file, function, type, complexity and nesting limits are on. Violations that were already there are kept in `.swiftlint.baseline`, so only new ones report. Don't add entries to the baseline to make room for new code.

## Tests and formatting

- Tests use Swift Testing (`@Test`, `#expect`). Don't add XCTest.
- Add automated tests for new behavior and regression tests for bug fixes when practical. If a change needs checking on a live menu bar, say what the automated tests can't cover and write down the manual checks you did.
- Ask before running checks that reset permissions or preferences, change the live menu bar layout, or quit other apps. Use separate test data instead of the user's own settings.
- Run `swiftformat .` before committing. See [Development](docs/DEVELOPMENT.md) for build and test commands.

## Commits and pull requests

The shared [contribution guidelines](https://github.com/thaw-app/.github/blob/main/.github/CONTRIBUTING.md) are the source of truth. In short:

1. **Sign off every commit** with `git commit -s`. The `Signed-off-by` trailer uses the contributor's real name and an email that matches the commit author. Never make up an identity; if Git's name or email isn't set, ask. Sign-off is not cryptographic signing (`-S`).
2. **Use and complete the [PR template](.github/pull_request_template.md)**, including when you open the PR with `gh`. Keep all its sections, and leave a checklist item unchecked when you didn't do it or it doesn't apply.
3. **Title the PR as a Conventional Commit,** such as `fix(layout): preserve item order`. Put `Closes: #123` on its own line, or `Closes: N/A` when there is no issue. Bug fixes and features from outside the team need an issue first.
4. **Agree on scope first.** Discuss features, substantial refactors and sensitive changes in an issue before writing them. Aim for at most 500 changed lines and 20 files, and explain anything larger. Write down the test commands you ran, their results, and the macOS versions you tested on.
5. **Translations go through [Crowdin](https://crowdin.com/project/thaw),** not translation PRs. Changing or adding the source strings a feature needs is fine.
6. **Review AI-generated changes before you submit them.** The contributor stays responsible for understanding the code, where it came from, its license compatibility and its tests.

## Reporting your work

- Keep each PR focused. Follow the issue-linking requirements above.
- User-facing changes get a line in [CHANGELOG.md](CHANGELOG.md), written for users, not for developers.
- Report the checks you actually ran and their results. Name any check you skipped or couldn't run.