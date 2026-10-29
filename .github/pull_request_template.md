# Summary

<!--
A short description of the change.

Scope: one focused thing (a bug fix or a feature) plus the plumbing it needs. Larger refactors need agreement in the issue first.

Don't add responsibilities to the big types. We're breaking up MenuBarItemManager, MenuBarItemImageCache, MenuBarManager, HIDEventManager, ControlItem and ProfileManager. Extend a focused module or extract the behavior with its state; the big type only plugs it in. The coding standards have the list and why:
https://github.com/thaw-app/Thaw/blob/development/docs/CODING_STANDARDS.md

Tests use Swift Testing. Write new tests with @Test and #expect, not XCTest.

External contributors: a bug fix or feature needs an issue in the tracker before the pull request. Pull requests for changes nobody reported or agreed on may be closed without review.
-->

## Linked issue (required)

<!--
PR Metadata fails without the line below. Keep it on its own line, and replace N/A with the issue number (#123) when this pull request fixes or implements one.
-->

Closes: N/A

## PR Type

<!--
Pick what this change does, not the kind of request in the linked issue. A bug report uses the Bug issue type; a bug fix is "fix" here.

If you tick Feature or Refactor and touch more than about 20 files, say why it can't be split.
-->

- [ ] Bug fix
- [ ] CI/CD
- [ ] Documentation
- [ ] Feature
- [ ] Enhancement
- [ ] Performance improvement
- [ ] Refactor
- [ ] Test addition or update
- [ ] Other (please describe)

## Area

<!--
Optional when the change isn't about the app's interface. Labels are also added from the paths you changed.

PR Type says what changed (CI/CD, Documentation, Other for chores). Tick ops for where, when the change is repo operations: CI, releases, GitHub settings, scripts, lint or Sonar config.
-->

- [ ] menubar
- [ ] icebar
- [ ] layout
- [ ] appearance
- [ ] settings
- [ ] onboarding
- [ ] permissions
- [ ] profiles
- [ ] hotkeys
- [ ] updates
- [ ] ops

## Does this PR introduce a breaking change?

<!-- If yes, describe the impact and how users move over. -->

- [ ] Yes
- [ ] No

## What is the new behavior?

<!-- What this pull request changes or adds, and why. -->

## PR Checklist

- [ ] I've built and run the app locally and verified that it works as expected.
- [ ] I've run `swiftformat .` and the strict lint for my branch (see [AGENTS.md](https://github.com/thaw-app/Thaw/blob/development/AGENTS.md#checks-to-run)).
- [ ] I've run the smallest relevant test commands and listed them below.
- [ ] I've added tests for new behavior (if applicable).
- [ ] I've noted which macOS versions I tested on (15, 26 or 27).
- [ ] I've documented new public APIs and non-obvious helpers.
- [ ] I've updated documentation as needed.
- [ ] This PR targets `development` (Thaw 3) or `legacy/thaw-2` (Thaw 2).
- [ ] I didn't add new responsibilities to the big types listed in the coding standards.
- [ ] New code has at least 80% test coverage and the SonarCloud scan reports no new issues (see [AGENTS.md](https://github.com/thaw-app/Thaw/blob/development/AGENTS.md#sonarcloud)). Fork PRs skip the scan, so it can't confirm this for them.
- [ ] If this PR changes dependencies or lockfiles (`Package.resolved`, Actions pins and so on), `dependency-sca` is green, or any `osv-scanner.toml` suppression has both `reason` and `ignoreUntil` (see the [Thaw/Floe Security Policy](https://github.com/thaw-app/.github/blob/main/.github/SECURITY.md#dependency-findings)).

Test commands run:

-

## Known limitations / follow-ups

<!-- Optional: what is out of scope on purpose, and any follow-up issues or planned work. -->

## Other information

<!-- Screenshots, notes, or anything else useful for reviewers. -->
