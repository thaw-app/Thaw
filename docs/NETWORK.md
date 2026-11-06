# What Thaw sends over the network

Thaw has no analytics and no tracking. It goes online for two things: updates, and the release notes that come with them. You can switch both off.

## Switch it all off

**Thaw 3**

1. Right-click Thaw's icon in the menu bar and choose **Settings…**.
2. Choose **Privacy**.
3. Under **Network access**, click **Turn Everything Off**.

**Thaw 2**

1. Right-click Thaw's icon in the menu bar and choose **Settings…**.
2. Choose **About**.
3. Turn off **Automatically check for updates**.

With these off, Thaw makes no network calls. You then update by hand, with Homebrew or from the [releases](https://github.com/thaw-app/Thaw/releases) page.

## What each call is

| Call | Goes to | Thaw 3 | Thaw 2 |
|---|---|---|---|
| Update check | `thaw-app.github.io` | **Automatic updates** in Privacy: Off, Check only, or Check and download | **Automatically check for updates** in About |
| Update download | GitHub, from the address the update check returns | The same setting | **Automatically download updates** in About |
| Release notes shown with an update | `thaw-app.github.io` | Follows the **Automatic updates** setting. It has no switch of its own. | Part of the update check |
| What's New notes | `raw.githubusercontent.com` | **What's New notes** in Privacy | Not in Thaw 2 |

Thaw 2 asks whether to check for updates the first time it opens. Thaw 3 asks during setup.

When **What's New notes** is off, Thaw 3 shows the last copy it fetched, if it has one.

## What does not count

Links that open in your browser, such as the repository or the sponsor page, are your browser's request and not Thaw's.

Every update is signed, and Thaw checks the signature before installing it. See [Releases and updates](RELEASES.md) for how that works.
