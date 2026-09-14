# Contributing to Thaw

All contributions welcome. Propose changes to this document in a pull request.

## Code of Conduct

Read and follow our [Code of Conduct][coc].

## Ways to contribute

Bug reports, code, docs, translations. Looking for a concrete task? See the living list in **[Ways to contribute (#316)](https://github.com/thaw-app/Thaw/issues/316)** (docs/screenshots, triage, small cleanups).

## Developer Certificate of Origin (DCO)

Thaw requires contributors to certify they have the right to submit their work under the project's license, via the [Developer Certificate of Origin (DCO) v1.1](https://developercertificate.org/). Add a `Signed-off-by` line to each commit with your real name (not a pseudonym):

```bash
git commit -s -m "fix(menubar): explain the change"
```

which appends:

```text
Signed-off-by: Your Name <your.email@example.com>
```

CI enforces this on pull requests (see `.github/workflows/pr-metadata.yml`): every non-merge commit must include a `Signed-off-by` trailer whose email matches the commit author. Bot/automation commits (Dependabot, Crowdin, etc.) are exempt. PRs that fail DCO will not pass the PR Metadata check until you amend or rebase with sign-off (`git rebase --signoff` then force-push).

This is not a CLA and does not transfer copyright; it is an attestation that you can contribute the change under GPL-3.0.

### AI-assisted contributions

AI-assisted work is welcome when the result is high quality and follows this guide.

- The DCO applies to the **human who signs off**. By adding `Signed-off-by`, you certify you have the right to contribute the change under GPL-3.0, including any AI-generated portions. The tool is not a DCO party; you are responsible for the commit.
- Prefer tools whose terms allow contributing output to GPL-licensed projects. Do not feed clearly proprietary or third-party-restricted code into an assistant and commit the result as if it were yours.
- You must understand and be able to explain the change in review.

CodeRabbit and SonarCloud run on pull requests. Treat their findings as part of the review bar unless a maintainer marks something won't-fix.

Low-quality PRs are closed. A PR is closed when it shows observable process or quality failures: unreviewed generated content pasted without human cleanup, missing required tests or documentation, failing CI or review checks left unaddressed, ignored maintainer feedback, wrong base branch, missing issue where required, unsigned commits, unchecked PR template, or drive-by refactors with no issue. Using AI does not lower the bar. If we request changes and there is no meaningful follow-up within a reasonable window, the PR is closed; open a new one later that addresses the feedback.

## Before you start

You need a GitHub account and a fork:

1. Fork the repository on GitHub
2. Clone your fork locally

   ```bash
   git clone https://github.com/YOUR_USERNAME/Thaw.git
   cd Thaw
   ```

3. Create a branch for your changes

   ```bash
   git checkout -b your-branch-name
   ```

4. When ready, open a pull request against `thaw-app/Thaw:development`

## Non-technical contributions

### Reporting bugs

Before submitting a bug report, search the [issue tracker][it] and check [Frequent Issues][fq]; your problem may already be known with a workaround. The bug report template asks for the information we need to reproduce the issue; reports without enough detail may be closed until more is provided. If the app crashed, attach a log file from Thaw's settings (General tab).

### Translations

Translations are managed on [Crowdin](https://crowdin.com/project/thaw). Contribute there directly to translate Thaw or improve existing translations.

**Translation pull requests are not accepted.** All translation contributions must go through Crowdin so they can be reviewed and synced consistently.

### Documentation improvements

A pull request to fix anything unclear, incomplete, or out of date in the project's docs is welcome.

## Technical contributions

### Prerequisites

- Xcode 26+
- macOS 26+

### Getting started

```bash
open Thaw.xcodeproj
```

### Code style

Thaw uses [SwiftLint](https://github.com/realm/SwiftLint) and [SwiftFormat](https://github.com/nicklockwood/SwiftFormat). Config lives in [`.swiftlint.yml`](../.swiftlint.yml) and [`.swiftformat`](../.swiftformat). Before submitting, run:

```bash
swiftformat .
swiftlint lint --strict
```

### SCA / SAST expectations

Thaw treats automated security and quality findings as part of the merge bar. The full dependency SCA policy (thresholds + suppressions) lives in [SECURITY.md](SECURITY.md) (§ Dependency SCA policy).

| Signal | Where | Expectation |
| --- | --- | --- |
| **Dependency SCA** (`dependency-sca`) | OSV-Scanner on every PR / `development` push | **Required.** Fix or suppress (via `osv-scanner.toml` + reason) before merge |
| **Dependabot** | Dependency / Actions update PRs | Review and merge promptly; those PRs must still pass `dependency-sca` |
| **SonarCloud** | PR decoration + quality gate | Fix new issues / smells called out on the PR unless a maintainer marks won't-fix |
| **CodeQL** | Security analysis workflow (when enabled on the branch) | Address high/critical findings before merge; discuss false positives with maintainers |
| **CodeRabbit** | PR review comments | Treat as required unless a maintainer marks won't-fix (same bar as above) |

Do not merge with a failing required check. If a finding is a false positive or not exploitable in Thaw, add a documented suppression in `osv-scanner.toml` (see SECURITY.md) rather than bypassing the check.

### Tests

The suite uses [Swift Testing](https://developer.apple.com/documentation/testing) throughout; there is no XCTest left to match. Major new functionality must include automated tests in `ThawTests` (or the relevant package test target) unless a maintainer agrees that no seam exists. Bug fixes should add a regression test when practical. The PR template checklist asks you to confirm this.

### Project conventions

- Branch & base: all external PRs must target `development` (not `main`), unless a maintainer asks otherwise.
- PR size: aim for ≤500 lines / ≤20 files per PR. If you expect to exceed this, say why in the Summary and link the design/issue.
- Templates & issues: bugfix and feature PRs should always reference a GitHub issue (`Closes: #123`, or `Closes: N/A` when agreed).
- Commit / PR titles: prefer conventional commits, e.g. `fix(menubar): …`, `feat(settings): …`.
- DCO: every commit must be signed off (`git commit -s`). CI enforces this on PRs via PR Metadata (author-email must match the trailer).
- Code review bots: CodeRabbit and SonarCloud comments are treated as *required* unless a maintainer marks them won't-fix. If you're unsure, wait for a maintainer reply before large refactors spurred by bots alone.
- Sensitive areas: expect deeper review and stronger tests when touching menu bar hiding/layout, IceBar / Thaw Bar, triggers/automation, logging, or permissions.

### Pull requests

Open a pull request via the [Thaw pull requests page][pr] and select the [appropriate template][prt]. It will guide you through the required information and checklist.

## Project docs (orientation)

- [Governance][gov]: roles and decision-making
- [Architecture][arch]: high-level design
- [Security policy][sec]: reporting and security requirements
- [URI schemes][uri]: external automation surface

## Resources

- [How to Contribute to Open Source](https://opensource.guide/how-to-contribute/)
- [Using Issues](https://docs.github.com/en/issues/tracking-your-work-with-issues/using-issues)
- [Using Pull Requests](https://help.github.com/articles/about-pull-requests/)
- [Developer Certificate of Origin](https://developercertificate.org/)

[coc]: CODE_OF_CONDUCT.md
[fq]: ../FREQUENT_ISSUES.md
[it]: https://github.com/thaw-app/Thaw/issues
[pr]: https://github.com/thaw-app/Thaw/pulls
[prt]: https://github.com/thaw-app/Thaw/blob/development/.github/pull_request_template.md
[gov]: GOVERNANCE.md
[arch]: ../docs/ARCHITECTURE.md
[sec]: SECURITY.md
[uri]: ../docs/URI_SCHEMES.md
