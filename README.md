<div align="center">
    <img src="Resources/Icon.svg" width=200 height=200>
    <h1>Thaw</h1>
</div>

Thaw is a powerful menu bar management tool for macOS 26. While its primary function is hiding and showing menu bar items, it aims to cover a wide variety of additional features to make it one of the most versatile menu bar tools available.

![thaw-banner](https://github.com/user-attachments/assets/9584065d-f840-4545-9a42-cfc5534b5ac3)

[![Download](https://img.shields.io/badge/download-latest-brightgreen?style=flat-square)](https://github.com/stonerl/Thaw/releases/latest)
[![CI](https://img.shields.io/github/actions/workflow/status/stonerl/Thaw/ci.yml?style=flat-square)](https://github.com/stonerl/Thaw/actions/workflows/ci.yml)
![Platform](https://img.shields.io/badge/platform-macOS-blue?style=flat-square)
![Requirements](https://img.shields.io/badge/requirements-macOS%2014%2B-fa4e49?style=flat-square)
[![Sponsor](https://img.shields.io/badge/Sponsor%20%E2%9D%A4%EF%B8%8F-8A2BE2?style=flat-square)](https://github.com/sponsors/stonerl)
[![Discord](https://img.shields.io/badge/Discord-7289DA?style=flat-square&logo=discord&logoColor=white)](https://discord.gg/5cnKkKbMFd)
[![License](https://img.shields.io/github/license/stonerl/Thaw?style=flat-square)](LICENSE)

> [!NOTE]
> **Thaw** is a fork of [Ice](https://github.com/jordanbaird/Ice) by Jordan Baird.
> As the original project appears to be inactive, Thaw aims to keep the project alive fixing bugs, ensuring compatibility with the latest macOS releases, and eventually implementing the remaining roadmap features.

## Install

### Manual Installation

Download the `Thaw_1.x.x.zip` file from the [latest release](https://github.com/stonerl/Thaw/releases/latest) and move the unzipped app into your `Applications` folder.

### Homebrew

Install the latest stable release:

```sh
brew install thaw
```

To get the latest beta (or stable, whichever is newer):

```sh
brew install thaw@beta
```

## Translations

Thaw is currently available in the following languages:

<table frame="void" rules="none">
    <tr>
        <th align="left">Language</th>
        <th align="center">Flag</th>
        <th align="left">Translation</th>
        <th width="30"></th>
        <th align="left">Language</th>
        <th align="center">Flag</th>
        <th align="left">Translation</th>
    </tr>
    <tr>
        <td><b>Bahasa Indonesia</b></td>
        <td align="center">🇮🇩</td>
        <td><img alt="id translation" src="https://img.shields.io/badge/dynamic/json?color=blue&label=id&style=flat-square&logo=crowdin&query=%24.progress.5.data.translationProgress&url=https%3A%2F%2Fbadges.awesome-crowdin.com%2Fstats-12858911-889934.json" /></td>
        <td></td>
        <td><b>Čeština</b></td>
        <td align="center">🇨🇿</td>
        <td><img alt="cs translation" src="https://img.shields.io/badge/dynamic/json?color=blue&label=cs&style=flat-square&logo=crowdin&query=%24.progress.0.data.translationProgress&url=https%3A%2F%2Fbadges.awesome-crowdin.com%2Fstats-12858911-889934.json" /></td>
    </tr>
    <tr>
        <td><b>Deutsch</b></td>
        <td align="center">🇩🇪/🇦🇹</td>
        <td><img alt="de translation" src="https://img.shields.io/badge/dynamic/json?color=blue&label=de&style=flat-square&logo=crowdin&query=%24.progress.1.data.translationProgress&url=https%3A%2F%2Fbadges.awesome-crowdin.com%2Fstats-12858911-889934.json" /></td>
        <td></td>
        <td><b>English</b></td>
        <td align="center">🇬🇧/🇺🇸</td>
        <td><img src="https://img.shields.io/badge/100%25-blue?style=flat-square" /></td>
    </tr>
    <tr>
        <td><b>Español</b></td>
        <td align="center">🇪🇸/🇲🇽</td>
        <td><img alt="es-ES translation" src="https://img.shields.io/badge/dynamic/json?color=blue&label=es-ES&style=flat-square&logo=crowdin&query=%24.progress.2.data.translationProgress&url=https%3A%2F%2Fbadges.awesome-crowdin.com%2Fstats-12858911-889934.json" /></td>
        <td></td>
        <td><b>Français</b></td>
        <td align="center">🇫🇷</td>
        <td><img alt="fr translation" src="https://img.shields.io/badge/dynamic/json?color=blue&label=fr&style=flat-square&logo=crowdin&query=%24.progress.3.data.translationProgress&url=https%3A%2F%2Fbadges.awesome-crowdin.com%2Fstats-12858911-889934.json" /></td>
    </tr>
    <tr>
        <td><b>Italiano</b></td>
        <td align="center">🇮🇹</td>
        <td><img alt="it translation" src="https://img.shields.io/badge/dynamic/json?color=blue&label=it&style=flat-square&logo=crowdin&query=%24.progress.6.data.translationProgress&url=https%3A%2F%2Fbadges.awesome-crowdin.com%2Fstats-12858911-889934.json" /></td>
        <td></td>
        <td><b>日本語</b></td>
        <td align="center">🇯🇵</td>
        <td><img alt="ja translation" src="https://img.shields.io/badge/dynamic/json?color=blue&label=ja&style=flat-square&logo=crowdin&query=%24.progress.7.data.translationProgress&url=https%3A%2F%2Fbadges.awesome-crowdin.com%2Fstats-12858911-889934.json" /></td>
    </tr>
    <tr>
        <td><b>한국어</b></td>
        <td align="center">🇰🇷</td>
        <td><img alt="ko translation" src="https://img.shields.io/badge/dynamic/json?color=blue&label=ko&style=flat-square&logo=crowdin&query=%24.progress.8.data.translationProgress&url=https%3A%2F%2Fbadges.awesome-crowdin.com%2Fstats-12858911-889934.json" /></td>
        <td></td>
        <td><b>Magyar</b></td>
        <td align="center">🇭🇺</td>
        <td><img alt="hu translation" src="https://img.shields.io/badge/dynamic/json?color=blue&label=hu&style=flat-square&logo=crowdin&query=%24.progress.4.data.translationProgress&url=https%3A%2F%2Fbadges.awesome-crowdin.com%2Fstats-12858911-889934.json" /></td>
    </tr>
    <tr>
        <td><b>Nederlands</b></td>
        <td align="center">🇳🇱/🇧🇪</td>
        <td><img alt="nl translation" src="https://img.shields.io/badge/dynamic/json?color=blue&label=nl&style=flat-square&logo=crowdin&query=%24.progress.9.data.translationProgress&url=https%3A%2F%2Fbadges.awesome-crowdin.com%2Fstats-12858911-889934.json" /></td>
        <td></td>
        <td><b>Português (Brasil)</b></td>
        <td align="center">🇧🇷</td>
        <td><img alt="pt-BR translation" src="https://img.shields.io/badge/dynamic/json?color=blue&label=pt-BR&style=flat-square&logo=crowdin&query=%24.progress.11.data.translationProgress&url=https%3A%2F%2Fbadges.awesome-crowdin.com%2Fstats-12858911-889934.json" /></td>
    </tr>
    <tr>
        <td><b>Русский</b></td>
        <td align="center">🇷🇺</td>
        <td><img alt="ru translation" src="https://img.shields.io/badge/dynamic/json?color=blue&label=ru&style=flat-square&logo=crowdin&query=%24.progress.12.data.translationProgress&url=https%3A%2F%2Fbadges.awesome-crowdin.com%2Fstats-12858911-889934.json" /></td>
        <td></td>
        <td><b>简体中文</b></td>
        <td align="center">🇨🇳</td>
        <td><img alt="zh-CN translation" src="https://img.shields.io/badge/dynamic/json?color=blue&label=zh-CN&style=flat-square&logo=crowdin&query=%24.progress.17.data.translationProgress&url=https%3A%2F%2Fbadges.awesome-crowdin.com%2Fstats-12858911-889934.json" /></td>
    </tr>
    <tr>
        <td><b>正體中文</b></td>
        <td align="center">🇹🇼</td>
        <td><img alt="zh-TW translation" src="https://img.shields.io/badge/dynamic/json?color=blue&label=zh-TW&style=flat-square&logo=crowdin&query=%24.progress.18.data.translationProgress&url=https%3A%2F%2Fbadges.awesome-crowdin.com%2Fstats-12858911-889934.json" /></td>
        <td></td>
        <td><b>ภาษาไทย</b></td>
        <td align="center">🇹🇭</td>
        <td><img alt="th translation" src="https://img.shields.io/badge/dynamic/json?color=blue&label=th&style=flat-square&logo=crowdin&query=%24.progress.13.data.translationProgress&url=https%3A%2F%2Fbadges.awesome-crowdin.com%2Fstats-12858911-889934.json" /></td>
    </tr>
    <tr>
        <td><b>Polski</b></td>
        <td align="center">🇵🇱</td>
        <td><img alt="pl translation" src="https://img.shields.io/badge/dynamic/json?color=blue&label=pl&style=flat-square&logo=crowdin&query=%24.progress.10.data.translationProgress&url=https%3A%2F%2Fbadges.awesome-crowdin.com%2Fstats-12858911-889934.json" /></td>
        <td></td>
        <td><b>Türkçe</b></td>
        <td align="center">🇹🇷</td>
        <td><img alt="tr translation" src="https://img.shields.io/badge/dynamic/json?color=blue&label=tr&style=flat-square&logo=crowdin&query=%24.progress.14.data.translationProgress&url=https%3A%2F%2Fbadges.awesome-crowdin.com%2Fstats-12858911-889934.json" /></td>
    </tr>
    <tr>
        <td><b>Українська(*)</b></td>
        <td align="center">🇺🇦</td>
        <td><img alt="uk translation" src="https://img.shields.io/badge/dynamic/json?color=blue&label=uk&style=flat-square&logo=crowdin&query=%24.progress.15.data.translationProgress&url=https%3A%2F%2Fbadges.awesome-crowdin.com%2Fstats-12858911-889934.json" /></td>
        <td></td>
        <td><b>Tiếng Việt(*)</b></td>
        <td align="center">🇻🇳</td>
        <td><img alt="vi translation" src="https://img.shields.io/badge/dynamic/json?color=blue&label=vi&style=flat-square&logo=crowdin&query=%24.progress.16.data.translationProgress&url=https%3A%2F%2Fbadges.awesome-crowdin.com%2Fstats-12858911-889934.json" /></td>
    </tr>
</table>

_Note: languages marked with (\*) are currently only available in the development branch._

Help translate Thaw via [Crowdin](https://crowdin.com/project/thaw)

## Features/Roadmap

<details>
<summary>Click to view the full Features & Roadmap list</summary>

### Menu bar item management

- [x] Hide menu bar items
- [x] "Always-hidden" menu bar section
- [x] Show hidden menu bar items when hovering over the menu bar
- [x] Show hidden menu bar items when an empty area in the menu bar is clicked
- [x] Show hidden menu bar items by scrolling or swiping in the menu bar
- [x] Automatically rehide menu bar items
- [x] Hide application menus when they overlap with shown menu bar items
- [x] Drag and drop interface to arrange individual menu bar items
- [x] Display hidden menu bar items in a separate bar (e.g. for MacBooks with the notch)
- [x] Search menu bar items
- [x] Menu bar item spacing (BETA)
- [x] Profiles for menu bar layout
- [ ] Individual spacer items
- [ ] Menu bar item groups
- [ ] Show menu bar items when trigger conditions are met

### Menu bar appearance

- [x] Menu bar tint (solid and gradient)
- [x] Menu bar shadow
- [x] Menu bar border
- [x] Custom menu bar shapes (rounded and/or split)
- [x] Remove background behind menu bar (macOS setting)
- [ ] Rounded screen corners
- [x] Different settings for light/dark mode

### Hotkeys

- [x] Toggle individual menu bar sections
- [x] Show the search panel
- [x] Enable/disable the Thaw Bar
- [x] Show/hide section divider icons
- [x] Toggle application menus
- [ ] Enable/disable auto rehide
- [ ] Temporarily show individual menu bar items

### Other

- [x] Launch at login
- [x] Automatic updates
- [ ] Menu bar widgets

</details>

## Gallery

### Item layout

<img width="1760" height="956" alt="thaw-items-fs8" src="https://github.com/user-attachments/assets/f2f6b9a6-55c5-40b3-910f-b27b114577dd" />

### Show hidden menu bar items below the menu bar

<img width="1760" height="400" alt="thaw-hidden-fs8" src="https://github.com/user-attachments/assets/c6ac6364-30f8-4c92-8f6f-9efe15f99573" />

### Drag-and-drop interface to arrange menu bar items

<img width="1760" height="800" alt="thaw-layout-fs8" src="https://github.com/user-attachments/assets/54273d41-fcf3-4c9a-834b-e62a162a6b0c" />

### Customize the menu bar's appearance

<img width="1760" height="956" alt="thaw-appearance-fs8" src="https://github.com/user-attachments/assets/d95302df-26b0-4608-896e-4966c822fb5e" />

### Menu bar item search

<img width="1760" height="956" alt="thaw-search-fs8" src="https://github.com/user-attachments/assets/ebafc745-7220-46c9-9297-f7a00ef6c15d" />

## License

Thaw is available under the [GPL-3.0 license](LICENSE).

## Project Stats

<a href="https://star-history.com/#stonerl/Thaw&Date">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/svg?repos=stonerl/Thaw&type=Date&theme=dark" />
    <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/svg?repos=stonerl/Thaw&type=Date" />
    <img alt="Star History Chart" src="https://api.star-history.com/svg?repos=stonerl/Thaw&type=Date" width="100%" />
  </picture>
</a>
