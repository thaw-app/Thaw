# Coding standards

How code in Thaw 3 is written. The [contribution guidelines](https://github.com/thaw-app/.github/blob/main/.github/CONTRIBUTING.md) cover issues, pull requests and sign-off, and [Development](DEVELOPMENT.md) has the build and test commands.

## Where new code goes

[Architecture](ARCHITECTURE.md) maps the app, the packages and what each may depend on.

A handful of types do too much, and we are breaking them up:

| Type | What it does today |
|---|---|
| `MenuBarItemManager` | Item cache, moves, section order, repair, startup, persistence, clicks and failure tracking, spread across extensions sharing state |
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

`AppState` owns the long-lived managers and also works as a service locator: much of the app reaches through `appState.menuBarManager`, `appState.itemManager` or `appState.settings`. Pass a new type the dependencies it needs instead of adding another dependency on `AppState`. A dependency can be a value, a closure or an existing protocol; don't add a protocol for every type.

File length alone is not a reason to split a type. A focused provider, a solver or several closely related views can belong in one file. Split when responsibilities or state lifetimes differ, not just to move lines elsewhere.

## Keep decisions in pure functions

Keep decision logic in pure functions that take values and return values: which section an item belongs in, whether a move is needed, what order to write. The code that talks to the menu bar, the window server or Accessibility then only gathers inputs and applies the result. This keeps the decisions testable without a live menu bar.

Put shared menu bar rules in `MenuBarModel`, saved-order solving in `ThawLayout`, and app-specific policy beside its owner in `Thaw/`. A pure function does not need a new package. Pass in time, snapshots and settings when they affect a decision instead of reading global state inside it.

## State and asynchronous work

- Give mutable state one owner. Expose the operations callers need rather than writable copies of the owner's state.
- Keep UI state and AppKit work on the main actor. Observation makes state visible to views; it does not make concurrent mutation safe.
- Give tasks, timers, subscriptions and helper sessions a lifetime. The owner must cancel or close them when their work is replaced or no longer needed.
- After an `await`, check that the result still belongs to the current request, display or item before publishing it or writing the layout. Actor isolation alone does not prevent stale results.
- Handle cancellation separately from failure. Keep retries bounded, and preserve existing timeout and cancellation behavior when replacing an implementation.

## Layout writes and saved data

- Use the [position-store boundary](ARCHITECTURE.md#layout-writes) for item-order writes. Don't call `RuntimePositionStore` directly to bypass permits or Manual arrangement mode.
- A missing item in one observation is not proof that the person removed it. Preserve the last usable state where the existing policy calls for it; test transient reads before changing recovery behavior.
- Treat defaults keys, encoded profile fields, item identities and helper messages as stored or shared formats. Renaming a Swift symbol must not silently rename its stored value. Keep explicit raw values and add migration tests when a format changes.
- Keep failures visible at the boundary that can handle them. Don't turn a failed write into a reported success, or silently replace unavailable data with an empty saved layout.

## Reuse before writing

- Search for an existing implementation before adding one. Share code when it represents the same rule; similar-looking code with different responsibilities need not share an abstraction.
- Before hand-rolling a collection, stream operator, timeout or lock, check the existing packages and standard APIs. `AsyncAlgorithms`, `Synchronization.Mutex`, `Observation` and `ContinuousClock` cover different needs; choose by behavior and availability, not just a matching name.
- Adding a new package is a bigger decision, because it changes `Package.resolved` and the dependency scan. Propose it in the issue or pull request and say what it replaces.
- Swapping in a library type must not change behavior. A lock that callers can cancel out of isn't a drop-in replacement for one they can't.

## Comments

Write comments as plain sentences. Explain a macOS quirk, a required ordering, a lifetime or another constraint the code cannot show. Don't narrate what the next line does or leave a history of the editing session.

Use `///` for a caller's contract, including important side effects, failure cases and cancellation behavior. Parameter and return documentation is useful when the signature is not enough. Keep `// MARK:` sections where they help navigation; avoid decorative headings, bold text and tables in ordinary comments.

## Writing

This covers documentation, the changelog, pull request descriptions and the text the app shows.

- Write for the person reading, in plain words. Say what they can do and what happens, and leave out how the code does it unless they need that.
- Use sentence case for headings, such as "Reset or uninstall".
- Don't use em dashes or en dashes. Use a period, a comma, a colon or parentheses.
- Refer to a person you don't know as they.
- Link to other files in the repository with relative links, such as `[Development](DEVELOPMENT.md)`.
- Keep each rule or procedure in one document and link to it elsewhere. Describe implemented behavior as fact and label proposals as proposals.
- Check paths, commands and heading anchors when editing documentation. Preserve headings linked from elsewhere, or update their incoming links.
- Change English source strings only. Translations go through Crowdin.

## Tests

- Use Swift Testing (`@Test`, `#expect`). Don't add XCTest.
- Where the logic can be isolated, write the failing test first.
- Add tests for new behavior and a regression test for each bug fix when practical.
- Test a module through its interface, not its private helpers. Assert observable behavior rather than the number of internal calls unless that count is part of the contract.
- Put package behavior in that package's test target and app behavior in `ThawTests`. Run the affected targets as well as the app suite described in [Development](DEVELOPMENT.md#tests).
- Use temporary files and isolated defaults. Tests that use the app's `Defaults.store` should use the existing [`.scratchDefaults` trait](../ThawTests/Utilities/ScratchDefaults.swift), which restores the store and coordinates access across suites. Serializing one suite alone does not protect a global used by another suite.
- Test refusal, missing data, cancellation and stale results where they are part of the behavior. Prefer controlled inputs and synchronization over sleeps that depend on machine speed.
- New code needs at least 80% test coverage. See [SonarCloud](../AGENTS.md#sonarcloud) in AGENTS.md.
- Some code can only run against a live menu bar. Keep that glue thin, and say in the pull request what you checked by hand.

## Formatting and lint

Configuration lives in [`.swiftformat`](../.swiftformat) and [`.swiftlint.yml`](../.swiftlint.yml).

```sh
swiftformat .
sh scripts/lint.sh --strict
```

The file, function, type, complexity and nesting limits are on. Violations that were already there are kept in `.swiftlint.baseline`, so only new ones report. Don't add entries to the baseline to make room for new code, and don't disable rules or add suppressions to get a change through.
