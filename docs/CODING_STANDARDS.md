# Coding standards

How code in Thaw 3 is written. The [contribution guidelines](https://github.com/thaw-app/.github/blob/main/.github/CONTRIBUTING.md) cover issues, pull requests and sign-off, and [Development](DEVELOPMENT.md) has the build and test commands.

## Where new code goes

[Architecture](ARCHITECTURE.md) maps the app, the packages and what each may depend on.

A handful of types do too much, and we are breaking them up:

| Type | What it does today |
|---|---|
| `MenuBarItemManager` | The worst one, split over many extension files that share one pool of state: item cache, moves, section order, repair, startup, persistence, clicks, failure tracking |
| `MenuBarItemImageCache` | Captures and caches item images, schedules recaptures, and also reveals hidden items to capture them |
| `MenuBarManager` | Showing and hiding sections, rehide timers, app-menu hiding, profile application, overlay state |
| `HIDEventManager` | Every input path: click, hover, scroll, drag, Clock and Notification Center taps |
| `ControlItem` | The status item, its look, its recovery and its length changes |
| `ProfileManager` | Stores profiles, switches them by display, Space or Focus, applies layout and spacing |

Don't give these types new responsibilities. A stored property and a few forwarding calls to plug in an extracted module are fine. If a bug fix has to change one of them in place, keep it small and say why in the pull request.

New behavior goes, in this order of preference:

1. Into an existing focused module, when the responsibility fits there.
2. Into a new type that owns the behavior and its state, behind a small interface.

A wrapper that only forwards calls doesn't help. Moving a method out while its state stays behind leaves the big type just as big.

`AppState` is small but works as a service locator: almost everything reaches through `appState.menuBarManager`, `appState.itemManager` or `appState.settings`. Pass a new type the dependencies it needs instead of adding another reach through `AppState`.

Some large files are fine as they are, so don't split them for the sake of it: `MenuBarItemAXProvider` and `SettingsURIHandler` (both stateless), `MenuBarOverlayPanel.swift` (several views in one file), `LayoutBarPaddingView` and `SearchIndex`.

## Keep decisions in pure functions

Keep decision logic in pure functions that take values and return values: which section an item belongs in, whether a move is needed, what order to write. The code that talks to the menu bar, the window server or Accessibility then only gathers inputs and applies the result. This keeps the decisions testable without a live menu bar.

## Reuse before writing

- If you'd copy a block, pull it into a shared function.
- Before hand-rolling an ordered set, a deque, a debounce or merge of async streams, a timeout race or a lock, check what Swift and Apple already provide: `AsyncAlgorithms` (already a dependency), `Synchronization.Mutex`, `Observation` and `ContinuousClock`. Use those.
- Adding a new package is a bigger decision, because it changes `Package.resolved` and the dependency scan. Propose it in the issue or pull request and say what it replaces.
- Swapping in a library type must not change behavior. A lock that callers can cancel out of isn't a drop-in replacement for one they can't.

## Comments

Write comments as plain sentences. No headings, bold, bullet lists or tables inside code comments. Say why the code does something when the code can't show it, such as a macOS quirk or an ordering that matters. Don't narrate what the next line does.

## Writing

This covers documentation, the changelog, pull request descriptions and the text the app shows.

- Write for the person reading, in plain words. Say what they can do and what happens, and leave out how the code does it unless they need that.
- Use sentence case for headings, such as "Reset or uninstall".
- Don't use em dashes or en dashes. Use a period, a comma, a colon or parentheses.
- Refer to a person you don't know as they.
- Link to other files in the repository with relative links, such as `[Development](DEVELOPMENT.md)`.

## Tests

- Use Swift Testing (`@Test`, `#expect`). Don't add XCTest.
- Where the logic can be isolated, write the failing test first.
- Add tests for new behavior and a regression test for each bug fix when practical.
- Test a module through its interface, not its private helpers.
- New code needs at least 80% test coverage. See [SonarCloud](../AGENTS.md#sonarcloud) in AGENTS.md.
- Some code can only run against a live menu bar. Keep that glue thin, and say in the pull request what you checked by hand.

## Formatting and lint

Configuration lives in [`.swiftformat`](../.swiftformat) and [`.swiftlint.yml`](../.swiftlint.yml).

```sh
swiftformat .
sh scripts/lint.sh --strict
```

The file, function, type, complexity and nesting limits are on. Violations that were already there are kept in `.swiftlint.baseline`, so only new ones report. Don't add entries to the baseline to make room for new code, and don't disable rules or add suppressions to get a change through.
