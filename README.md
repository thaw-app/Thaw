# Thaw

The open source menu bar manager for macOS. Hide the items you don't need, bring them back on demand, and find any of them in a keystroke. Free under GPL-3.0, with no tracking and no account. [Try it in your browser](https://www.getthaw.app/#try).

![Thaw](https://www.getthaw.app/og/site/home/image.png)

## Install

| macOS | Thaw | Homebrew |
|---|---|---|
| 15 to 26 | Thaw 2 | `brew install thaw`, or `brew install thaw@beta` on macOS 15 until Thaw 2.2 is out of beta |
| 27 | Thaw 3, in beta | `brew install thaw@beta` |

Without Homebrew, download the disk image from the [releases](https://github.com/thaw-app/Thaw/releases) and drag Thaw to Applications. [Versions and update channels](docs/VERSIONS.md) covers macOS 14 and the update channels.

Thaw asks for Accessibility to move menu bar items, and on macOS 27 for Menu Bar Layout Access, the one file where macOS keeps the menu bar's order. Screen Recording is optional; without it, items show as their app's icon. [Getting started](docs/GETTING_STARTED.md) walks through the first run.

## Documentation

Visit https://www.getthaw.app/docs/thaw to view the documentation. [What Verified means](https://www.getthaw.app/verified) covers how releases are built and checked.

## Contributing

Please read the [contributing guide](https://github.com/thaw-app/.github/blob/main/.github/CONTRIBUTING.md). Pull requests go against the `development` branch. Translations go through [Crowdin](https://crowdin.com/project/thaw), and everyone who has helped is on the [community page](https://www.getthaw.app/community).

## License

Thaw is available under the [GPL-3.0 license](LICENSE). Linking with
PlatformRuntimeKit, the closed component that hides items, is allowed by an
[additional permission](LICENSE-EXCEPTION) under section 7.
