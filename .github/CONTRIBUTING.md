# Contributing to Thaw

The following is a set of guidelines to contribute to Thaw on GitHub.
Feel free to propose any changes to this document. All contributions welcome.

## Code of Conduct

Please read and follow our [Code of Conduct][coc].

## Ways to contribute

- Bug reports
- Documentation improvements
- Code
- Translations

Looking for a concrete task? See the living list in **[Ways to contribute (#316)](https://github.com/thaw-app/Thaw/issues/316)** (docs/screenshots, triage, small cleanups, and more).

## Developer Certificate of Origin (DCO)

Thaw requires contributors to certify that they have the right to submit their
work under the project’s license. We use the
[Developer Certificate of Origin (DCO) v1.1](https://developercertificate.org/).

By adding a `Signed-off-by` line to each commit, you assert the DCO. Use your
real name (not a pseudonym) as in:

```bash
git commit -s -m "fix(menubar): explain the change"
```

which appends:

```text
Signed-off-by: Your Name <your.email@example.com>
```

CI enforces this on pull requests (see `.github/workflows/pr-metadata.yml`):
every non-merge commit must include a `Signed-off-by` trailer whose email
matches the commit author. Bot/automation commits (Dependabot, Crowdin, etc.)
are exempt. PRs that fail DCO will not pass the PR Metadata check until you
amend or rebase with sign-off (`git rebase --signoff` then force-push).

> **Note:** This is not a CLA and does not transfer copyright. It is an
> attestation that you can contribute the change under GPL-3.0.

### AI-assisted contributions

We are **friendly to AI-assisted work**. Using coding assistants is fine when the result is high quality and follows this guide.

The DCO still applies to the **human who signs off**. By adding `Signed-off-by`, you certify that you have the right to contribute the change under GPL-3.0, including any AI-generated portions. The tool is not a DCO party; you are responsible for the commit.

In practice:

- Prefer tools whose terms allow contributing output to GPL-licensed projects.
- Do not feed clearly proprietary or third-party-restricted code into an assistant and commit the result as if it were yours.
- You must understand and be able to explain the change in review.

We use **CodeRabbit** and **SonarCloud** on pull requests. Treat their findings as part of the review bar unless a maintainer marks something won’t-fix. We expect fixes and high quality before (and during) human review.

**We reserve the right** to reject contributions or block automated committers / assistant-driven submission paths when they harm the project (spam, unsafe automation, or repeated low-quality work).

Pull requests **will be closed** when they show observable process or quality failures, for example unreviewed generated content pasted without human cleanup, missing required tests or documentation, failing CI or review checks left unaddressed, ignored maintainer feedback, wrong base branch, missing issue where required, unsigned commits, unchecked PR template, or drive-by refactors with no issue. Using AI does not lower the bar.

Maintainer bandwidth is limited. If we request changes and there is **no meaningful follow-up** within a reasonable window, the PR **will be closed**. You can always open a new PR later that addresses the feedback.

## Before You Start

Regardless of the type of contribution, you'll need a GitHub account and a fork of the repository:

1. Fork the repository on GitHub
2. Clone your fork locally

   ```bash
   git clone https://github.com/YOUR_USERNAME/Thaw.git
   ```

3. Navigate to the cloned directory
4. Create a branch for your changes

   ```bash
   git checkout -b your-branch-name
   ```

5. When ready, open a pull request against `thaw-app/Thaw:development`

## Non-technical contributions

### Reporting bugs

Before submitting a bug report, please search the [issue tracker][it] and check [Frequent Issues][fq]. Your problem may already be known with a workaround available.

We want to fix all issues as soon as possible, but before fixing a bug we need to be able to reproduce them first. Our bug report template will guide you through the information we need. Issues without enough information to reproduce the problem may be closed until more details are provided.

If the app crashed, attach a log file. You can find these in Thaw's settings under the General tab.

### Translations

Translations are managed on [Crowdin](https://crowdin.com/project/thaw). If you want to help translate Thaw into your language or improve existing translations, please contribute there directly.

**Translation pull requests are not accepted.** All translation contributions must go through Crowdin so they can be reviewed and synced consistently.

### Documentation improvements

If you find something unclear, incomplete, or out of date in any of the project's docs, a pull request to fix it is welcome.

This includes but is not limited to:

- Fixing typos or unclear wording
- Keeping the README up to date
- Adding new entries to [Frequent Issues][fq]
- Improving this and other guides.

## Technical contributions

### Prerequisites

- Xcode 26+
- macOS 26+

> [!NOTE]
> macOS 27 (Golden Gate) experimental work happens on `feat/macos-27-experimental` and is tracked in [issue #687](https://github.com/thaw-app/Thaw/issues/687).

### Getting Started

1. Open `Thaw.xcodeproj` in Xcode 26 or later

   ```bash
   open Thaw.xcodeproj
   ```

2. Build and run the app (`Cmd+R`) to confirm everything works before making changes

### Code Style

Thaw uses [SwiftLint](https://github.com/realm/SwiftLint) and [SwiftFormat](https://github.com/nicklockwood/SwiftFormat) to enforce consistent code style.

Primary language style guides are embodied in:

- [`.swiftlint.yml`](../.swiftlint.yml)
- [`.swiftformat`](../.swiftformat)

Before submitting a request, run:

```bash
swiftformat .
swiftlint lint --strict
```

Pull requests are automatically reviewed by SonarCloud for code quality and CodeRabbit for AI-assisted review. You may receive automated comments from these tools, so please address any findings before requesting a human review.

### SCA / SAST expectations

Thaw treats automated security and quality findings as part of the merge bar.
The full dependency SCA policy (thresholds + suppressions) lives in
[SECURITY.md](SECURITY.md) (§ Dependency SCA policy).

| Signal | Where | Expectation |
| --- | --- | --- |
| **Dependency SCA** (`dependency-sca`) | OSV-Scanner on every PR / `development` push | **Required.** Fix or suppress (via `osv-scanner.toml` + reason) before merge |
| **Dependabot** | Dependency / Actions update PRs | Review and merge promptly; those PRs must still pass `dependency-sca` |
| **SonarCloud** | PR decoration + quality gate | Fix new issues / smells called out on the PR unless a maintainer marks won’t-fix |
| **CodeQL** | Security analysis workflow (when enabled on the branch) | Address high/critical findings before merge; discuss false positives with maintainers |
| **CodeRabbit** | PR review comments | Treat as required unless a maintainer marks won’t-fix (same bar as above) |

Do not merge with a failing required check. If a finding is a false positive or
not exploitable in Thaw, add a documented suppression in `osv-scanner.toml` (see
SECURITY.md) rather than bypassing the check.

### Tests

The suite uses [Swift Testing](https://developer.apple.com/documentation/testing)
throughout; there is no XCTest left to match. Major new functionality must
include automated tests in `ThawTests` (or the relevant package test target)
unless a maintainer agrees that no seam exists. Bug fixes should add a
regression test when practical. The PR template checklist asks you to confirm
this.

### Project conventions

- **Branch & base:** All external PRs must target `development` (not `main`), unless a maintainer asks otherwise.
- **PR size:** Aim for ≤500 lines / ≤20 files per PR. If you expect to exceed this, say why in the Summary and link the design/issue.
- **Templates & issues:** Bugfix and feature PRs should always reference a GitHub issue (`Closes: #123`, or `Closes: N/A` when agreed).
- **Commit / PR titles:** Prefer conventional commits, e.g. `fix(menubar): …`, `feat(settings): …`.
- **DCO:** Every commit must be signed off (`git commit -s`). CI enforces this
  on PRs via PR Metadata (author-email must match the trailer).
- **Code review bots:** CodeRabbit and SonarCloud comments are treated as *required* unless a maintainer marks them won’t-fix. If you’re unsure, wait for a maintainer reply before large refactors spurred by bots alone.
- **Sensitive areas:** Expect deeper review and stronger tests when touching menu bar hiding/layout, IceBar / Thaw Bar, triggers/automation, logging, or permissions.

### Pull Requests

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
