# Where Thaw keeps its files

This page lists the files and folders Thaw 3 writes in your home folder, and says which ones you can copy to another Mac or keep in a dotfiles tool such as chezmoi.

The paths are for Thaw 3 on macOS 27. Thaw 2 uses the same preferences file, profiles folder and log folder. Its other files are not covered here.

## Move your settings to another Mac

Profiles are the supported way. A profile holds your layout, appearance, shortcuts and most settings, and Thaw can save profiles to a file and read them back. Export writes saved profiles only, so save your current settings as a profile first.

1. On the first Mac, right-click Thaw's icon in the menu bar and choose **Settings…**. If Settings shows a single page, click **All Settings**.
2. Choose **Profiles**. To keep your current settings, type a name and click **Save Current**.
3. Click **Export Profiles…**. To save one profile, use **Export…** in that profile's menu.
4. On the other Mac, open the same page, click **Import Profiles…** and pick the file.
5. Click **Apply** on the profile you want.

An imported profile comes with its scripts switched off. Switch each one on yourself after you have checked it. A profile linked to a display or a Space on the first Mac keeps that link, but a Space from another Mac never matches.

## Files and folders

`com.stonerl.Thaw` is the released app. Thaw Debug, the build developers run, uses `com.stonerl.Thaw.debug` in the same places. Where Thaw Debug shares a file with the released app, the table says so.

### Settings and profiles

| Path | What it holds | Sync it? |
|---|---|---|
| `~/Library/Preferences/com.stonerl.Thaw.plist` | Your settings, the update channel, the updater's own keys (they start with `SU`), and access you granted to files | Only with care. See [The preferences file](#the-preferences-file). |
| `~/Library/Preferences/com.stonerl.Thaw.debug.plist` | The same, for Thaw Debug | No |
| `~/Library/Application Support/Thaw/Profiles/` | One `.json` file per profile, and `profiles.json`, which lists them with their display and Space links. Thaw Debug uses this folder too. | Yes. Quit Thaw before you replace it. Export and import is safer. |

### Files Thaw rebuilds

You can delete these and Thaw makes them again. None of them belong in dotfiles.

| Path | What it holds |
|---|---|
| `~/Library/Caches/com.stonerl.Thaw/imageCache.plist` | Pictures of menu bar items, so they show right away after a restart |
| `~/Library/Caches/release-notes.md` | The last copy of the What's New notes. Thaw Debug shares it. |
| `~/Library/Application Support/com.stonerl.Thaw/Tips/` | Which tips you have seen |
| `~/Library/Application Support/com.stonerl.Thaw/StandIns/` | What Thaw's helper items show, and which of them to hide |
| `~/Library/Application Support/Thaw/Thaw.instance.lock` | Stops two copies of Thaw running at once. Thaw Debug shares it. |
| `~/Library/Group Containers/A7CKWF99ML.com.stonerl.Thaw/` | Whether Thaw's Control Center controls show as on. Thaw clears it when it quits. Thaw Debug shares it. |

### Logs and diagnostics

Thaw writes these only when you ask for them. Don't sync them.

| Path | What it holds |
|---|---|
| `~/Library/Logs/Thaw/thaw_<date>.log` | The detailed log, written while **Settings → Troubleshooting → Detailed logging** is on. Thaw Debug writes here too. |
| `~/Library/Logs/Thaw/item-dump-<time>.json` | A list of menu bar items, written by the `thaw://dump-items` link |
| `ThawCaptureDiagnostics-<number>` in your temporary folder | Sample item pictures, saved while detailed logging is on |

Thaw also saves a backup of the menu bar layout before **Rebuild Saved Layout…** and before it restores a backup. To find them, open **Settings → Troubleshooting** and click **Show Backups in Finder** under **Layout backups**. A backup holds this Mac's layout, so keep it on this Mac.

### Helpers

Thaw ships small helper apps inside its own bundle. Two of them keep a setting of their own.

| Path | What it holds | Sync it? |
|---|---|---|
| `~/Library/Preferences/com.stonerl.Thaw.extra.focus.plist` | Access you granted to the Focus folder, so Thaw's Focus item can show which Focus is on | No |
| `~/Library/Preferences/com.stonerl.Thaw.extra.timemachine.plist` | Whether **Show Only While Backing Up** is on for Thaw's Time Machine item | Yes |

Thaw stores no settings for its other helpers, for the screen capture service or for the Control Center controls. ThawCtl, a tool for developers that is not part of the app, stores none either.

## The preferences file

Most of `com.stonerl.Thaw.plist` is safe on another Mac. Some keys only make sense on the Mac that wrote them.

| Keys | Why they stay on this Mac |
|---|---|
| `MenuBarLayoutTableBookmark`, `NativeAppHidingAppListBookmark`, `NativeVisibilityRecoveryFileBookmark` | Access you granted to one file. macOS ties it to this Mac, so on another Mac it does not work and you grant access again. |
| `DisplayIceBarConfigurations`, `KnownDisplays`, and keys that start with `MenuBarSearchPanelFrame_` | Settings for each display, stored under this Mac's display IDs |
| `UnresponsiveMenuBarItems`, `CannotCompleteMenuBarItems`, `StrandedMenuBarItems`, `MenuBarFailureLedgerVersion` | What Thaw learned about the items on this Mac |
| Keys that start with `SU` | The updater's own record of checks on this Mac |

If you keep the file in dotfiles:

1. Quit Thaw before you replace it. A running Thaw writes its own copy back.
2. Leave out the keys above.
3. Expect to grant Accessibility and Menu Bar Layout Access again on the new Mac. Permissions are not stored in this file. See [Permissions](PERMISSIONS.md).

macOS 27 keeps the order of menu bar items in its own file, not in Thaw's. Thaw's file says which section each item belongs in.

## Settings that belong to macOS

Thaw changes a few settings that macOS owns. They belong to this Mac, so keep them out of dotfiles.

- **Menu bar spacing.** `NSStatusItemSpacing` and `NSStatusItemSelectionPadding`, saved for this Mac only (`defaults -currentHost`).
- **The menu bar's saved order.** Thaw reads and updates it with Menu Bar Layout Access.
- **Control Center's list of apps allowed in the menu bar.** Thaw changes it when **Settings → Layout → Hiding method** is set to Native.

To remove all of Thaw's files, see [Remove what is left](RESET_AND_UNINSTALL.md#remove-what-is-left).
