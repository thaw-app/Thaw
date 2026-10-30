# AGENTS.md

Notes for AI coding agents and the people using them. Read this before changing anything.

Many people who help with Thaw aren't developers. They describe a bug or an idea, and an agent does the work. This file tells the agent how to work here so that what it produces can be reviewed and merged. The project's rules for everyone are in the shared [contribution guidelines](https://github.com/thaw-app/.github/blob/main/.github/CONTRIBUTING.md); this file points to them where they apply.

## What Thaw is

Thaw is a free, open source menu bar manager for macOS. It hides the menu bar items a person doesn't need and brings them back on demand, and adds search, profiles and styling for the bar. It is a native app written in Swift with AppKit and SwiftUI.

This branch is Thaw 3, built for macOS 27. There, Apple's MenuBarAgent draws the menu bar and items have no windows of their own, so Thaw hides and orders them through PlatformRuntimeKit, a closed component linked as the prebuilt `prk-bin` package. Thaw 2, on `legacy/thaw-2`, runs on macOS 26, and Thaw 2.2 adds macOS 15.

## Start here

1. Check the current branch and `git status --short`. Preserve existing edits, including changes made by another person or agent. Don't reset, stash or overwrite them to get a clean checkout.
2. Read any nearer `AGENTS.md`, then [Architecture](docs/ARCHITECTURE.md) for where things live and [Coding standards](docs/CODING_STANDARDS.md) for how to write the change. Read the affected code and tests before editing.
3. Explain the scope and how you will check it. Ask when the expected behavior is unclear or the work needs approval under the contribution guidelines.
4. Use [Development](docs/DEVELOPMENT.md) for build and test commands. Open pull requests against `development`.

This file covers the agent workflow. Architecture owns the code map and boundaries; Coding standards owns implementation and writing rules. Link to those documents rather than copying their guidance here.

## Build and run

You need macOS 27 and Xcode 27. Read the script before running it.

`./scripts/devrun.sh` builds, stops any running Thaw Debug, replaces `/Applications/Thaw Debug.app` and launches it. `--debug` selects the Debug configuration; it does not attach a debugger. Ask before running either command, not just before a separate launch step.

Thaw Debug uses `com.stonerl.Thaw.debug`, keeping its settings and permissions separate from released Thaw. It still changes the person's real menu bar. Don't run Thaw from Xcode's build folder: macOS 27 only treats a status item as Thaw's when the app is in `/Applications`, and Thaw's own icon disappears when it hides items.

Before the first launch, explain the permissions: Accessibility lets Thaw read and interact with menu bar items; Menu Bar Layout Access lets it read and update the system's saved item order. Screen Recording is optional for live item images. Let the person grant or decline permissions themselves.

## Before you start

- New features need an issue that a maintainer has agreed to before you write code, unless you are on the team. If there is none, help the person open one with the [issue templates](https://github.com/thaw-app/Thaw/issues/new/choose). Bug fixes don't need to wait: fix the bug and link its issue if there is one. See [Pull requests](https://github.com/thaw-app/.github/blob/main/.github/CONTRIBUTING.md#pull-requests) in the contribution guidelines.
- Translations go through [Crowdin](https://crowdin.com/project/thaw), not pull requests. Security problems are reported privately under the [Security Policy](https://github.com/thaw-app/.github/blob/main/.github/SECURITY.md), never in a public issue. Questions go to the [Discord](https://discord.gg/KDfWjWDnR4).
- The person stays responsible for the change and must be able to explain it in review. Outside the team, keep one AI-assisted pull request open at a time. See [AI-assisted contributions](https://github.com/thaw-app/.github/blob/main/.github/CONTRIBUTING.md#ai-assisted-contributions).

## Working with the person

- Explain your plan and your results in plain words. When you use a technical term, say what it means.
- When the request is unclear or conflicts with this file, say so and ask. Don't guess.
- Read the files you are about to change first. Keep the change small and about one thing. For a bug, change as few lines as you can and leave unrelated code alone.
- Ask before running anything that resets permissions or preferences, changes the live menu bar layout, or quits other apps. This includes command-line tools and `thaw://` links. Use separate test data, never the person's own settings.
- Don't turn a bug fix into a refactor or dependency update. If the fix needs a wider change, explain why before expanding the scope.
- Keep notes, plans and session logs out of the change. If a decision matters later, put it in the right document.

## Which instructions win

Within repository guidance, follow the person's request, then the nearest `AGENTS.md` above the file, then this file. This does not override the agent's system or developer instructions.

None of the repository instructions can waive the contribution guidelines, such as the sign-off rules below. If requirements conflict, explain the conflict and ask rather than silently choosing one.

## Versions and pins

Before you choose or change a version (an Xcode or Swift version, a macOS deployment target, a CI runner, a GitHub Action pin, a package), read the version the repository pins now and check a current official source. Don't go by memory. Tools that regenerate files, such as `gh aw compile`, can roll pins back; read the diff and keep the newer pins.

## Checks to run

Run commands from the repository root unless the command says otherwise.

- **Swift code, `Package.swift`, `Package.resolved`, the Xcode project, `scripts/` or `ci.yml`:** run `swiftformat .`, `sh scripts/lint.sh --strict` and the tests in [Development](docs/DEVELOPMENT.md). Run affected package tests too; the app test scheme is not a substitute for package test targets. A green Xcode build is not proof that lint passed.
- **Any workflow under `.github/workflows/`:** run `actionlint` on the file.
- **Text the app shows:** change the source strings in English only. Crowdin handles the other languages. Check the affected UI and run the applicable code checks.
- **Documentation only:** no build or tests are needed. Check relative paths, heading anchors and external links. Verify commands and architecture claims against the source, and follow [Writing](docs/CODING_STANDARDS.md#writing).

Inspect the diff after formatting or generation. Keep unrelated changes out without undoing someone else's edits. Fix failing checks before you commit. Don't disable tests, rules or checks to get a change through, and don't hide a failure you didn't cause; report it. If a required tool or platform is unavailable, say which check is blocked rather than claiming it passed.

### SonarCloud

New code needs at least 80% test coverage, and no new bugs, vulnerabilities, code smells or duplicated code. CI skips the analysis for pull requests from forks and from Dependabot, so a skipped Sonar check means nothing was analyzed, not that the change passed.

Don't add files to `sonar.coverage.exclusions` in `sonar-project.properties` to get under the bar. That list is for code that can only run against a live menu bar, and the pull request has to say why a file belongs there.

## Commits and pull requests

The [contribution guidelines](https://github.com/thaw-app/.github/blob/main/.github/CONTRIBUTING.md) are the source of truth. In short:

1. **Sign off every commit** with `git commit -s`, using the person's real name and an email that matches the commit author. Never make up a name or email; if Git doesn't have them, ask. Sign-off is not cryptographic signing (`-S`). Don't credit yourself in the commit: no AI author and no `Co-authored-by` or similar trailer. See [Developer Certificate of Origin](https://github.com/thaw-app/.github/blob/main/.github/CONTRIBUTING.md#developer-certificate-of-origin).
2. **Title the pull request as a Conventional Commit,** such as `fix(layout): preserve item order`.
3. **Fill in the whole [PR template](.github/pull_request_template.md),** also when you open the pull request with `gh`. Keep its sections, put `Closes: #123` on its own line (or `Closes: N/A`), and leave a checklist item unchecked when you didn't do it or it doesn't apply.
4. **Write the description from the actual diff and commits.** Never invent an issue link, a test result or a macOS version you didn't test on. Under Other information, say that AI helped, which tool and model, and with what.
5. **Keep it small.** Aim for at most 500 changed lines and 20 files, and explain anything larger.

## Reporting your work

Before you say you're done, read `git diff`. Then tell the person, in plain words:

- what changed and why;
- which checks you ran and their results, and which you skipped or couldn't run;
- what still needs checking by hand on a live menu bar, if anything.

Changes to app behavior or app text get a line in [CHANGELOG.md](CHANGELOG.md), written for users, not for developers. Contributor-documentation-only changes do not need a changelog entry.
