# Contributing to Thaw
The following is a set of guidelines to contribute to Thaw on GitHub.
Feel free to propose any changes to this document. All contributions welcome.

## <a name="coc"></a>Code of Conduct
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
5. When ready, open a pull request against `stonerl/Thaw:main`
## Non-technical contributions

### Reporting bugs
Before submitting a bug report, please search the [issue tracker][it] and check [Frequent Issues][fq] — your problem may already be known with a workaround available.

We want to fix all issues as soon as possible, but before fixing a bug we need to be able to reproduce them first. Our bug report template will guide you through the information we need. Issues without enough information to reproduce the problem may be closed until more details are provided.

If the app crashed — attaching a log file will help us significantly, you can find these in Thaw's settings under the General tab.

### Translations
If you want to help translate Thaw into your language or improve existing ones, you'll need Xcode 16.4+.

1. Open `Thaw.xcodeproj` from your cloned fork.
2. Navigate to `Thaw -> Resources -> Localizable.xcstrings`.
3. Add a new language using the **+** button at the bottom or update existing strings.
4. Submit a Pull Request with your changes using the [Localization / Translation PR template][lt].

_Note: You can see the exact completion percentage for each language directly in the Xcode String Catalog editor._

### Documentation improvements

If you find something unclear, incomplete, or out of date in any of the project's docs, a pull request to fix it is welcome.
 
This includes but is not limited to:
- Fixing typos or unclear wording
- Keeping the README up to date
- Adding new entries to [Frequent Issues][fq]
- Improving this and other guides.

## Technical contributions

### Prerequisites
- Xcode 16.4+
- macOS 14+

### Getting Started

1. Open `Thaw.xcodeproj` in Xcode 16.4 or later
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
Open a pull request [here][pr] and select the [appropriate template][prt] — it will guide you through the required information and checklist. Make sure the CI passes and wait for code review. You may be asked to make changes; when finished, request a re-review using the GitHub feature or mention the reviewers.

## Resources
- [How to Contribute to Open Source](https://opensource.guide/how-to-contribute/)
- [Using Issues](https://docs.github.com/en/issues/tracking-your-work-with-issues/using-issues)
- [Using Pull Requests](https://help.github.com/articles/about-pull-requests/)

[coc]: CODE_OF_CONDUCT.md
[fq]: FREQUENT_ISSUES.md
[it]: https://github.com/stonerl/Thaw/issues
[pr]: https://github.com/stonerl/Thaw/pulls
[lt]: https://github.com/stonerl/Thaw/blob/main/.github/PULL_REQUEST_TEMPLATE/localization.md
[prt]: https://github.com/stonerl/Thaw/blob/main/.github/pull_request_template.md
