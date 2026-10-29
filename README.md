![Thaw](https://raw.githubusercontent.com/thaw-app/brand-assets/main/headers/light_header.svg#gh-light-mode-only)
![Thaw](https://raw.githubusercontent.com/thaw-app/brand-assets/main/headers/dark_header.svg#gh-dark-mode-only)

<p align="center">
  <b>The open source menu bar manager for macOS.</b><br />
  Take back your menu bar. Hide what you don't need, and find anything in a keystroke.
</p>

<p align="center">
  <a href="https://www.getthaw.app"><b>getthaw.app</b></a> ·
  <a href="https://www.getthaw.app/docs/thaw">Docs</a> ·
  <a href="https://www.getthaw.app/changelog">Changelog</a> ·
  <a href="https://www.getthaw.app/#try">Try it in your browser</a>
</p>

<p align="center">
  <a href="https://discord.gg/KDfWjWDnR4"><picture><source media="(prefers-color-scheme: dark)" srcset="https://www.shieldcn.dev/badge/Discord-join.svg?variant=outline&amp;size=xs&amp;mode=dark&amp;font=geist&amp;logo=discord&amp;" /><img alt="Discord" src="https://www.shieldcn.dev/badge/Discord-join.svg?variant=outline&amp;size=xs&amp;mode=light&amp;font=geist&amp;logo=discord&amp;" /></picture></a>
  <a href="https://sonarcloud.io/component_measures?id=thaw-app_Thaw&amp;metric=coverage"><picture><source media="(prefers-color-scheme: dark)" srcset="https://www.shieldcn.dev/sonar/coverage/thaw-app_Thaw.svg?variant=outline&amp;size=xs&amp;mode=dark&amp;font=geist&amp;logo=sonarqubecloud" /><img alt="Sonar coverage" src="https://www.shieldcn.dev/sonar/coverage/thaw-app_Thaw.svg?variant=outline&amp;size=xs&amp;mode=light&amp;font=geist&amp;logo=sonarqubecloud" /></picture></a>
  <a href="https://scorecard.dev/viewer/?uri=github.com/thaw-app/Thaw"><picture><source media="(prefers-color-scheme: dark)" srcset="https://www.shieldcn.dev/github/scorecard/thaw-app/Thaw.svg?variant=outline&amp;size=xs&amp;mode=dark&amp;font=geist" /><img alt="OpenSSF Scorecard" src="https://www.shieldcn.dev/github/scorecard/thaw-app/Thaw.svg?variant=outline&amp;size=xs&amp;mode=light&amp;font=geist" /></picture></a>
  <a href="https://www.bestpractices.dev/projects/13303"><picture><source media="(prefers-color-scheme: dark)" srcset="https://www.shieldcn.dev/github/openssf/thaw-app/Thaw.svg?variant=outline&amp;size=xs&amp;mode=dark&amp;font=geist&amp;color=D4AF37" /><img alt="OpenSSF Best Practices" src="https://www.shieldcn.dev/github/openssf/thaw-app/Thaw.svg?variant=outline&amp;size=xs&amp;mode=light&amp;font=geist&amp;color=D4AF37" /></picture></a>
  <a href="docs/VERIFYING_RELEASES.md"><picture><source media="(prefers-color-scheme: dark)" srcset="https://www.shieldcn.dev/badge/SLSA-Build_L3.svg?variant=outline&amp;size=xs&amp;mode=dark&amp;font=geist&amp;logo=ri:GoPackage" /><img alt="SLSA 3" src="https://www.shieldcn.dev/badge/SLSA-3.svg?variant=outline&amp;size=xs&amp;mode=light&amp;font=geist&amp;logo=ri:GoPackage" /></picture></a>
</p>

<p align="center">
  <a href="https://www.raycast.com/diazdesandi/thaw"><picture><source media="(prefers-color-scheme: dark)" srcset="https://www.shieldcn.dev/badge/Works_with-Raycast.svg?variant=outline&amp;size=xs&amp;mode=dark&amp;font=geist&amp;logo=raycast" /><img alt="Works with Raycast" src="https://www.shieldcn.dev/badge/Works_with-Raycast.svg?variant=outline&amp;size=xs&amp;mode=light&amp;font=geist&amp;logo=raycast" /></picture></a>
  <a href="https://getdroppy.app/"><picture><source media="(prefers-color-scheme: dark)" srcset="https://www.shieldcn.dev/badge/Works_with-Droppy.svg?variant=outline&amp;size=xs&amp;mode=dark&amp;font=geist&amp;logo=data%3Aimage%2Fsvg%2Bxml%3Bbase64%2CPHN2ZyB3aWR0aD0iMTEwOCIgaGVpZ2h0PSIxNDAwIiB2aWV3Qm94PSIwIDAgMTEwOCAxNDAwIiBmaWxsPSJub25lIiB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciPjxwYXRoIGZpbGwtcnVsZT0iZXZlbm9kZCIgY2xpcC1ydWxlPSJldmVub2RkIiBkPSJNNzM5LjE4OSAzLjA5OTgzQzc3MS44OTUgLTEwLjMzMDEgODAzLjcyNyAyMi4xMjcyIDc5OC44MzIgNTcuMjEzNEM3ODYuNDQxIDE0Ni4wMzQgNzk3LjUwOSAyNDUuNDUxIDg0MC43MDYgMzI1LjM1MUM5MzguMTk3IDUwNS42NzUgMTEwOCA2NzAuMTQ0IDExMDggODY5Ljc4NkMxMTA4IDEwNjkuNDMgOTk4Ljc2NSAxNDAwIDU3MC45MzkgMTQwMEMxNDMuMTEyIDE0MDAgLTEwNy4xNDUgMTA0Ny42OCA0NC42MDQgNjI5LjAwNUMxNTQuOTEzIDMyNC42NjIgNDUwLjczNiAxMjEuNTQ5IDczOS4xODkgMy4wOTk4M1pNNzUwLjg4NyA2NjkuMTQyQzY4My4yODIgNjYxLjc1NSA2MTguMzkgNzQ4LjUyMiA2MDUuOTQ3IDg2Mi45NDFDNTkzLjUwNSA5NzcuMzYgNjM4LjIyMyAxMDc2LjEgNzA1LjgyNyAxMDgzLjQ5Qzc3My40MzIgMTA5MC44OCA4MzguMzI0IDEwMDQuMTEgODUwLjc2NyA4ODkuNjkzQzg2My4yMSA3NzUuMjczIDgxOC40OTIgNjc2LjUyOSA3NTAuODg3IDY2OS4xNDJaTTUwMi40OCA4NjMuMDY2QzQ5Mi41IDc0OS4yMTUgNDI5LjQ5IDY2MS43NTcgMzYxLjc0NiA2NjcuNzIzQzI5NC4wMDIgNjczLjY5MSAyNDcuMTc1IDc3MC44MjMgMjU3LjE1NSA4ODQuNjc0QzI2Ny4xMzUgOTk4LjUyNSAzMzAuMTQzIDEwODUuOTggMzk3Ljg4NyAxMDgwLjAyQzQ2NS42MzEgMTA3NC4wNSA1MTIuNDYgOTc2LjkxOCA1MDIuNDggODYzLjA2NloiLz48L3N2Zz4%3D" /><img alt="Works with Droppy" src="https://www.shieldcn.dev/badge/Works_with-Droppy.svg?variant=outline&amp;size=xs&amp;mode=light&amp;font=geist&amp;logo=data%3Aimage%2Fsvg%2Bxml%3Bbase64%2CPHN2ZyB3aWR0aD0iMTEwOCIgaGVpZ2h0PSIxNDAwIiB2aWV3Qm94PSIwIDAgMTEwOCAxNDAwIiBmaWxsPSJub25lIiB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciPjxwYXRoIGZpbGwtcnVsZT0iZXZlbm9kZCIgY2xpcC1ydWxlPSJldmVub2RkIiBkPSJNNzM5LjE4OSAzLjA5OTgzQzc3MS44OTUgLTEwLjMzMDEgODAzLjcyNyAyMi4xMjcyIDc5OC44MzIgNTcuMjEzNEM3ODYuNDQxIDE0Ni4wMzQgNzk3LjUwOSAyNDUuNDUxIDg0MC43MDYgMzI1LjM1MUM5MzguMTk3IDUwNS42NzUgMTEwOCA2NzAuMTQ0IDExMDggODY5Ljc4NkMxMTA4IDEwNjkuNDMgOTk4Ljc2NSAxNDAwIDU3MC45MzkgMTQwMEMxNDMuMTEyIDE0MDAgLTEwNy4xNDUgMTA0Ny42OCA0NC42MDQgNjI5LjAwNUMxNTQuOTEzIDMyNC42NjIgNDUwLjczNiAxMjEuNTQ5IDczOS4xODkgMy4wOTk4M1pNNzUwLjg4NyA2NjkuMTQyQzY4My4yODIgNjYxLjc1NSA2MTguMzkgNzQ4LjUyMiA2MDUuOTQ3IDg2Mi45NDFDNTkzLjUwNSA5NzcuMzYgNjM4LjIyMyAxMDc2LjEgNzA1LjgyNyAxMDgzLjQ5Qzc3My40MzIgMTA5MC44OCA4MzguMzI0IDEwMDQuMTEgODUwLjc2NyA4ODkuNjkzQzg2My4yMSA3NzUuMjczIDgxOC40OTIgNjc2LjUyOSA3NTAuODg3IDY2OS4xNDJaTTUwMi40OCA4NjMuMDY2QzQ5Mi41IDc0OS4yMTUgNDI5LjQ5IDY2MS43NTcgMzYxLjc0NiA2NjcuNzIzQzI5NC4wMDIgNjczLjY5MSAyNDcuMTc1IDc3MC44MjMgMjU3LjE1NSA4ODQuNjc0QzI2Ny4xMzUgOTk4LjUyNSAzMzAuMTQzIDEwODUuOTggMzk3Ljg4NyAxMDgwLjAyQzQ2NS42MzEgMTA3NC4wNSA1MTIuNDYgOTc2LjkxOCA1MDIuNDggODYzLjA2NloiLz48L3N2Zz4%3D" /></picture></a>
  <a href="https://www.getthaw.app/floe"><picture><source media="(prefers-color-scheme: dark)" srcset="https://www.shieldcn.dev/badge/Works_with-Floe.svg?variant=outline&amp;size=xs&amp;mode=dark&amp;font=geist&amp;logo=data%3Aimage%2Fsvg%2Bxml%3Bbase64%2CPHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHZpZXdCb3g9IjAgMCA1MzQgNTA3Ij48cGF0aCBkPSJNNDk0LDM5MyBMNDI2LDQ4MiBMMjE1LDUwMyBMNjksNDUxIEw0LDMwMiBMMzUsMTAyIEwyMTMsMTkgTDI2MiwyNSBMMzM0LDI3NyBaIi8%2BPHBhdGggZD0iTTMzMSwzMyBMMzY3LDM3IEw0MzYsNCBMNTIyLDEzNiBMNDk0LDI2MyBMNTMwLDM0MCBMMzkwLDIzOSBaIi8%2BPC9zdmc%2B" /><img alt="Works with Floe" src="https://www.shieldcn.dev/badge/Works_with-Floe.svg?variant=outline&amp;size=xs&amp;mode=light&amp;font=geist&amp;logo=data%3Aimage%2Fsvg%2Bxml%3Bbase64%2CPHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHZpZXdCb3g9IjAgMCA1MzQgNTA3Ij48cGF0aCBkPSJNNDk0LDM5MyBMNDI2LDQ4MiBMMjE1LDUwMyBMNjksNDUxIEw0LDMwMiBMMzUsMTAyIEwyMTMsMTkgTDI2MiwyNSBMMzM0LDI3NyBaIi8%2BPHBhdGggZD0iTTMzMSwzMyBMMzY3LDM3IEw0MzYsNCBMNTIyLDEzNiBMNDk0LDI2MyBMNTMwLDM0MCBMMzkwLDIzOSBaIi8%2BPC9zdmc%2B" /></picture></a>
  <a href="https://www.getthaw.app/docs/thaw/shortcuts#ask-siri"><picture><source media="(prefers-color-scheme: dark)" srcset="https://www.shieldcn.dev/badge/Works_with-Siri.svg?variant=outline&amp;size=xs&amp;mode=dark&amp;font=geist&amp;logo=lu:AudioLines" /><img alt="Works with Siri" src="https://www.shieldcn.dev/badge/Works_with-Siri.svg?variant=outline&amp;size=xs&amp;mode=light&amp;font=geist&amp;logo=lu:AudioLines" /></picture></a>
</p>

<p align="center">
  <a href="https://vercel.com/open-source-program"><img alt="Vercel OSS Program" src="https://vercel.com/oss/program-badge-2026.svg" height="28" /></a>
  <a href="https://www.producthunt.com/products/thaw-2?embed=true&amp;utm_source=badge-featured&amp;utm_medium=badge&amp;utm_campaign=badge-thaw-3"><img alt="Thaw | Product Hunt" src="https://api.producthunt.com/widgets/embed-image/v1/featured.svg?post_id=1239794&amp;theme=light&amp;t=1788423441056" height="28" /></a>
  <a href="https://trendshift.io/repositories/21173"><img alt="thaw-app/Thaw | Trendshift" src="https://trendshift.io/api/badge/repositories/21173" height="28" /></a>
  <a href="https://www.star-history.com/thaw-app/thaw"><picture><source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/badge?repo=thaw-app/Thaw&amp;type=rank&amp;theme=dark" /><img alt="Star History Rank" src="https://api.star-history.com/badge?repo=thaw-app/Thaw&amp;type=rank" height="28" /></picture></a>
</p>

## Install

| macOS | Thaw | Homebrew |
|---|---|---|
| 15 to 26 | Thaw 2 | `brew install thaw`, or `brew install thaw@beta` on macOS 15 until Thaw 2.2 is out of beta |
| 27 | Thaw 3, in beta | `brew install thaw@beta` |

Without Homebrew, download the disk image from the [releases](https://github.com/thaw-app/Thaw/releases) and drag Thaw to Applications. [Versions and update channels](docs/VERSIONS.md) covers macOS 14 and the update channels.

Thaw asks for Accessibility to move menu bar items, and on macOS 27 for Menu Bar Layout Access, the one file where macOS keeps the menu bar's order. Screen Recording is optional; without it, items show as their app's icon. [Getting started](docs/GETTING_STARTED.md) walks through the first run.

## Features

- **Hide what you don't need.** Keep the items you look at in view and tuck the rest into a hidden section. Bring them back with a click, by hovering, by scrolling or with a shortcut.
- **Made for the notch.** A notch covers part of the menu bar on a MacBook. The Thaw Bar shows the items it would hide in a bar of their own, just below.
- **Search from the keyboard.** Find any menu bar item, hidden ones included, and open it. Recent items come first, and a shortcut opens an item by its letter.
- **Groups and folders.** Group items so they move and hide as one, even across sections. Show a group as a folder with its own icon and colour.
- **Profiles.** Save a whole setup and switch in one step, or bind it to a display, a Space or a Focus. Thaw shows what a profile would change before you apply it.
- **Zen Mode.** One shortcut hides every section and locks the ways to reveal them, then puts it all back. It can switch on by itself while you present or share your screen.
- **Style the bar.** Give the bar a shape, glass, a border, a shadow or a tint taken from your wallpaper. You can round the screen corners too, and keep a different look per Space or for light and dark.
- **Scriptable.** Drive Thaw with [`thaw://` links](docs/URI_SCHEMES.md) from a launcher, a shortcut or a script.
- **A privacy pane.** See what Thaw reads from your screen and every network call it makes, and switch them off.
- **Layout editor.** Arrange every item in one window, with the keyboard if you like. Rest on a tile and the item lights up in the real bar.

## Transparency

- Thaw is free, with nothing to buy or subscribe to, and a new macOS brings an update, not an upgrade fee.
- It is open source under GPL-3.0, so you can read the code and build it yourself.
- It has no account and sends no analytics or telemetry. [What Thaw sends over the network](docs/NETWORK.md) lists every connection it makes.
- Releases are signed and notarized by Apple, built to SLSA Build Level 3, and [verifiable](docs/VERIFYING_RELEASES.md). The project holds the [OpenSSF Best Practices](https://www.bestpractices.dev/projects/13303) Gold badge, its supply chain is rated by the [OpenSSF Scorecard](https://scorecard.dev/viewer/?uri=github.com/thaw-app/Thaw), and its test coverage is on [SonarCloud](https://sonarcloud.io/component_measures?id=thaw-app_Thaw&metric=coverage).

## Languages

Thaw is available in 20 languages, thanks to translators around the world. Missing yours, or spotted something off? [Translate Thaw on Crowdin](https://crowdin.com/project/thaw), where you can also ask for a new language. Everyone who has translated Thaw is named in [Credits](CREDITS.md).

## Contributors

Everyone who has contributed code or documentation is on the [community page](https://www.getthaw.app/community).

To help, start with [Ways to contribute](https://github.com/thaw-app/Thaw/issues/316) and the shared [contribution guidelines](https://github.com/thaw-app/.github/blob/main/.github/CONTRIBUTING.md). Pull requests go against the `development` branch.

For partnerships, integrations or sponsorship, [get in touch](https://github.com/sponsors/stonerl).

## Project documentation

The docs are at [getthaw.app/docs](https://www.getthaw.app/docs/thaw), built from the files in [`docs/`](docs). Start with [Getting started](https://www.getthaw.app/docs/thaw/getting-started), and see [Frequent issues](https://www.getthaw.app/docs/thaw/frequent-issues) if something looks wrong. The [changelog](https://www.getthaw.app/changelog) and the [roadmap](https://www.getthaw.app/roadmap) are there too.

These live on GitHub:

- [Contributing](https://github.com/thaw-app/.github/blob/main/.github/CONTRIBUTING.md)
- [Security policy](https://github.com/thaw-app/.github/blob/main/.github/SECURITY.md)
- [Governance](.github/GOVERNANCE.md)
- [Credits](CREDITS.md)

## License

Thaw is available under the [GPL-3.0 license](LICENSE). Linking with
PlatformRuntimeKit, the closed component that hides items, is allowed by an
[additional permission](LICENSE-EXCEPTION) under section 7.
