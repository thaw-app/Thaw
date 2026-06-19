<div align="center">
    <img alt="Thaw icon" src="Resources/NewIcon.png" width="200" height="200" />
    <h1>Thaw</h1>
</div>

Thaw is a powerful menu bar management tool for macOS 26. While its primary function is hiding and showing menu bar items, it aims to cover a wide variety of additional features to make it one of the most versatile menu bar tools available.

<div align="center">
<a href="https://trendshift.io/repositories/21173" target="_blank"><img src="https://trendshift.io/api/badge/repositories/21173" alt="stonerl%2FThaw | Trendshift" style="width: 250px; height: 55px;" width="250" height="55"/></a>

</div>

<br>

![thaw-banner](https://github.com/user-attachments/assets/9584065d-f840-4545-9a42-cfc5534b5ac3)

[![Download](https://img.shields.io/badge/download-latest-brightgreen?style=square)](https://github.com/stonerl/Thaw/releases/latest)
[![CI](https://img.shields.io/github/actions/workflow/status/stonerl/Thaw/ci.yml?style=square)](https://github.com/stonerl/Thaw/actions/workflows/ci.yml)
[![OpenSSF Best Practices](https://www.bestpractices.dev/projects/13303/badge)](https://www.bestpractices.dev/projects/13303)
![Requirements](https://img.shields.io/badge/requirements-macOS%2026%2B-fa4e49?style=square)
[![Sponsor](https://img.shields.io/badge/Sponsor%20%E2%9D%A4%EF%B8%8F-8A2BE2?style=square)](https://github.com/sponsors/stonerl)
[![Discord](https://img.shields.io/badge/Discord-7289DA?style=square&logo=discord&logoColor=white)](https://discord.gg/5cnKkKbMFd)
[![License](https://img.shields.io/github/license/stonerl/Thaw?style=square)](LICENSE)

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

## Translations

Thaw is currently available in the following languages:

<table frame="void" rules="none">
    <tr>
        <td>🇮🇩 <b>Bahasa Indonesia</b><br /><img alt="id translation" src="https://img.shields.io/badge/dynamic/json?color=blue&label=id&style=square&logo=crowdin&query=%24.progress.5.data.translationProgress&url=https%3A%2F%2Fbadges.awesome-crowdin.com%2Fstats-12858911-889934.json" /></td>
        <td>🇨🇿 <b>Čeština</b><br /><img alt="cs translation" src="https://img.shields.io/badge/dynamic/json?color=blue&label=cs&style=square&logo=crowdin&query=%24.progress.0.data.translationProgress&url=https%3A%2F%2Fbadges.awesome-crowdin.com%2Fstats-12858911-889934.json" /></td>
        <td>🇩🇪 🇦🇹 <b>Deutsch</b><br /><img alt="de translation" src="https://img.shields.io/badge/dynamic/json?color=blue&label=de&style=square&logo=crowdin&query=%24.progress.1.data.translationProgress&url=https%3A%2F%2Fbadges.awesome-crowdin.com%2Fstats-12858911-889934.json" /></td>
        <td>🇬🇧 🇺🇸 <b>English</b><br /><img alt="en translation" src="https://img.shields.io/badge/en-100%25-blue?style=square&logo=crowdin" /></td>
        <td>🇪🇸 🇲🇽 <b>Español</b><br /><img alt="es-ES translation" src="https://img.shields.io/badge/dynamic/json?color=blue&label=es-ES&style=square&logo=crowdin&query=%24.progress.2.data.translationProgress&url=https%3A%2F%2Fbadges.awesome-crowdin.com%2Fstats-12858911-889934.json" /></td>
    </tr>
    <tr>
        <td>🇫🇷 <b>Français</b><br /><img alt="fr translation" src="https://img.shields.io/badge/dynamic/json?color=blue&label=fr&style=square&logo=crowdin&query=%24.progress.3.data.translationProgress&url=https%3A%2F%2Fbadges.awesome-crowdin.com%2Fstats-12858911-889934.json" /></td>
        <td>🇮🇹 <b>Italiano</b><br /><img alt="it translation" src="https://img.shields.io/badge/dynamic/json?color=blue&label=it&style=square&logo=crowdin&query=%24.progress.6.data.translationProgress&url=https%3A%2F%2Fbadges.awesome-crowdin.com%2Fstats-12858911-889934.json" /></td>
        <td>🇯🇵 <b>日本語</b><br /><img alt="ja translation" src="https://img.shields.io/badge/dynamic/json?color=blue&label=ja&style=square&logo=crowdin&query=%24.progress.7.data.translationProgress&url=https%3A%2F%2Fbadges.awesome-crowdin.com%2Fstats-12858911-889934.json" /></td>
        <td>🇰🇷 <b>한국어</b><br /><img alt="ko translation" src="https://img.shields.io/badge/dynamic/json?color=blue&label=ko&style=square&logo=crowdin&query=%24.progress.8.data.translationProgress&url=https%3A%2F%2Fbadges.awesome-crowdin.com%2Fstats-12858911-889934.json" /></td>
        <td>🇭🇺 <b>Magyar</b><br /><img alt="hu translation" src="https://img.shields.io/badge/dynamic/json?color=blue&label=hu&style=square&logo=crowdin&query=%24.progress.4.data.translationProgress&url=https%3A%2F%2Fbadges.awesome-crowdin.com%2Fstats-12858911-889934.json" /></td>
    </tr>
    <tr>
        <td>🇳🇱 🇧🇪 <b>Nederlands</b><br /><img alt="nl translation" src="https://img.shields.io/badge/dynamic/json?color=blue&label=nl&style=square&logo=crowdin&query=%24.progress.9.data.translationProgress&url=https%3A%2F%2Fbadges.awesome-crowdin.com%2Fstats-12858911-889934.json" /></td>
        <td>🇧🇷 <b>Português (Brasil)</b><br /><img alt="pt-BR translation" src="https://img.shields.io/badge/dynamic/json?color=blue&label=pt-BR&style=square&logo=crowdin&query=%24.progress.11.data.translationProgress&url=https%3A%2F%2Fbadges.awesome-crowdin.com%2Fstats-12858911-889934.json" /></td>
        <td>🇷🇺 <b>Русский</b><br /><img alt="ru translation" src="https://img.shields.io/badge/dynamic/json?color=blue&label=ru&style=square&logo=crowdin&query=%24.progress.12.data.translationProgress&url=https%3A%2F%2Fbadges.awesome-crowdin.com%2Fstats-12858911-889934.json" /></td>
        <td>🇨🇳 <b>简体中文</b><br /><img alt="zh-CN translation" src="https://img.shields.io/badge/dynamic/json?color=blue&label=zh-CN&style=square&logo=crowdin&query=%24.progress.17.data.translationProgress&url=https%3A%2F%2Fbadges.awesome-crowdin.com%2Fstats-12858911-889934.json" /></td>
        <td>🇹🇼 <b>正體中文</b><br /><img alt="zh-TW translation" src="https://img.shields.io/badge/dynamic/json?color=blue&label=zh-TW&style=square&logo=crowdin&query=%24.progress.18.data.translationProgress&url=https%3A%2F%2Fbadges.awesome-crowdin.com%2Fstats-12858911-889934.json" /></td>
    </tr>
    <tr>
        <td>🇹🇭 <b>ภาษาไทย</b><br /><img alt="th translation" src="https://img.shields.io/badge/dynamic/json?color=blue&label=th&style=square&logo=crowdin&query=%24.progress.13.data.translationProgress&url=https%3A%2F%2Fbadges.awesome-crowdin.com%2Fstats-12858911-889934.json" /></td>
        <td>🇵🇱 <b>Polski</b><br /><img alt="pl translation" src="https://img.shields.io/badge/dynamic/json?color=blue&label=pl&style=square&logo=crowdin&query=%24.progress.10.data.translationProgress&url=https%3A%2F%2Fbadges.awesome-crowdin.com%2Fstats-12858911-889934.json" /></td>
        <td>🇹🇷 <b>Türkçe</b><br /><img alt="tr translation" src="https://img.shields.io/badge/dynamic/json?color=blue&label=tr&style=square&logo=crowdin&query=%24.progress.14.data.translationProgress&url=https%3A%2F%2Fbadges.awesome-crowdin.com%2Fstats-12858911-889934.json" /></td>
        <td>🇺🇦 <b>Українська(*)</b><br /><img alt="uk translation" src="https://img.shields.io/badge/dynamic/json?color=blue&label=uk&style=square&logo=crowdin&query=%24.progress.15.data.translationProgress&url=https%3A%2F%2Fbadges.awesome-crowdin.com%2Fstats-12858911-889934.json" /></td>
        <td>🇻🇳 <b>Tiếng Việt(*)</b><br /><img alt="vi translation" src="https://img.shields.io/badge/dynamic/json?color=blue&label=vi&style=square&logo=crowdin&query=%24.progress.16.data.translationProgress&url=https%3A%2F%2Fbadges.awesome-crowdin.com%2Fstats-12858911-889934.json" /></td>
    </tr>
</table>

_Note: languages marked with (\*) are currently only available in the development branch._

Help translate Thaw via [Crowdin](https://crowdin.com/project/thaw)

If a language you'd like to help to translate is not listed here, let us know and we will add it on Crowdin. 

## Features

<details>
<summary>Click to view the full list of features</summary>

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
- Menu bar item spacing (BETA)
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

### Other

- Launch at login
- Automatic updates

</details>

## Roadmap

Planned features, grouped by area:

- **Menu bar item management** — individual spacer items; menu bar item groups; show menu bar items when trigger conditions are met
- **Menu bar appearance** — rounded screen corners
- **Hotkeys** — enable/disable auto rehide; temporarily show individual menu bar items
- **Other** — menu bar widgets

## Gallery

> Click any screenshot to view it full size.

<table>
  <tr>
    <td align="center" width="50%">
      <a href="https://github.com/user-attachments/assets/f2f6b9a6-55c5-40b3-910f-b27b114577dd"><img alt="Item layout" src="https://github.com/user-attachments/assets/f2f6b9a6-55c5-40b3-910f-b27b114577dd" width="400" /></a><br />
      <sub><b>Item layout</b></sub>
    </td>
    <td align="center" width="50%">
      <a href="https://github.com/user-attachments/assets/c6ac6364-30f8-4c92-8f6f-9efe15f99573"><img alt="Show hidden menu bar items below the menu bar" src="https://github.com/user-attachments/assets/c6ac6364-30f8-4c92-8f6f-9efe15f99573" width="400" /></a><br />
      <sub><b>Show hidden items below the menu bar</b></sub>
    </td>
  </tr>
  <tr>
    <td align="center" width="50%">
      <a href="https://github.com/user-attachments/assets/54273d41-fcf3-4c9a-834b-e62a162a6b0c"><img alt="Drag-and-drop interface to arrange menu bar items" src="https://github.com/user-attachments/assets/54273d41-fcf3-4c9a-834b-e62a162a6b0c" width="400" /></a><br />
      <sub><b>Drag-and-drop arrangement</b></sub>
    </td>
    <td align="center" width="50%">
      <a href="https://github.com/user-attachments/assets/d95302df-26b0-4608-896e-4966c822fb5e"><img alt="Customize the menu bar's appearance" src="https://github.com/user-attachments/assets/d95302df-26b0-4608-896e-4966c822fb5e" width="400" /></a><br />
      <sub><b>Customize the appearance</b></sub>
    </td>
  </tr>
  <tr>
    <td align="center" width="50%">
      <a href="https://github.com/user-attachments/assets/ebafc745-7220-46c9-9297-f7a00ef6c15d"><img alt="Menu bar item search" src="https://github.com/user-attachments/assets/ebafc745-7220-46c9-9297-f7a00ef6c15d" width="400" /></a><br />
      <sub><b>Menu bar item search</b></sub>
    </td>
    <td width="50%"></td>
  </tr>
</table>

## Contributors

This project exists thanks to the awesome people who contribute code and documentation:

<a href="https://github.com/stonerl/Thaw/graphs/contributors"><img alt="Gallery of all contributors' profile photos" src="https://contrib.rocks/image?repo=stonerl/Thaw&columns=16" width="100%" /></a>

## Project Stats

<a href="https://star-history.com/#stonerl/Thaw&Date">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/svg?repos=stonerl/Thaw&type=Date&theme=dark" />
    <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/svg?repos=stonerl/Thaw&type=Date" />
    <img alt="Star History Chart" src="https://api.star-history.com/svg?repos=stonerl/Thaw&type=Date" width="100%" />
  </picture>
</a>

## License

Thaw is available under the [GPL-3.0 license](LICENSE).
