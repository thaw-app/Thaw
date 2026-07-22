Thaw is a powerful menu bar management tool for macOS. Stable releases target **macOS 26+**. macOS 27 (Golden Gate) support is in preview — see the tracking issue below. While its primary function is hiding and showing menu bar items, it aims to cover a wide variety of additional features to make it one of the most versatile menu bar tools available.

**[macOS 27 (Golden Gate) status and preview builds](https://github.com/stonerl/Thaw/issues/687)**

thaw-banner

[Download](https://github.com/stonerl/Thaw/releases/latest)
[CI](https://github.com/stonerl/Thaw/actions/workflows/ci.yml)
[OpenSSF Best Practices](https://www.bestpractices.dev/projects/13303)
Requirements
[Sponsor](https://github.com/sponsors/stonerl)
[Discord](https://discord.gg/5cnKkKbMFd)
[License](LICENSE)

> [!NOTE]
> **Thaw** is a fork of [Ice](https://github.com/jordanbaird/Ice) by Jordan Baird.
> As the original project appears to be inactive, Thaw aims to keep the project alive fixing bugs, ensuring compatibility with the latest macOS releases, and eventually implementing the remaining roadmap features.

## Install

### Manual Installation

Download the `Thaw_<version>.zip` file from the [latest release](https://github.com/stonerl/Thaw/releases/latest) and move the unzipped app into your `Applications` folder.

### Homebrew

Install the latest stable release:

```sh
brew install thaw
```

To get the latest beta (or stable, whichever is newer):

```sh
brew install thaw@beta
```

Having trouble after installing? Check [Frequent Issues](FREQUENT_ISSUES.md) before opening a new report.

## Contributing

Pull requests are welcome. Please open them against the `development` branch (not `main`), follow the PR template, and read [Contributing](.github/CONTRIBUTING.md).

**Translations** are managed on [Crowdin](https://crowdin.com/project/thaw) — translation PRs are not accepted in this repo.

## Translations

Thaw is currently available in the following languages:

|                         |                           |                   |                     |                     |
| ----------------------- | ------------------------- | ----------------- | ------------------- | ------------------- |
| 🇮🇩 **Bahasa Indonesia** | 🇨🇿 **Čeština**            | 🇩🇪 🇦🇹 **Deutsch** | 🇬🇧 🇺🇸 **English**   | 🇪🇸 🇲🇽 **Español**   |
| 🇫🇷 **Français**         | 🇮🇹 **Italiano**           | 🇯🇵 **日本語**     | 🇰🇷 **한국어**       | 🇭🇺 **Magyar**       |
| 🇳🇱 🇧🇪 **Nederlands**    | 🇧🇷 **Português (Brasil)** | 🇷🇺 **Русский**    | 🇨🇳 **简体中文**     | 🇹🇼 **正體中文**     |
| 🇹🇭 **ภาษาไทย**          | 🇵🇱 **Polski**             | 🇹🇷 **Türkçe**     | 🇺🇦 **Українська()** | 🇻🇳 **Tiếng Việt()** |

_Note: languages marked with () are currently only available in the development branch._

Help translate Thaw via [Crowdin](https://crowdin.com/project/thaw).

If a language you'd like to help translate is not listed here, let us know and we will add it on Crowdin.

## Features

Click to view the full features list

### Menu bar item management

- Hide menu bar items
- "Always-hidden" menu bar section
- Show hidden menu bar items when hovering over the menu bar
- Show hidden menu bar items when an empty area in the menu bar is clicked
- Show hidden menu bar items by scrolling or swiping in the menu bar
- Automatically rehide menu bar items
- Hide application menus when they overlap with shown menu bar items
- Drag and drop interface to arrange individual menu bar items
- Display hidden menu bar items in a separate bar (e.g. for MacBooks with the notch)
- Search menu bar items
- Menu bar item spacing
- Profiles for menu bar layout

### Menu bar appearance

- Menu bar tint (solid and gradient)
- Menu bar shadow
- Menu bar border
- Custom menu bar shapes (rounded and/or split)
- Remove background behind menu bar (macOS setting)
- Different settings for light/dark mode

### Hotkeys

- Toggle individual menu bar sections
- Show the search panel
- Enable/disable the Thaw Bar
- Show/hide section divider icons
- Toggle application menus

## Roadmap

Click to view the roadmap

- **Menu bar item management** — individual spacer items; menu bar item groups; show menu bar items when trigger conditions are met
- **Menu bar appearance** — rounded screen corners
- **Hotkeys** — enable/disable auto rehide; temporarily show individual menu bar items
- **Other** — menu bar widgets

## Gallery

> Click any screenshot to view it full size.

|                               |                                          |
| ----------------------------- | ---------------------------------------- |
| **Item layout**               | **Show hidden items below the menu bar** |
| **Drag-and-drop arrangement** | **Customize the appearance**             |
| **Menu bar item search**      |                                          |

## Contributors

This project exists thanks to the awesome people who contribute code and documentation:

## Project Stats

## License

Thaw is available under the [GPL-3.0 license](LICENSE).
