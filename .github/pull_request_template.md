# Summary

A brief description of the changes proposed in this pull request.

**Scope:** This PR changes one focused thing (bugfix or feature) plus minimal plumbing. Larger refactors need prior agreement in the issue.

> **External contributors:** before opening a PR for a bug fix or new feature, please make sure there's a corresponding issue in the [issue tracker](https://github.com/stonerl/Thaw/issues). PRs that fix or change things that haven't been reported/agreed on may be closed without review.

Closes: (Required for bugfix/feature PRs; use `Closes: #123` or `N/A`)

## PR Type

Describe **what this change does** (not the linked issue’s request kind). Bug *reports* use `bug` on issues; bug *fixes* use `fix` on PRs.

If you tick **Feature** or **Refactor** and touch more than ~20 files, please mention why this can’t be split.

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

**Product surfaces** (optional when the change is not about the app UI). Path-based labeling also applies.

- Use **PR Type** for *what* changed (`CI/CD`, `Documentation`, `Other` / chore, etc.).
- Use **`ops`** for *where* when it is repo operations: CI, release, GitHub hygiene, scripts, lint/sonar config — not a product surface.

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

- [ ] Yes - if yes, please describe the impact and migration path
- [ ] No

## What is the new behavior?

What does this PR change or add, and why?

## PR Checklist

- [ ] I've built and run the app locally and verified that it works as expected.
- [ ] I've run `swiftformat .` to keep the code style consistent.
- [ ] I've run the smallest relevant test commands (list 1–2 below), e.g. `xcodebuild test …` or `swift test --package-path MenuBarModel`.
- [ ] I've added tests for new behavior (if applicable).
- [ ] I've documented new public APIs / non-obvious helpers.
- [ ] I've updated documentation as needed.
- [ ] This PR targets the `development` branch.

Test commands run:

-

## Known limitations / follow-ups

- (optional) What is intentionally out of scope
- (optional) Follow-up issues or planned work

## Other information

Screenshots, notes, or anything useful for reviewers.
