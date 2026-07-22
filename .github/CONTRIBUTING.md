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

5. When ready, open a pull request against `stonerl/Thaw:development`

## Non-technical contributions

### Reporting bugs

Before submitting a bug report, please search the [issue tracker][it] and check [Frequent Issues][fq] — your problem may already be known with a workaround available.

We want to fix all issues as soon as possible, but before fixing a bug we need to be able to reproduce them first. Our bug report template will guide you through the information we need. Issues without enough information to reproduce the problem may be closed until more details are provided.

If the app crashed — attaching a log file will help us significantly, you can find these in Thaw's settings under the General tab.

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

### Getting Started

1. Open `Thaw.xcodeproj` in Xcode 26 or later

   ```bash
   open Thaw.xcodeproj
   ```

2. Build and run the app (`Cmd+R`) to confirm everything works before making changes

### Code Style

Thaw uses [SwiftLint](https://github.com/realm/SwiftLint) and [SwiftFormat](https://github.com/nicklockwood/SwiftFormat) to enforce consistent code style.

Before submitting a request, run:

```bash
swiftformat .
swiftlint lint
```

Pull requests are automatically reviewed by SonarCloud for code quality and CodeRabbit for AI-assisted review. You may receive automated comments from these tools, so please address any findings before requesting a human review.

### Pull Requests

Open a pull request via the [Thaw pull requests page][pr] and select the [appropriate template][prt] — it will guide you through the required information and checklist.

## Resources

- [How to Contribute to Open Source](https://opensource.guide/how-to-contribute/)
- [Using Issues](https://docs.github.com/en/issues/tracking-your-work-with-issues/using-issues)
- [Using Pull Requests](https://help.github.com/articles/about-pull-requests/)

[coc]: CODE_OF_CONDUCT.md
[fq]: ../FREQUENT_ISSUES.md
[it]: https://github.com/stonerl/Thaw/issues
[pr]: https://github.com/stonerl/Thaw/pulls
[prt]: https://github.com/stonerl/Thaw/blob/development/.github/pull_request_template.md
