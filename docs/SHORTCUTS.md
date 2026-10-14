# Shortcuts and automation

## Set a keyboard shortcut

Thaw ships with no shortcuts set. You choose the keys.

1. Right-click Thaw's icon in the menu bar and choose **Settings…**.
2. Choose **Shortcuts**. In Thaw 2 the pane is called **Hotkeys**.
3. Click an action and press the keys you want.

| Action | Thaw 2 | Thaw 3 |
|---|---|---|
| Toggle the Hidden section | Yes | Yes |
| Toggle the Always Hidden section | Yes | Yes |
| Search menu bar items | Yes | Yes |
| Turn the Thaw Bar on or off | Yes | Yes |
| Toggle application menus | Yes | Yes |
| Apply a profile | Yes | Yes |
| Open one item's menu | Yes | Yes |
| Swap shown and hidden items | | Yes |
| Toggle automatic rehiding | | Yes |
| Toggle Zen Mode | | Yes |
| Open an item by letter | | Yes |
| Show Thaw Bar Only items | | Yes |
| Reveal the menu bar | | Yes |
| Show Layout | | Yes |

A few keys are fixed, and work while Thaw's own menu is open. **⌘,** opens Settings. In Thaw 3, **⌘Q** quits and **⌥⌘Q** restarts.

## Shortcuts and Spotlight

This is in the Thaw 3 beta. Open the Shortcuts app, add an action, and search for "Thaw". The same actions turn up in Spotlight.

| Action | What it does |
|---|---|
| Show Hidden Menu Bar Items | Shows the Hidden section |
| Toggle Hidden Menu Bar Items | Shows or hides the Hidden section |
| Toggle Always Hidden Menu Bar Items | Shows or hides the Always Hidden section |
| Reveal Hidden Menu Bar Section, Hide Menu Bar Section | Shows or hides the section you choose |
| Swap Shown and Hidden Items | Swaps what is in view with what is hidden |
| Toggle Zen Mode | Turns Zen Mode on or off |
| Toggle Application Menus | Shows or hides the app's menus |
| Open Menu Bar Item | Opens the menu of the item you choose, revealing it first if it is hidden |
| Reveal Menu Bar Item | Brings one item into view |
| Apply Menu Bar Profile | Switches to the profile you choose |
| Open Thaw Settings | Opens Settings |

### Ask Siri

Seven of these actions have phrases Siri understands, with no setup. Say the phrase as written, with "Thaw" in it.

| Say | What it does |
|---|---|
| "What is Thaw hiding" | Lists the hidden items |
| "Toggle hidden menu bar items in Thaw" | Shows or hides the Hidden section |
| "Swap the menu bar with Thaw" | Swaps what is in view with what is hidden |
| "Turn on zen mode in Thaw" | Turns Zen Mode on or off |
| "Switch Thaw to Work" | Switches to the profile you name |
| "Open Wi-Fi in Thaw" | Opens the item you name |
| "Open Thaw settings" | Opens Settings |

## Focus

Both versions add a Focus filter that sets a menu bar profile. In Thaw 3 it is called **Set Menu Bar Profile**. Add it under **System Settings → Focus**, pick a Focus, then **Focus Filters**. Thaw switches to that profile when the Focus starts. When it ends, Thaw applies the profile set for the current display, if there is one.

## Control Center

This is in the Thaw 3 beta. Thaw adds two controls you can place in Control Center:

- **Reveal Hidden Items**
- **Toggle Zen Mode**

## More thaw:// links

The [URL schemes](URI_SCHEMES.md) page covers Thaw 2. Thaw 3 also answers these:

| Link | What it does |
|---|---|
| `thaw://toggle-swap` | Swaps shown and hidden items |
| `thaw://toggle-zen-mode` | Turns Zen Mode on or off |
| `thaw://toggle-layout-editor` | Opens or closes the quick layout editor, without opening Settings |
| `thaw://item-hints` | Shows or hides the letters for opening an item by letter |

Run one from Terminal to try it:

```sh
open "thaw://toggle-zen-mode"
```

Thaw 3 also has links that list items, open an item, and list or apply profiles. An app has to be authorized before it can use them, the same way as for changing settings.
