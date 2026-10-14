# Getting started

## 1. Install

Choose the option for your macOS: a Homebrew command to run in Terminal, or a download. To see which macOS you have, open the Apple menu and choose **About This Mac**.

| Your Mac runs | Run this | You get |
|---|---|---|
| macOS 27 | `brew install thaw@beta` | Thaw 3, in beta |
| macOS 26 | `brew install thaw` | Thaw 2, the stable release |
| macOS 14 or 15 | Download from the [releases](https://github.com/thaw-app/Thaw/releases) | Thaw 1 |

No Homebrew? Download the disk image for your macOS from the [releases](https://github.com/thaw-app/Thaw/releases) and drag Thaw to Applications.

Then open Thaw from Applications.

## 2. Say yes to the prompts

Thaw asks for what it needs the first time it opens.

| Permission | Do you need it? | Why |
|---|---|---|
| Accessibility | Yes | Thaw moves menu bar items with it. Without it, nothing can be hidden. |
| Menu Bar Layout Access | Only on macOS 27 | macOS 27 keeps the menu bar's order in one protected file. You pick that file in a panel, and Thaw can read that file and no other. |
| Screen Recording | No | It adds live previews and a tint taken from your wallpaper. Without it, items show as their app's icon. |

More on each one is under [Permissions](PERMISSIONS.md).

## 3. Hide one item

1. Hold **⌘ Command**.
2. Drag an item you rarely look at along the menu bar into the Hidden section.
3. Let go.

Not sure where Hidden starts? Click Thaw's icon. The items that appear are the Hidden section, and clicking again hides them.

Once the item is in Hidden, it stays out of the menu bar until you click Thaw's icon.

### Or arrange them in Settings

1. Right-click Thaw's icon in the menu bar and choose **Settings…**.
2. Choose **Layout**.
3. Drag the item from **Visible** into **Hidden**.

On Thaw 3, Settings opens as one page with no sidebar if you kept Simple Mode. Switch off **Simple Mode** to see **Layout**.

## If something looks wrong

### An item disappeared

Thaw cannot delete an item. It is in **Hidden**, or in **Always Hidden** if you switched that section on.

1. Click Thaw's icon to show the Hidden section.
2. Hold **⌘ Command** and drag the item back to the visible part of the menu bar.

### Thaw's own icon is missing

1. Run this in Terminal to open Settings:

   ```sh
   open "thaw://open-settings"
   ```

2. Turn on **General → Show Thaw icon**.
3. On macOS 27, also turn on **System Settings → Menu Bar → Allow in Menu Bar → Thaw**.

Still missing? See [Thaw's own icon is missing](../FREQUENT_ISSUES.md#thaws-own-icon-is-missing-how-to-open-settings).

## Next

Hide two more items you never look at.

After that:

- [Permissions](PERMISSIONS.md) says what each one is for.
- [Versions and update channels](VERSIONS.md) covers betas.
- [Frequent issues](../FREQUENT_ISSUES.md) has fixes for the problems people hit most often.
- [Verifying releases](VERIFYING_RELEASES.md) shows how to check that a download came from the Thaw team.
