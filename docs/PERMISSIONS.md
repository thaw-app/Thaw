# Permissions

## What Thaw asks for

| Permission | Do you need it? | What Thaw does with it |
|---|---|---|
| Accessibility | Yes | Moves menu bar items. Without it, nothing can be hidden. |
| Menu Bar Layout Access | Only with Thaw 3 on macOS 27 | Reads the one file where macOS 27 keeps the menu bar's order. |
| Screen Recording | No | Draws live previews of items and takes a tint from your wallpaper. |

Thaw asks for the ones it needs the first time it opens. Some optional features ask for more when you switch them on.

## Grant or check a permission

1. Right-click Thaw's icon in the menu bar and choose **Settings…**.
2. In Thaw 2, choose **Advanced**, then **Permissions**. In Thaw 3, choose **Privacy**.
3. Grant the one that is missing.

## Accessibility

Thaw needs it to move items between sections. Hiding, revealing and rearranging all depend on it.

To reset it and be asked again, run this in Terminal:

```sh
tccutil reset Accessibility com.stonerl.Thaw
```

Then open Thaw and grant it when the prompt appears.

## Menu Bar Layout Access

This is for Thaw 3 on macOS 27. Thaw 2 does not ask for it.

macOS 27 keeps the menu bar's order in one protected file. Thaw shows a panel, you pick that file, and Thaw can read that file and no other. With it, items move into place without your pointer moving.

If you decline, Thaw offers Full Disk Access as a fallback. It never asks for that first.

## Screen Recording

You can refuse this one. Hiding, revealing and moving items in the menu bar work without it.

What you lose depends on your version:

| | Thaw 3 | Thaw 2 |
|---|---|---|
| Thaw Bar, search and Layout settings | Each item is drawn as its app's icon | They cannot show your items |
| Tooltips | Off | Off |
| Wallpaper tint | Off | Off |

On Thaw 2, grant it if you want the Thaw Bar or search.

### macOS keeps asking after you said yes

1. Open **System Settings → Privacy & Security → Screen Recording**.
2. Remove Thaw from the list.
3. Add it again.

## Apps that control Thaw

An app that changes Thaw's settings through `thaw://` links has to be authorized first. The first time, Thaw shows a dialog with the app's name and what it wants. See [URL schemes](URI_SCHEMES.md).

If items still do not move after Accessibility is granted, see [Frequent issues](../FREQUENT_ISSUES.md).
