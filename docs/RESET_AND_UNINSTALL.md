# Reset or uninstall

If you are here because something broke, check [Frequent issues](../FREQUENT_ISSUES.md) first. The fix may be smaller than a reset.

## Reset the layout

Use this when items sit in the wrong section and dragging them does not fix it.

1. Right-click Thaw's icon in the menu bar and choose **Settings…**.
2. Choose **Layout**.
3. Click **Reset Layout…** and pick the section every item should go back to.

### If you cannot reach Settings

Thaw 2 can reset its saved layout from Terminal. Quit Thaw first, because a running Thaw writes its own copy back.

```sh
/Applications/Thaw.app/Contents/MacOS/Thaw --reset-layout
```

Then open Thaw again.

## Reset everything

This puts every setting back to its default. Your saved profiles are kept. It cannot be undone.

| Version | Where |
|---|---|
| Thaw 3 | **Settings → Troubleshooting → Reset Thaw…** |
| Thaw 2 | **Settings → Advanced → Reset Thaw** |

## More repairs in Thaw 3

**Settings → Troubleshooting** has a tool for each of these. Each one asks before it does anything.

| Problem | Tool | What it does |
|---|---|---|
| An app's item is gone | Restore Missing Items… | Brings items back without touching your layout |
| Apple's own items misbehave | Reset Control Center… | Quits Control Center and deletes its preference files so they rebuild |
| Items will not stay where you put them | Reset Positions… | Deletes the layout macOS saved and restarts the menu bar. A backup is saved first. |
| Icons look stale | Quit and Clear Cache… | Deletes Thaw's cache folder, then quits |
| A permission is stuck | Reset Permissions… | Clears Accessibility and Screen Recording for Thaw, then quits so you can grant them again |

## Uninstall

1. If you changed the menu bar spacing in Thaw 2, set it back to the default in **Settings → Displays** first. That setting belongs to macOS and stays after Thaw is gone.
2. Turn off **Launch at Login** in **Settings → General**.
3. Quit Thaw from the menu on its icon.
4. Remove the app. With Homebrew, run the line for what you installed:

   ```sh
   brew uninstall thaw
   brew uninstall thaw@beta
   ```

   Without Homebrew, drag Thaw from Applications to the Trash.

## Remove what is left

Thaw keeps its settings, profiles, cache and logs in your Library folder. Removing them is optional, and it deletes your saved profiles for good.

```sh
rm ~/Library/Preferences/com.stonerl.Thaw.plist
rm -rf ~/Library/Application\ Support/Thaw
rm -rf ~/Library/Application\ Support/com.stonerl.Thaw
rm -rf ~/Library/Caches/com.stonerl.Thaw
rm -rf ~/Library/Logs/Thaw
```

To clear the permissions you gave it:

```sh
tccutil reset Accessibility com.stonerl.Thaw
tccutil reset ScreenCapture com.stonerl.Thaw
```

If you skipped step 1 and the spacing is still changed, these put it back. Log out and in again afterwards.

```sh
defaults -currentHost delete -globalDomain NSStatusItemSpacing
defaults -currentHost delete -globalDomain NSStatusItemSelectionPadding
```
