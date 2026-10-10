# Changelog

All notable changes to Thaw are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

The `release.yml` workflow reads the section matching the release tag
(`## [tag]`) and uses it as the release notes for both the GitHub Release
and the Sparkle appcast, unless overridden with the `release_notes` input.

Each release's sections go in this order:

1. `### New`
2. `### Changed`
3. `### Fixed`
4. `### Known issues`

Leave out a section that would be empty. If one runs long, split it by area
with `####` headings, such as `#### Layout`. Do not put the area in the
section's name.

Anything else goes before the first section, or in its own section after
these four. The website shows each section's name beside its list, and counts
the items under New and Fixed.

## [3.0.0-beta.2] - 2026-10-07
**macOS 27 only · Build 112**

### New

- **Triggers can show items while an app runs**, even in the background. When it quits, they go back to your saved layout. Added by @diazdesandi in [#1223](https://github.com/thaw-app/Thaw/pull/1223).
- **Launchers can open menu bar items and apply profiles** through `thaw://` URLs. Floe works without setup. Added by @diazdesandi in [#1223](https://github.com/thaw-app/Thaw/pull/1223).
- **Restore missing menu bar items**, in Troubleshooting, brings back stuck items and keeps your saved layout. Added by @diazdesandi in [#1223](https://github.com/thaw-app/Thaw/pull/1223).
- **Gradients can run at any angle.** A new slider in Appearance sets it. Gradients you already use look the same. Suggested by Danilo Carvalho (danmnesiac) on Discord. Added by @diazdesandi.
- **Layout shows when macOS won't let an icon follow its section.** A badge on the item explains why. Added by @camguillory in [#1254](https://github.com/thaw-app/Thaw/pull/1254).

### Changed

- **Automatic overflow is off by default.** If you set it yourself, your choice stays. By @diazdesandi in [#1223](https://github.com/thaw-app/Thaw/pull/1223).
- **A gold app icon** and a matching accent color. By @diazdesandi in [#1223](https://github.com/thaw-app/Thaw/pull/1223).
- **About has a new layout**, a sidebar entry and a Credits page. By @diazdesandi in [#1223](https://github.com/thaw-app/Thaw/pull/1223).
- **Release notes and Credits use the same text sizes as Settings.** By @diazdesandi in [#1223](https://github.com/thaw-app/Thaw/pull/1223).
- **Menu bar history is gone**, with its click history and unused-item suggestions. Thaw clears the recorded history on launch. Layout backups and hidden items are unaffected. By @diazdesandi in [#1223](https://github.com/thaw-app/Thaw/pull/1223).

### Fixed

#### Missing icons and search

- **Thaw says when macOS is blocking its icon.** A warning under "Show Thaw icon" points you to System Settings > Menu Bar. Reported by @promonteiro89 in [#1232](https://github.com/thaw-app/Thaw/issues/1232). Fixed by @diazdesandi in [#1223](https://github.com/thaw-app/Thaw/pull/1223).
- **Thaw warns when apps it hid are still hidden** after a launch where it couldn't show them again. The warning in General opens Tools, where you can restore them. Fixed by @diazdesandi in [#1223](https://github.com/thaw-app/Thaw/pull/1223).
- **Items show in the menu bar again with the Thaw Bar turned off.** The bar could show only the section markers. Reported by @daschles in [#1228](https://github.com/thaw-app/Thaw/issues/1228). Fixed by @diazdesandi in [#1223](https://github.com/thaw-app/Thaw/pull/1223).
- **Menu bar search keeps the keyboard** after a search with no matches, and when you open it again. Reported by Jam and krossen6 on Discord. Fixed by @diazdesandi in [#1223](https://github.com/thaw-app/Thaw/pull/1223).

#### Items and previews

- **Layout previews follow each item's current position.** Fixed by @diazdesandi in [#1223](https://github.com/thaw-app/Thaw/pull/1223).
- **Simple Mode previews stay up to date.** Fixed by @diazdesandi in [#1223](https://github.com/thaw-app/Thaw/pull/1223).
- **Amphetamine, Rectangle and OneDrive stay hidden** across title changes and restarts. Reported by Mason_Boom and xX-Mordran-Xx on Discord. Fixed by @diazdesandi in [#1223](https://github.com/thaw-app/Thaw/pull/1223).
- **Items parked off the menu bar no longer count toward overflow.** Fixed by @diazdesandi in [#1223](https://github.com/thaw-app/Thaw/pull/1223).
- **Clock, Control Center and Siri stay in view** with Live Activities and the camera indicator shown. Fixed by @diazdesandi in [#1223](https://github.com/thaw-app/Thaw/pull/1223).

#### Appearance, Thaw Bar and Displays

- **Appearance detects a menu bar that hides automatically.** Reported by @lyramsr in [#1217](https://github.com/thaw-app/Thaw/issues/1217). Fixed by @diazdesandi in [#1223](https://github.com/thaw-app/Thaw/pull/1223).
- **Split pills cover status items on secondary displays.** Fixed by @diazdesandi in [#1223](https://github.com/thaw-app/Thaw/pull/1223).
- **Clicking Thaw's icon after it moves** no longer closes and reopens the Thaw Bar. Fixed by @diazdesandi in [#1223](https://github.com/thaw-app/Thaw/pull/1223).
- **The Thaw Bar no longer turns gray with black icons** when "Thaw Bar own look" is off. Reported by @scsyc in [#1222](https://github.com/thaw-app/Thaw/issues/1222). Fixed by @diazdesandi in [#1223](https://github.com/thaw-app/Thaw/pull/1223).
- **"When applying spacing" is back in Displays.** "Wait until next restart" saves the spacing without relaunching apps. Reported by @netheremp in [#1230](https://github.com/thaw-app/Thaw/issues/1230). Fixed by @diazdesandi in [#1223](https://github.com/thaw-app/Thaw/pull/1223).

#### Moving and arranging

- **Moves work while another app is slow to respond.** One busy app, such as Google Drive in the middle of a sync, used to block every move. Fixed by @camguillory in [#1233](https://github.com/thaw-app/Thaw/pull/1233).
- **Reordering in Layout works with the Thaw icon hidden.** Drops used to save the order without moving anything. Fixed by @camguillory in [#1234](https://github.com/thaw-app/Thaw/pull/1234).
- **Dragging one Stats item moves only that item.** After updating, you may need to place your Stats items once more. Fixed by @camguillory in [#1235](https://github.com/thaw-app/Thaw/pull/1235).
- **A second display no longer scrambles your saved order.** Items used to jump to the end of the menu bar after a reveal. Fixed by @camguillory in [#1241](https://github.com/thaw-app/Thaw/pull/1241).
- **Some items no longer take seconds to move.** Thaw drags them right away. Fixed by @camguillory in [#1251](https://github.com/thaw-app/Thaw/pull/1251).

#### Saved order and Manual arrangement

- **A new or temporary icon no longer scrambles your order.** When an item arrives, Thaw keeps the order you saved. Reported by HiroMike on Discord. Fixed by @diazdesandi in [#1223](https://github.com/thaw-app/Thaw/pull/1223).
- **Layout works in Manual arrangement.** You can drag, sort and use the keyboard there to move items between sections. Reported by HiroMike on Discord. Fixed by @diazdesandi in [#1223](https://github.com/thaw-app/Thaw/pull/1223).

#### Icons in Layout and the Thaw Bar

- **Stats icons show up** where they used to be blank or out of date. Fixed by @camguillory in [#1236](https://github.com/thaw-app/Thaw/pull/1236).
- **Items that report an oversized icon appear in Thaw.** You can now show, hide and move them. Fixed by @camguillory in [#1240](https://github.com/thaw-app/Thaw/pull/1240).
- **Layout keeps real icons while you work in another app.** They used to turn into app icons after 30 seconds. Fixed by @camguillory in [#1246](https://github.com/thaw-app/Thaw/pull/1246).
- **Icons next to a hidden Thaw icon keep their real look.** Fixed by @camguillory in [#1247](https://github.com/thaw-app/Thaw/pull/1247) and [#1252](https://github.com/thaw-app/Thaw/pull/1252).
- **Icons with their own background keep it**, such as Krisp's white square. Fixed by @camguillory in [#1264](https://github.com/thaw-app/Thaw/pull/1264).

#### Several displays and a full menu bar

- **Icons load sooner in Layout with several displays.** They could take about 19 seconds and show app icons in the meantime. Fixed by @camguillory in [#1248](https://github.com/thaw-app/Thaw/pull/1248).
- **Thaw recognizes the menu bar's overflow arrow in every language.** On non-English systems Thaw could save it as an app's icon, and opening the Thaw Bar made icons blink. Fixed by @camguillory in [#1257](https://github.com/thaw-app/Thaw/pull/1257).
- **Clicks in empty menu bar space work on a full notched bar.** Right-clicking opens Thaw's menu there, and click, hover and scroll show your items. Fixed by @camguillory in [#1258](https://github.com/thaw-app/Thaw/pull/1258).
- **The Thaw Bar shows real icons when the menu bar is full**, where it used to show an app icon for every item. Fixed by @camguillory in [#1259](https://github.com/thaw-app/Thaw/pull/1259).
- **A Thaw Bar opened at the pointer stays put.** It used to jump across the screen when you moved the mouse over an item. Fixed by @camguillory in [#1249](https://github.com/thaw-app/Thaw/pull/1249).

#### Menus and permissions

- **Menus opened from the Thaw Bar appear at their icon.** They could open at the top-left corner of the screen. Reported by @steermomo in [#1225](https://github.com/thaw-app/Thaw/issues/1225) and confirmed by @daschles. Fixed by @diazdesandi.
- **System Settings no longer opens behind the Screen Recording prompt.** Thaw waits for your answer first. Fixed by @camguillory in [#1243](https://github.com/thaw-app/Thaw/pull/1243).

## [2.1.0-rc.1] - 2026-10-06

**macOS 26 only · Build 63 · Release candidate**

The first 2.1.0 release candidate. Nothing changed since 2.1.0-beta.6: this is the same app, promoted so it can ship as 2.1.0 if no new problems turn up. For what's new in 2.1.0, see the beta notes below.

If something breaks, please report it at [github.com/thaw-app/Thaw/issues](https://github.com/thaw-app/Thaw/issues).

## [3.0.0-beta.1] - 2026-10-02
**macOS 27 only · Build 111 · First beta**

> [!IMPORTANT]
> **This is the first 3.0.0 beta.**
>
> Beta is the default update channel. Choose Beta or Nightly in About Thaw, from the ⋯ menu in Settings.

> [!NOTE]
> **Updating from alpha 7**
>
> Alpha 7 couldn't find beta 1 because its updater only checked the alpha channel. We've fixed the update feed, so Check for Updates can now offer beta 1 without a manual download. The app itself hasn't changed.
>
> After updating, choose **Beta** in About Thaw to receive later betas. If you previously selected Alpha/Nightly, that choice carries over and excludes later beta releases. This update requires macOS 27; nothing changes for macOS 26 users.

> [!NOTE]
> **Missing a fix?**
>
> If your issue isn't fixed in this build, comment on it. Thank you to everyone who sent logs, recordings and crash reports.

> [!NOTE]
> **A leaner Thaw**
>
> We're trimming, tidying and improving the interface over the next betas. If something feels cluttered, confusing or missing, tell us on GitHub or Discord. Help is appreciated.

> [!TIP]
> **The short version**
>
> **What's new**
> - New option to show Live Activities and the camera indicator while apps are hidden.
> - Folders, opening items by letter, and rounded screen corners.
> - Pick the icon Thaw shows for any item.
> - Open hidden items in the menu bar, under their own icon.
> - One menu for every item, and fewer settings.
>
> **What's fixed**
> - Settings no longer crashes on notched MacBooks, or at 110% zoom.
> - Passwords' menu bar key can move to Hidden.
> - "Who arranges items" is now Item arrangement, and says what it does.
> - Thaw no longer reorders the menu bar around its own icons, or when it runs out of room.
> - The camera and microphone indicators stay in view with the Live Activities option on.
> - Fast User Switching, AirDrop, Focus and Now Playing stay reachable.
> - macOS's » button works again on notched MacBooks.

Thanks to your support, Thaw is now part of the Vercel Open Source Program.

[![Vercel OSS Program](https://vercel.com/oss/program-badge-2026.svg)](https://vercel.com/open-source-program)

### New

#### Folders, letters and corners

- **Folders.** Right-click an item group and choose Show as a Folder. Each folder can have its own icon and color.
- **Open an item by letter** with a shortcut from Settings > Shortcuts.
- **Rounded screen corners** in Settings > Appearance.

#### Icons and menus

- **Thaw uses the app's own icon** where it has no picture of an item. Reported by @mrleblanc101 in [#1087](https://github.com/thaw-app/Thaw/issues/1087).
- **Choose Icon…** picks any image the app ships, or a file of your own. Requested by @Snowman833 in [#912](https://github.com/thaw-app/Thaw/issues/912).
- **One menu for every item** in Layout, search and the Thaw Bar.

#### Show Live Activities and the camera indicator

- **A new option in Settings > General** keeps Live Activities and the camera and microphone indicators on the menu bar while apps are hidden, and stops hidden items from flashing when Notification Center opens.
- **It's in beta and off by default.** Thaw offers it once at launch and asks for access to one file.
- **The camera and microphone indicator stays in Visible.** It could land among hidden items and stay out of sight.
- **An app Control Center doesn't know stays on the bar** instead of switching the option back to the usual hiding, which hid the indicators again.

#### Open hidden items in the menu bar

- **Open hidden items in the menu bar**, in Settings > Thaw Bar, shows a hidden item in the menu bar and opens its menu under the icon, from the Thaw Bar, search or a shortcut. Off, the menu opens without the icon, as before.
- **An app that ignores the click** still opens without its icon.

### Apple's items Thaw can't hide

Switches in Settings > Experiments swap these for Thaw icons you can move or hide.

- **New: Replace Input Menu**, with your keyboard layouts.
- **Fast User Switching, AirDrop, Focus and Now Playing are replaced wherever they sit.** Reported by @joaofrgomes in [#1196](https://github.com/thaw-app/Thaw/issues/1196).
- **Replacement icons look right** and survive a relaunch.

### Settings

- **Update channels.** Choose Beta or Nightly in About Thaw, from the ⋯ menu in Settings.
- **An update's notes open in What's New** before you install.
- **Item arrangement** says what Automatic and Manual do. Reported by @KyNorthstar in [#1212](https://github.com/thaw-app/Thaw/issues/1212).
- **Dashed and dotted borders** in Appearance.
- **Fewer settings.** Anything you changed still applies.
- **Tidier pages**, buttons and sidebar: one shorter list, a subtitle under each pane title, and Swap, Zen Mode and About in the toolbar's menu.
- **Roomier Layout pane.** Each section's bar gets its own card at full width, with its name above it.

### Fixed

- **Settings no longer crashes** on notched MacBooks or at 110% zoom. Reported by @ifangxiang and @NickBenthem in [#1194](https://github.com/thaw-app/Thaw/issues/1194).
- **Thaw no longer reorders the menu bar around its own icons.**
- **Unplugging a display no longer quits menu bar apps.** A different spacing on each display used to relaunch every app with a menu bar item, Chrome included. The new spacing now applies the next time those apps launch, or at once with Reapply Spacing. [#1215](https://github.com/thaw-app/Thaw/issues/1215)
- **A full menu bar stays in order.** When macOS has no room to draw some Visible items, Thaw moves the extra ones to Hidden instead of rearranging the bar again and again.
- **Apps with more than one icon stay where you put them.**
- **Items keep their section** when you reorder Hidden or Always Hidden in Layout.
- **The menu bar is no longer covered** while Thaw updates item pictures.
- **Thaw waits while the screen is locked** instead of updating pictures and positions against the lock screen.
- **Apple's items keep their pictures** on taller notched menu bars.
- **The menu bar background follows reveals at once**, on the right display.
- **The Thaw Bar stays put** when the Thaw icon is turned off.
- **A divider you ⌘-drag stays where you put it**, and the items it passes change section with it.
- **Manual arrangement keeps sections in step with the menu bar.** Drag an item past a divider to change its section; Layout no longer moves items Thaw can't.
- **Hover reveals close again** a second after the pointer leaves the menu bar, instead of waiting for a click.
- **The Thaw Bar captures only missing pictures** when it opens, instead of revealing the whole section.
- **Hidden items open reliably**, and open in the Thaw Bar when the menu bar is full. Reported by @Kodiak-01 in [#1115](https://github.com/thaw-app/Thaw/issues/1115).
- **macOS's » button works** on notched MacBooks. Reported by @joaofrgomes in [#1195](https://github.com/thaw-app/Thaw/issues/1195).
- **Passwords' menu bar key can move to Hidden.** [#1205](https://github.com/thaw-app/Thaw/issues/1205)
- **Siri stays put** when you move other items.
- **An app's items stay together**, and Layout says when one is hidden with its app.
- **Items hidden beside the notch come back** on a wider display. Reported by @shaneoreilly in [#1106](https://github.com/thaw-app/Thaw/issues/1106).
- **Wide items keep their picture.** Reported by @thomast8 in [#1204](https://github.com/thaw-app/Thaw/issues/1204).
- **Item pictures survive a relaunch** and no longer pick up specks from busy wallpapers.
- **Other apps stay in the background** while Settings is open. Reported by @joaofrgomes in [#1197](https://github.com/thaw-app/Thaw/issues/1197).
- **Clicks near the clock in full-screen apps** no longer open Notification Center. Reported by @apaeffgen in [#1191](https://github.com/thaw-app/Thaw/issues/1191).
- **Thaw is faster**: the accessibility helper starts, and swaps and reveals do less work.

### Known issues

- **"Broadcast Message … NSAccessibilityException" in every Terminal window.** An older app whose menu bar item uses AppKit's legacy status-item API throws when Thaw reads the item, and macOS broadcasts the error to all terminals. To find the app, run `log show --last 10m --style compact --predicate 'eventMessage CONTAINS "NSAccessibilityException"'` while it happens; the process name in each line is the app. Quitting or updating that app stops the messages. [#1214](https://github.com/thaw-app/Thaw/issues/1214)

### Still under investigation

- **Thaw may not stay the frontmost app.** Tell us if it still happens. [#1167](https://github.com/thaw-app/Thaw/issues/1167)
- **Uneven gaps after a spacing change.** [#1126](https://github.com/thaw-app/Thaw/issues/1126)
- **Webcam and microphone controls can be hard to reach.** [#1174](https://github.com/thaw-app/Thaw/issues/1174)
- **Item positions with a right-to-left language.** [#1063](https://github.com/thaw-app/Thaw/issues/1063)

### Thank you

- @KyNorthstar, the Item arrangement wording ([#1212](https://github.com/thaw-app/Thaw/issues/1212))
- @ifangxiang and @NickBenthem, the Settings crash ([#1194](https://github.com/thaw-app/Thaw/issues/1194))
- @joaofrgomes, the » button, Typeface and Fast User Switching ([#1195](https://github.com/thaw-app/Thaw/issues/1195), [#1196](https://github.com/thaw-app/Thaw/issues/1196), [#1197](https://github.com/thaw-app/Thaw/issues/1197))
- @shaneoreilly, @Kodiak-01 and @thomast8, hidden and wide items ([#1106](https://github.com/thaw-app/Thaw/issues/1106), [#1115](https://github.com/thaw-app/Thaw/issues/1115), [#1204](https://github.com/thaw-app/Thaw/issues/1204))
- @mrleblanc101 and @Snowman833, item icons ([#1087](https://github.com/thaw-app/Thaw/issues/1087), [#912](https://github.com/thaw-app/Thaw/issues/912))
- @apaeffgen, Notification Center ([#1191](https://github.com/thaw-app/Thaw/issues/1191))
- lyly and influx on Discord, missing items and live wallpapers
- Andrew, ꩜ツ iamnotacat ツ꩜, xX-Mordran-Xx, Kristian Kruse, katlaland and Fofer on Discord, testing, logs and reports across many issues

## [2.1.0-beta.6] - 2026-10-01
**macOS 26 only · Build 62**

Thaw stops rearranging your menu bar in a loop, drops into Always Hidden stay put, and macOS 27 users are pointed at the right update channel.

### New

- **Opened items can stay a while after their menu closes.** A hidden item you open from search or the Thaw Bar went back as soon as its menu closed, so one click in the wrong place sent it away and you had to find it again. "Hide opened items again after" (Settings > General > After revealing) keeps it in the menu bar for up to 30 seconds after the menu closes. It starts at 0 seconds, which works as before. [#342](https://github.com/thaw-app/Thaw/issues/342)
- **Thaw pauses its own moves when they go wrong.** When the menu bar kept putting an item back, Thaw could drag it again and again, so your icons shuffled around. Failed moves also kept hiding the pointer while Thaw retried. Thaw now notices both and pauses its automatic moves for a minute, and longer if it happens again. Your own drags always go through, and a drag that lands ends the pause.

### Fixed

1. **Items dropped into Always Hidden stay there.** When Always Hidden held only a Control Center item whose app Thaw couldn't identify, a dragged item landed off-screen and jumped back to the visible section. Layout now places the drop at the edge of the section, and no longer lets you drag that Control Center item while it's parked out of sight. [#1190](https://github.com/thaw-app/Thaw/issues/1190)
2. **The Thaw icon stays put after reconnecting a display on a notched Mac.** While macOS briefly reported Control Center in the wrong place, Thaw could restore your saved layout against that position and move the Thaw icon far to the left. It now waits for the menu bar to settle first.

### Updates

- **The macOS 27 notice sends you to beta updates.** If you run this version on macOS 27, the notice now says support comes through the alpha and beta channels, and its button switches you to beta updates. Until the first 3.0 beta is out, the beta channel on macOS 27 also offers the 3.0 alphas, so there's always a build that runs. Nothing changes on macOS 26.
- **Under the hood.** A large cleanup: shorter code comments, less unused code, and the biggest source files split up. None of it should change how Thaw behaves. If something does, please report it.

## [3.0.0-alpha.7] - 2026-09-25

**macOS 27 only · Build 108 · Beta candidate**

> [!IMPORTANT]
> **This is a beta candidate.**
>
> If nothing serious turns up in this build, it becomes 3.0.0-beta. Please report anything that looks like a regression from alpha.6.

> [!NOTE]
> **Missing a fix?**
>
> If an issue you reported is not fixed in this build, comment on it and tell us. Where a fix came from a report, it names that report. Thank you to everyone who sent logs, recordings and screenshots, on GitHub and on Discord.

> [!TIP]
> **The short version**
>
> **What's new**
> - Stand-ins for Apple items Thaw can't hide, Time Machine included (Settings > Experiments).
> - Swap answers instantly, and Layout and the Thaw Bar work from the keyboard.
> - A redesigned Appearance pane whose glass and colors can follow your system settings, and a Thaw Bar preview that shows the bar on your desktop.
> - Layout points out items behind the notch and items you don't use.
> - Settings use one name for each thing, and every problem message says what to do.
>
> **What's fixed**
> - Clicking the clock no longer flashes your hidden items, and the blue screen-recording dot is gone.
> - A click on the menu bar reveals hidden items right away.
> - A second display works like the first, and on a notched MacBook the Thaw icon no longer gets stuck under the notch.
> - Bluetooth and Wi-Fi hide and reveal like other items, and System Settings switches no longer stay off.
> - Apps that put a count or a date in their menu bar item stay where you put them.
>
> **What's coming in the beta**
> - Fewer settings: some become default behavior, and experiments graduate or go.
> - Dragging an Apple item Thaw can't hide into Hidden puts a stand-in there for you.
> - Command-Z undoes a mouse drag in Layout.
> - Next up: the scripts feature from Thaw 2.1.0.
>
> The full plan is under "What's next for 3.0.0-beta" below.

### New

#### Stand-ins for Apple items Thaw can't hide (Experiments)

macOS 27 won't let Thaw hide some Apple items, and it removes others completely while they sit in Hidden. These experiments put a Thaw icon in their place. It does the original's main job, and you can hide and order it like any other item. Find them in Settings > Experiments.

- **Time Machine can be hidden now.** Turn on "Replace Time Machine" and Thaw swaps Apple's icon for its own, in the same spot. Its menu has Back Up Now, Browse Time Machine Backups and Time Machine Settings. Reported by @nullsin in [#1153](https://github.com/thaw-app/Thaw/issues/1153).
- **Focus stays reachable while it's hidden.** macOS removes Focus from the bar when it sits in Hidden. The stand-in shows which Focus is on, using that Focus's symbol when macOS lets apps draw it. Reported by @jmstacey in [#1124](https://github.com/thaw-app/Thaw/issues/1124).
- **The Focus stand-in asks for one folder, not Full Disk Access.** The first time, its menu offers "Allow Access to Focus…". Pick the DB folder it shows, and it reads your Focus status from then on. It can show the active Focus but can't switch modes; its menu links to Focus settings for that.
- **AirDrop stays reachable while it's hidden.** Its stand-in opens AirDrop and AirDrop settings.
- **Now Playing stays reachable while it's hidden.** Its stand-in has Play/Pause, Next Track and Previous Track. macOS keeps the track name private to its own apps, so the stand-in can't show what's playing.
- **Fast User Switching stays reachable while it's hidden.** Its stand-in shows your name and offers Lock Screen, Login Window and Users & Groups settings.
- **Getting the original back is one drag.** Move a stand-in to Visible and the Apple item returns in its place. Quitting Thaw, or turning the switch off, always puts every original back.

#### Swapping

- **Swap answers the moment you press it.** It used to wait until every item had been dragged back into its own order, 10 to 40 seconds by one reporter's count, before the Swap button worked again. The groups now trade places immediately and the ordering finishes in the background.
- **Two quick swaps land where they started.** A second swap now works from where the first one was headed, not from a half-finished bar.
- **A click on the Thaw icon can swap.** A new setting, off by default, makes a plain click on the icon swap Visible and Hidden. Option-click, double-click and right-click keep their usual actions.

#### Layout from the keyboard

- **Tab moves into the Layout editor's rows.** Items show the standard focus ring. Left and Right move between items, Up and Down between sections.
- **Home and End jump to either end.** Command-Left and Command-Right do the same.
- **Option-arrow keys move the focused item.** Option-Left and Option-Right move it one place. Option-Up and Option-Down, or Command-1, 2 and 3, move it to another section.
- **Space or Return opens the item's inspector.** Control-Return or Shift-F10 opens its menu.
- **Command-Z undoes a keyboard move.** Mouse drags can't be undone yet.
- **VoiceOver announces every move** and gains Move left and Move right actions.

#### Undo for profiles

- **Command-Z undoes profile changes.** That covers creating, duplicating, renaming, deleting and Save Current. Shift-Command-Z redoes.
- **A deleted profile comes back exactly as it was.** It returns to its place in the list with its display and Space links, and it's active again if it was before.
- **Undoing a Save Current doesn't touch your menu bar.** It restores the profile's saved contents only. Saving to all profiles undoes in one step.
- **The delete confirmation now says you can undo it.**

#### Small helpers

- **Items behind the notch are pointed out.** On a notched MacBook, the Layout pane names the items the notch covers and moves them to Hidden in one click, where they open from the Thaw Bar. Close the hint and it stays away for a month.
- **Items you don't use are pointed out.** With the "Menu bar history" experiment on, the Layout pane suggests moving items you haven't clicked in 30 days to Hidden, and the item inspector shows when each item was last clicked.
- **The Thaw menu shows how many items each section holds**, so you know before opening it.
- **The Thaw Bar works from the keyboard.** Open it with its keyboard shortcut, move with the arrow keys, and press Return or Space to click the highlighted item.

### Settings

- **Settings opens on the macOS 27.2 beta.** Opening Settings, or checking for updates, crashed every time. The crash was inside macOS's own sidebar list, so on 27.2 the sidebar is built a different way; the gaps between its groups are a little wider there. Reported by @Mudflapper, @lucifercraig12345-create and @MHX792 in [#1153](https://github.com/thaw-app/Thaw/issues/1153).
- **"What Thaw sees" shows your menu bar again.** Capture Now in Settings > Privacy always said nothing was captured and blamed the Screen Recording permission. Reported by crazyJosh on Discord.
- **The Settings toolbar works like Xcode's.** Back and forward move through the panes you've visited, with Command-[ and Command-].
- **The active profile sits in the middle of the toolbar**, with the same switch and Manage Profiles options it had in the sidebar.
- **Swap, Zen Mode and Edit Layout are in the toolbar**, with Swap and Zen Mode showing whether they're on.
- **The About page reads like a Mac About window.** Icon, name, a one-line description, then the version, build and commit.
- **Version details can be selected and copied.** Copy Info puts the name, version, build, commit and your macOS version on the clipboard, ready for a bug report.
- **Update settings are one picker.** Choose Off, Check only, or Check and download.
- **The Layout editor uses the whole window width.** Widening Settings gives the item rows more room instead of empty margins. Requested by @djbclark in [#1166](https://github.com/thaw-app/Thaw/issues/1166).
- **The Appearance pane starts with the shape.** Pick it from drawings of a menu bar, then fill the shape and the bar behind it. Ends and margins are one row each, controls that do nothing for the current style are hidden, and Light/Dark, per-Space looks and Reset sit together under Advanced.
- **One name for each thing.** Hidden and Always Hidden, Layout, Thaw Bar, Swap Bar, Zen Mode and keyboard shortcut read the same everywhere, and settings no longer show internal terms like "menu bar agent" or "layout table".
- **Every problem message says what to do.** Missing permissions come with a Grant Access button, an empty Thaw Bar offers Open Layout, a refused Swap says why, and a taken keyboard shortcut says how to pick another.
- **Settings panes read in order.** Tools ends with its reset, Automation leads with everyday options, Experiments is grouped by topic, and options that do nothing in the current state are hidden.
- **The three Thaw menus use the same words** for the same commands, with ellipses where a window opens.
- **Lists of apps and settings read naturally in every language** ("A, B and C").
- **The Thaw Bar's look moved to the Thaw Bar pane**, under its preview, so the Appearance pane is only about the menu bar.
- **The Thaw Bar preview shows the real bar on your desktop.** Settings > Thaw Bar draws it centered on the top of your wallpaper, the part the real bar sits over, instead of a strip across the pane. It's one menu bar tall with the real bar's padding, and each icon is drawn exactly as the Layout editor draws it.
- **The control panel opens as a popover (Experiments).** The panel that replaces Thaw's menu opens under the Thaw icon with the system arrow. Esc, a click elsewhere, or a second click on the icon closes it.

### The clock and Notification Center

- **Clicking the clock no longer flashes your hidden items.** Thaw has to lift its hiding for about a second so the click can reach macOS, and every hidden item used to show for that second. Thaw now covers that part of the bar with what's behind it, so the bar looks unchanged. Reported by @volcbs in [#1181](https://github.com/thaw-app/Thaw/issues/1181).
- **Notification Center opens as soon as you click.** The bar used to stay open on a fixed two-second timer. It now follows Notification Center itself, opening and closing. Reported by @jmstacey in [#1152](https://github.com/thaw-app/Thaw/issues/1152) and by siren on Discord.
- **Clicks just below the clock reach the app underneath.** A click near the top-right corner of a maximized window could land on the clock. Clicks are now matched to the menu bar only. Reported by @MetzgerHund in [#1171](https://github.com/thaw-app/Thaw/issues/1171).
- **Thaw leaves your layout alone while Notification Center opens.** It no longer tries to repair item positions during that second.

### Showing and hiding

- **The blue recording dot is gone.** Showing or hiding items could briefly light macOS's screen-recording indicator, because Thaw took a screenshot of the bar first. Nothing Thaw draws over the bar takes a screenshot now. Asked about by @rtheodoro in [#1161](https://github.com/thaw-app/Thaw/issues/1161).
- **A click on empty menu bar space reveals hidden items right away.** It used to wait for a fresh picture of the bar, about 420 ms on one Mac. It now takes about 70 ms, as fast as a scroll. Reported by a tester on a notched MacBook.
- **The first click reveals even with double-click for Always Hidden on.** Thaw used to wait out the double-click interval first. A second click still reveals Always Hidden on top.
- **Items hide again after a reveal when another app keeps a small window open.** A dock-preview app's floating window was mistaken for an open menu, so Thaw waited forever and icons piled up. Reported by @Dominik-esb in [#1158](https://github.com/thaw-app/Thaw/issues/1158).
- **Apps that change their title keep their place.** An unread count, a date or a live value in the menu bar used to make Thaw treat the item as new every time it changed, and move it. Thaw now learns which apps do this. Reported by @afrazkhan in [#973](https://github.com/thaw-app/Thaw/issues/973) and by @Vicjjh (WeChat) in [#1125](https://github.com/thaw-app/Thaw/issues/1125).
- **Dato keeps one identity whatever date format you pick**, including day-number-only formats. Reported by @Nisgrak in [#1175](https://github.com/thaw-app/Thaw/issues/1175).
- **The Timer can be placed like other system items.** It was missing from Thaw's list of macOS items. Reported by @lucifercraig12345-create in [#1143](https://github.com/thaw-app/Thaw/issues/1143).
- **Icons stay put during a reveal.** For a moment during a reveal, macOS republishes its own items without names, and Thaw could write positions for the wrong item. Icons, Thaw's own included, then wandered around the bar.
- **Thaw no longer misses the first click or keyboard shortcut after it starts listening for one.** It could switch on a moment before it was ready, so the first one went unanswered.
- **The Layout pane says what happens to Control Center items in Hidden.** macOS switches them off rather than hiding them, and the pane now explains that.

### Bluetooth, Wi-Fi and other Control Center items

- **Bluetooth and Wi-Fi hide like other items.** They used to be hidden by switching them off under System Settings > Menu Bar, so they vanished from the bar, didn't come back when you revealed Hidden, and couldn't be moved. Thaw now hides them the same way it hides Sound: they show when you reveal Hidden, and System Settings is left alone. If an earlier build left one switched off, Thaw turns it back on at launch. Reported by Probert on Discord.
- **Thaw no longer leaves Fast User Switching switched off in System Settings.** macOS gives Thaw only one way to hide it, and AirDrop, Focus and Now Playing: turning off their switch under Menu Bar. Thaw turned them back on when it quit, but only after a normal quit. After a crash or a force quit they stayed off, and the next launch took "off" for your own choice, so they never came back. Thaw now saves the original settings before changing anything and puts them back on the next launch. Reported by Probert on Discord.
- **"Move items that don't fit into Hidden" leaves AirDrop, Focus, Now Playing and Fast User Switching alone.** A crowded bar could push one into Hidden and so switch it off in System Settings, without you asking.
- **The item inspector says what hiding a Control Center item does.** Open one in the Layout editor to see that Hidden turns off its System Settings switch, and that Thaw turns it back on when you move it to Visible or quit.

### The Thaw icon

- **Right-clicking the Thaw icon works over a full-screen app.** It used to do nothing there.
- **The Thaw icon comes back even when macOS leaves the dividers out of order.**
- **The Thaw icon and the dividers make their way out from under the notch.** When the bar was full, the notch could cover them. Thaw only checked for an icon pushed off the bar, not one under the notch, so nothing brought it back. With "Move items that don't fit into Hidden" on, Thaw now hides more items until the icon shows. Once it's visible, nothing moves back until an app adds or removes an item. Reported by a tester on a notched MacBook on Discord.
- **A lost Thaw icon is no longer put back under the notch.** When Thaw put its icon back on the bar, it could place it next to an item hidden by the notch.

### Two displays

- **Hovering, clicking and right-clicking work on the second display.** macOS 27 shows the same items on every menu bar but reports their positions for only one of them, so Thaw was checking the pointer against the wrong spots. Reported by @majn4-hub in [#1159](https://github.com/thaw-app/Thaw/issues/1159).
- **Other apps' menus open on the second display**, such as BenQ Display Pilot 2's. Reported by @jmstacey in [#1138](https://github.com/thaw-app/Thaw/issues/1138).
- **Thaw's right-click menu stays open on the second display** instead of flashing and closing. Reported by @jmstacey in [#1137](https://github.com/thaw-app/Thaw/issues/1137).
- **The spacing prompt stops coming back.** Around sleep and wake the active display flickered, and each flicker asked again about a change you'd already declined. Reported by @hamishC0 in [#1180](https://github.com/thaw-app/Thaw/issues/1180).

### Menu bar appearance

- **Glass can match the system.** Choose "Match System" under Effect and Thaw's glass follows Liquid Glass in System Settings > Appearance, the way the Dock does: Regular while it's Tinted, Clear while it's Clear.
- **Colors can follow your accent color.** Turn on "Accent" next to a fill or glass tint color, in Appearance or the Thaw Bar's look, and it changes whenever you change the accent color in System Settings.
- **Appearance tells you when Reduce Transparency hides your look.** macOS draws the menu bar solid while it's on, so the pane now says so and links to the setting, instead of changes seeming to do nothing.
- **Your menu bar look follows you to every desktop.** The tint and shape only showed on the desktop where Thaw started. Reported by @etibes303 in [#1139](https://github.com/thaw-app/Thaw/issues/1139).
- **The shape keeps up with the icons.** When an app added or removed an item on its own, the shape's edge lagged behind for up to eight seconds. It now moves with the icons.
- **The shape appears with the icons during a reveal.** It used to trail them by about a fifth of a second.
- **The shape reaches Control Center and the clock on large notched screens.** At high scaled resolutions on a notched MacBook, Wi-Fi, Control Center and the clock dropped out of Thaw's view. The Split shape stopped short and those items were missing from Layout. Reported by @CoolJosh0221 in [#1081](https://github.com/thaw-app/Thaw/issues/1081) and by crazyJosh on Discord, confirmed by xX-Mordran-Xx.
- **The Split shape still reaches the right edge when macOS doesn't report its own items' positions.**
- **The tint and shape step aside in full screen.** Watching a video full screen used to leave them painted across the top of the display.
- **The Thaw Bar's border follows its rounded corners.** It used to leave dark slivers at the top.
- **Icons in the Thaw Bar are readable on any wallpaper.** Thaw copies each icon from the menu bar, in the menu bar's ink, so on a light wallpaper they came out dark on the Thaw Bar's dark background. Single-color icons now take the Thaw Bar's own ink. Color icons, like a network graph, keep their colors.

### Icons in the Thaw Bar and Layout

- **Hidden items show their own icon, not a neighbor's.** An item could end up with the icon of the item next to it, usually Thaw's, so a whole row showed copies of one icon. Those icons are captured again. Reported by @Vicjjh in [#1125](https://github.com/thaw-app/Thaw/issues/1125) and by Sal on Discord.
- **Items in Always Hidden show their real icons** instead of app icons. Reported by Sal on Discord.
- **Icons read correctly on a solid menu bar.** With Reduce Transparency, Increase Contrast or a full-screen app, Thaw threw real icons away and showed app icons instead. Reported by @MHX792 in [#1153](https://github.com/thaw-app/Thaw/issues/1153).
- **Items that overlap another item keep their icon** instead of switching to the app icon.
- **The Layout editor's notch marker and new-items badge match the icons beside them** on a tinted menu bar. They ignored the tint and could pick the opposite ink.
- **More items find a real icon.** When the first way of capturing an icon fails, Thaw now tries two more before using the app icon.

### Keyboard and VoiceOver

- **Every slider works from the keyboard.** Tab to it and use the arrow keys.
- **Esc closes the Thaw Bar** and the Customize Sidebar sheet, and Return presses Done in the Layout and Appearance popovers.
- **Reduce Motion stops Thaw Bar icons from growing on hover.**
- **Durations read correctly in every language**, "1 second" included, where some settings said "1 seconds".
- **VoiceOver can click Thaw Bar items**, names the group handle in Layout and opens its menu, and says which section each item is in.
- **Warnings stay readable on yellow and orange**, and the notch marker is drawn at full strength with Increase Contrast.

### Speed and stability

- **A frozen app can't freeze your mouse and keyboard.** Some pointer and click checks asked other apps about their menu bar items and waited for an answer. One unresponsive app could hold up every click and key press on the Mac. Those checks now run in Thaw's helper.
- **Thaw's helpers are on by default.**
- **Thaw no longer changes other apps' settings for Always Hidden items.** An unfinished feature ran even though its switch was off, and wrote into those apps' own menu bar settings. It now stays off, and Thaw puts back anything it changed.
- **A `thaw://` link can no longer move items on your menu bar.** A developer test was reachable from any app through a link, with no permission prompt. We removed it.
- **A helper started too early is replaced.** At login, Thaw's accessibility helper could start before macOS had granted it access, and it stayed shut out for the whole session. Thaw now replaces it with a fresh one, waiting a little longer each time, and keeps trying every ten minutes in case you grant access later.
- **A helper that keeps quitting is left alone.** If something on your Mac keeps closing Thaw's accessibility helper, Thaw stops restarting it after a few tries and reads the menu bar itself, and the log says how the helper ended.
- **A click cancelled at the wrong moment can no longer leave Thaw waiting.** If a click on a menu bar item was cancelled before it had started, Thaw could wait for it indefinitely instead of giving up.
- **Updates install reliably on macOS 27.** Thaw's updater now includes the fix for delta updates on macOS 27.
- **Dependencies updated:** Sparkle 2.10.0 (the update fix above, and no more leaked temporary files when a delta update fails) and swift-subprocess 1.0.0, its first stable release.
- **Two actions at once no longer undo each other.** A click queued behind a long move could let two moves run together for the rest of the session.
- **Switching profiles quickly no longer leaves apps closed.** A second switch during the first one's app restart used to stop the restart halfway.
- **Automation sees your settings' real values.** Several settings that are on by default read as off to scripts and Shortcuts until you changed them once.
- **thawctl lists only the settings it can change.**
- **Launch at login uses macOS's own login items.**

### Try the new things

- **Stand-ins:** open Settings > Experiments. Turn on "Replace Time Machine", or "Replace Control Center items while hidden" for Focus, AirDrop, Now Playing and Fast User Switching. Then move those items into Hidden.
- **Swap from the icon:** search Settings for "swap" and turn on the Thaw icon option.
- **Keyboard layout editing:** open Layout, press Tab until an item is focused, then use the arrow keys. Hold Option to move the item.
- **Profile undo:** change a profile, then press Command-Z while Settings is open.
- **Thaw Bar keyboard:** open the Thaw Bar with its keyboard shortcut, then use the arrow keys and Return.
- **System glass and accent color:** in Appearance, choose "Match System" under Effect, or turn on "Accent" next to a color.

### Still under investigation

- **Thaw may not stay the frontmost app.** This build logs every activation change to find out why. Reported by @jimbobbibong-max in [#1167](https://github.com/thaw-app/Thaw/issues/1167).
- **Several items from one app still hide and show together**, such as Stats' network and CPU items. Reported by @Vicjjh in [#1125](https://github.com/thaw-app/Thaw/issues/1125).
- **Uneven gaps after a spacing change.** Reported by @woofingcough in [#1126](https://github.com/thaw-app/Thaw/issues/1126).
- **Webcam and microphone controls can be hard to reach while Thaw runs.** Reported by @colemickens in [#1174](https://github.com/thaw-app/Thaw/issues/1174).
- **After logging in, Thaw can miss some apps' menu bar items until it's relaunched.** They then sit outside your menu bar look and don't hide. The Layout pane now names those apps and offers a Relaunch button, and the log records why each app's items are missing. If it happens to you, send a log before relaunching.
- **Item positions can be wrong with a right-to-left system language**, such as Arabic or Hebrew. [#1063](https://github.com/thaw-app/Thaw/issues/1063)
- **Timer has no stand-in yet.** Thaw can't remove Apple's Timer, so there is no switch for it.

### What's next for 3.0.0-beta

This is the plan as it stands, not a promise, and your reports decide the order. Open bugs are listed under "Still under investigation" above.

- **Fewer switches.** Thaw has grown a lot of settings. For the beta we're going through every one: some become default behavior, some move under Advanced, and some go away. Experiments either graduate or get removed.
- **Stand-ins without a switch.** When you drag an Apple item Thaw can't hide into Hidden, Thaw should put a stand-in there for you.
- **Undo for drags.** Command-Z will undo mouse moves in Layout, the way it already undoes keyboard moves.
- **Scripts, next.** The scripts feature from Thaw 2.1.0 is the next thing coming to 3.0.

#### Blocked by macOS 27, looking for workarounds

These run into limits in macOS 27 itself (see the macOS 27 limitations in the Layout pane). We're actively looking for ways around them, but can't promise them for the beta.

- **Separate items from the same app.** macOS 27 hides and shows an app's items together, so Stats' network item can't yet go in Hidden while its CPU item stays in Visible. [#1125](https://github.com/thaw-app/Thaw/issues/1125)
- **Even spacing.** Each app adds its own padding around its items, so the same spacing setting can still leave uneven gaps. [#1126](https://github.com/thaw-app/Thaw/issues/1126)
- **The Shortcuts item.** macOS 27 can hide it at launch, and Thaw can't bring it back yet. Reported by @gzebadua in [#1154](https://github.com/thaw-app/Thaw/issues/1154).
- **A Timer stand-in.** Thaw can't remove Apple's Timer, so it can't put one of its own in its place.

#### Further out

These come after the beta is solid. We intend to build them, but none of them has a date yet.

- **Rounded screen corners**, carried over from the 2.x roadmap.
- **An Alfred workflow** you can install, on top of the `thaw://` links that already work with Alfred.
- **iCloud sync** for profiles, appearance and preferences between your Macs. Anything tied to one Mac's displays stays local.
- **Item hints.** Press a shortcut, every menu bar item gets a letter, type the letter to click it.
- **Import your setup from another menu bar manager**, so switching to Thaw doesn't mean starting over.
- **Isolation mode.** Show just one item for a while, with everything else out of the way. Requested by @RyloRiz in [#970](https://github.com/thaw-app/Thaw/issues/970).
- **Custom icons.** Give any menu bar item an icon of your choosing, without changing the app. Requested by @Snowman833 in [#912](https://github.com/thaw-app/Thaw/issues/912).

If something matters more to you than what's here, say so on GitHub or Discord.

### Thank you

These people reported what's fixed above, or tested the fixes:

- @afrazkhan, changing titles ([#973](https://github.com/thaw-app/Thaw/issues/973))
- @CoolJosh0221, the notched display ([#1081](https://github.com/thaw-app/Thaw/issues/1081))
- @jmstacey, Focus, both second-display menus and Notification Center ([#1124](https://github.com/thaw-app/Thaw/issues/1124), [#1137](https://github.com/thaw-app/Thaw/issues/1137), [#1138](https://github.com/thaw-app/Thaw/issues/1138), [#1152](https://github.com/thaw-app/Thaw/issues/1152))
- @Vicjjh, WeChat and borrowed icons ([#1125](https://github.com/thaw-app/Thaw/issues/1125))
- @etibes303, the look on other desktops ([#1139](https://github.com/thaw-app/Thaw/issues/1139))
- @lucifercraig12345-create, the Timer ([#1143](https://github.com/thaw-app/Thaw/issues/1143))
- @MHX792, @nullsin and @Mudflapper, solid bars, Time Machine and the Settings crash ([#1153](https://github.com/thaw-app/Thaw/issues/1153))
- @Dominik-esb, auto-rehide ([#1158](https://github.com/thaw-app/Thaw/issues/1158))
- @majn4-hub, second-display positions ([#1159](https://github.com/thaw-app/Thaw/issues/1159))
- @rtheodoro, the blue dot ([#1161](https://github.com/thaw-app/Thaw/issues/1161))
- @djbclark, the full-width Layout editor ([#1166](https://github.com/thaw-app/Thaw/issues/1166))
- @MetzgerHund, clicks below the clock ([#1171](https://github.com/thaw-app/Thaw/issues/1171))
- @Nisgrak, Dato ([#1175](https://github.com/thaw-app/Thaw/issues/1175))
- @hamishC0, the spacing prompt ([#1180](https://github.com/thaw-app/Thaw/issues/1180))
- @volcbs, the clock flash ([#1181](https://github.com/thaw-app/Thaw/issues/1181))
- Sal on Discord, icons in the Thaw Bar and Always Hidden
- siren on Discord, slow clock clicks
- crazyJosh and xX-Mordran-Xx on Discord, the notched display and What Thaw sees
- Kristian Kruse on Discord, hiding Wi-Fi and Bluetooth
- Probert on Discord, Bluetooth, Wi-Fi and Fast User Switching

## [2.1.0-beta.5] - 2026-09-25

**macOS 26 only · Build 61**

> [!IMPORTANT]
> **This is the last beta before the release candidate.**
>
> The next 2.1.0 build is the release candidate. If something looks wrong in this one, please report it now.

A bug-fix release. Thaw stops relaunching your menu bar apps without asking, and fixes the new-item and app-menu bugs beta.4 left behind.

### Fixed

1. **The spacing prompt stops coming back after Cancel.** Waking the Mac, changing resolution, or a display dropping out for a moment could look like a display change, so Thaw asked to relaunch apps for a spacing that was already right. Cancel now counts for that display, and a display that briefly goes missing is no longer treated as a change. Moving to another display still asks. [#1180](https://github.com/thaw-app/Thaw/issues/1180)
2. **"Confirm before relaunching apps" covers every automatic relaunch.** It only applied to display changes. Connecting a display for the first time, switching profiles (by hand or automatically), and changing spacing through a Settings URL all relaunched apps without asking. They ask now. If you decline during a profile switch, the rest of the profile still applies. Changes you confirm in Settings > Displays don't ask twice. [#1098](https://github.com/thaw-app/Thaw/issues/1098)
3. **New items land at the "New items" placeholder.** The beta.4 fix only covered new items with no placeholder set. When the Thaw icon sat at the right end of the visible section, where it usually is, a new app was placed past it and ended up next to the Thaw icon. It now stays at the placeholder. [#1069](https://github.com/thaw-app/Thaw/issues/1069)
4. **Clicking an app menu no longer opens the hidden section.** In some apps, Firefox among them, clicking a menu title like File opened the hidden section as if you had clicked empty menu bar space. Since 2.0.0 Thaw trusted the menu positions each app reports, and these apps report positions that aren't on screen. Thaw now falls back to where the menus actually are. [#1028](https://github.com/thaw-app/Thaw/issues/1028)
5. **Fewer menu bar writes and screen captures.** Every show and hide rewrote Thaw's icons, even when nothing had changed. On macOS 26 each of those writes holds on to memory until Thaw quits. Thaw now writes only what changed, and with an adaptive tint it stops capturing the screen while your displays sleep. Both should slow the memory growth some of you see after days of uptime. If Activity Monitor still shows Thaw growing, please add a comment to [#1129](https://github.com/thaw-app/Thaw/issues/1129).

### Updates

- **The beta channel offers 2.1 updates again.** The beta update feed was built from the 3.0 alpha builds, so some of you stayed on beta.2. From this release, 2.1 installs on the beta channel get 2.1 updates. [#1170](https://github.com/thaw-app/Thaw/issues/1170)
- **"Dev Mode Flags" is now "Trigger Sources".** The switches that add conditions to the Triggers pane had a name that made them look like debugging tools, and the Triggers pane sent you to "Developer settings", which isn't in the sidebar. The pane and every pointer to it now say Trigger Sources.
- **Search, About and onboarding follow your text size.** They used fixed point sizes, so the macOS text size setting didn't reach them. Trigger cards and the layout bar also use the same 16pt corners as the rest of Settings.
- **Sparkle 2.10.0 and AXSwift6 0.5.2.** The update framework and the accessibility library Thaw uses are on their latest versions.

### Correction to beta.4

The beta.4 notes gave the wrong name for the app-icon setting. It's **Settings > Layout > Advanced layout controls > Show app icons instead of live previews**. Turning it on stops Thaw capturing the menu bar, which removes the screen-recording indicator. [#1051](https://github.com/thaw-app/Thaw/issues/1051)

## [3.0.0-alpha.6] - 2026-09-21

**macOS 27 only · Build 106**

> [!NOTE]
> **Missing a fix?**
>
> If an issue you reported is not fixed in this build, comment on it and tell us. We had a wave of new reports and duplicates and lost track of some.

> [!TIP]
> **iStat Menus and Little Snitch**
>
> Thaw and iStat Menus work well together since iStat Menus 7.5.1. For Little Snitch, turn on **Security → Allow GUI Scripting access to Little Snitch**.

### Expected behavior and current limits

- **Several items from one app:** some apps' menu bar items cannot be hidden independently with the current macOS 27 mechanism. An item you put in Hidden can stay visible when another item from the same app is in Visible. [#1125](https://github.com/thaw-app/Thaw/issues/1125)
- **App icons instead of menu bar previews:** when Thaw has no usable capture, including when Screen Recording permission is off, it shows the item's app icon instead of leaving a hole. That fallback is on purpose. If an item still disappears completely, report it. [#1119](https://github.com/thaw-app/Thaw/issues/1119)
- **Spacing changes:** applying spacing can restart menu bar apps so they pick up the new value. Each app adds its own padding, so the same setting does not always produce the same gaps. [#1126](https://github.com/thaw-app/Thaw/issues/1126)
- **macOS-pinned items stay where they are:** Clock, Control Center and Siri cannot be moved. The macOS items toggle covers only those three.
- **The Layout editor does not reorder under Manual arrangement:** a drag there is refused with a warning instead of overwriting the order you saved by hand.
- **Live Activities:** macOS 27 hides some Live Activity items and gives Thaw no way to bring them back on demand. This is a system limitation, not a setting. [#1095](https://github.com/thaw-app/Thaw/issues/1095)
- **Shortcuts and the Focus icon:** macOS 27 can hide the Shortcuts item, and the Focus icon may not be visible to Thaw at all, so Thaw cannot manage either one. [#1105](https://github.com/thaw-app/Thaw/issues/1105), [#1124](https://github.com/thaw-app/Thaw/issues/1124)

### New

- **Swap bar:** one press trades your shown and hidden items, and the next trades them back, each group keeping its own order. It is a real layout change, so it survives a relaunch. The bar sits under the menu bar on the display your pointer is on, with the swap beside the active profile, the section toggles, and zen mode. Thaw's right-click menu, a hotkey, or a Shortcuts action reach the same swap. Turn it on with "Show Swap bar".
- **Panel instead of the status menu (Alpha):** right-click Thaw's icon to get a panel of controls instead of a menu of text. It shows the sections, zen mode, the active profile, and the Swap bar. Everything else stays in the menu, which comes back when this is off.
- **macOS 27 limits in the Layout pane:** the pane opens with a list of what macOS 27 does not let Thaw do, and keeps it behind an info button after you dismiss it.
- **Glow warning:** Thaw tells you when Glow is also managing the menu bar. Two apps hiding the same items fight each other, and Thaw cannot win that quietly.
- **Reorder circuit breaker:** when automatic reordering starts looping, Thaw stops, waits longer on each repeat, and a single manual move clears it.
- **System item toggle scoped to macOS items:** the show/hide toggle now covers Clock, Control Center and Siri only, the items macOS pins.

### Fixed

- **Supporting text and warning pills are readable in light mode.** Both use ink that meets contrast instead of the dimmed grey.
- **The settings panes got a consistency pass.** Panes that had no title now have one, buttons that do the same thing look the same and sit in the same place, and error alerts name what failed.
- **The Displays pane leads with the display selector**, and its Customized label reflects the whole configuration rather than one setting.
- **The Thaw Bar pane opens on the real-spacing preview**, and the panel no longer shows two sets of controls for the same thing.
- **Missing dividers explain themselves.** The empty state says Thaw is placing the dividers and only sends you to System Settings if they stay missing.
- **Thaw no longer reopens the last Settings pane at launch**, and a crash loop no longer stacks Troubleshooting windows.
- **A Core Foundation result that is not an array or a dictionary no longer crashes the app.** Five bridging sites are checked before use.
- **A Manual-arrangement reorder is refused with a warning** instead of silently overwriting the order you saved.
- **A missing capture no longer leaves a blank slot.** An item with no app icon and no capture, such as a concealed Apple module, now falls back to a substitute glyph instead of an empty cell.
- **Right-clicking an item in the Thaw Bar opens its menu again.** Alpha 6 sent the right click through the move path, so an item macOS would not let Thaw move never got a context menu.
- **A failed menu bar capture falls back to the app icon** instead of leaving the slot blank or black.
- **A reveal whose menu bar capture fails no longer pegs a CPU core.** The join loop spun the main thread, which is the system-wide lag some of you saw during a reveal.
- **Time Machine is recognized by name.** macOS 27 stopped reporting a title for it, so Thaw filed it as an unnamed item and could not place it.

### Menu bar reliability

- **The Notification Center shortcut works while Thaw holds the menu bar assertion.** [#1146](https://github.com/thaw-app/Thaw/issues/1146)
- **Clicking an empty part of the bar no longer opens the Thaw Bar or reveals Always Hidden items.** [#1145](https://github.com/thaw-app/Thaw/issues/1145)
- **Right-clicking Thaw's icon keeps its context menu open** instead of showing it and hiding it again. [#1147](https://github.com/thaw-app/Thaw/issues/1147)
- **Clicking an item inside the hidden section no longer closes the whole section.** [#1148](https://github.com/thaw-app/Thaw/issues/1148)
- **A quit app's item no longer stays behind as a dead icon in the Thaw Bar.** [#1149](https://github.com/thaw-app/Thaw/issues/1149)
- **Concealed icons are no longer painted onto the bar while Thaw captures them.** The reveal mask is captured in-process, so a Clock click opens Notification Center faster, and the mask is captured even when no Thaw panel is open.
- **A hidden row keeps its own glyph.** It no longer borrows a neighbour's pixels or draws an empty row.
- **A concealed item gets one fresh capture attempt** each time a visible consumer asks for it, instead of staying blacklisted.
- **Full-frame icons such as Little Snitch keep their glyph.** The background for the knock-out is sampled from the edge of the crop instead of its corners. [#1119](https://github.com/thaw-app/Thaw/issues/1119)
- **Item crops no longer include the desktop behind the bar**, and status items are taken from the window they are drawn in.
- **Wallpaper captures work** even though the wallpaper window belongs to a system process.
- **Items the window server parks stay in the inventory**, and the repeated Thaw Bar warnings and Clock relocation loops stop.
- **Dropping an item in the Layout pane puts it where you dropped it**, in the order you dropped a group, without dragging the cursor across the bar. A drop still works while the reorder breaker is cooling down.
- **Hiding a batch of items no longer walks the cursor** into the hidden section.
- **A move the position store cannot express still completes** through the Command-drag fallback. Drops can land next to parked-band items, and two icons of one app sitting on one weight are separated.
- **The Thaw icon honours a held Option**, and Always Hidden presents the Thaw Bar when it is on.
- **The capture helper no longer aborts while ScreenCaptureKit builds its window filter**, and Layout opens right after the Thaw Bar without the multi-second wait.
- **The Thaw Bar stays beside the Thaw icon when macOS parks it.** It used to anchor to the parked position and land at the left edge of the screen.
- **The Thaw icon comes back after a display change.** Recovery used to give up for the rest of the session.

### Still under investigation

- **Thaw's own menu bar item can still go missing on macOS 27.** Thaw now treats a parked Thaw icon as parked, so the bar and the layout engine stop planning on that position, and recovery retries after a display change. macOS can still park the item, so this needs a live test before it is called fixed. [#1135](https://github.com/thaw-app/Thaw/issues/1135)
- **Hidden section items still look wrong in some cases.** Always-hidden icons are captured after the section settles, and edge-ring knock-out helps full-frame icons, but the reports stay open. [#1119](https://github.com/thaw-app/Thaw/issues/1119)
- **The five clicking bugs reported against alpha.5 have fixes in this build.** The reports stay open until someone confirms them on a live macOS 27 setup: empty-spot clicks, the Notification Center shortcut, the right-click menu, hidden-section collapse, and a dead Thaw Bar icon. [#1145](https://github.com/thaw-app/Thaw/issues/1145), [#1146](https://github.com/thaw-app/Thaw/issues/1146), [#1147](https://github.com/thaw-app/Thaw/issues/1147), [#1148](https://github.com/thaw-app/Thaw/issues/1148), [#1149](https://github.com/thaw-app/Thaw/issues/1149)
- **Uneven gaps after a spacing change are not resolved.** [#1126](https://github.com/thaw-app/Thaw/issues/1126)
- **The reported Accessibility crash is still under investigation.** This release keeps compact crash diagnostics even when regular logging is off. If Thaw crashes, attach the crash report and the files available through **Troubleshooting → Show Log Files in Finder**.

## [2.1.0-beta.4] - 2026-09-21
**macOS 26 only · Build 60**

A bug-fix pass on the menu bar layout engine and its settings, plus one new option. Eight field reports are fixed here, from parked reorders that reverted to the screen-recording indicator.

### New

- **Keep Thaw out of the Dock while you toggle the bar.** "Hide Dock icon when toggling the menu bar" (General) stops Thaw switching to a regular activation policy when it shows or hides hidden items, so the Dock icon no longer flashes on every toggle. Overflow that would have hidden the frontmost app's menus opens in the Thaw Bar instead. Settings and other explicit windows still appear normally. [#1128](https://github.com/thaw-app/Thaw/issues/1128)

### Fixed

1. **Parked reorders land again.** While a parked item is held, WindowServer reports it at the display origin and the parked lane reads as reflowed by roughly a thousand points. Rebuilding the release point from that mid-hold snapshot landed the item past the end of the lane, so every hidden-section reorder was refused and the user saw "could not be kept in its new position". A parked teleport now releases at the point planned just before the press. A source-anchored retry keeps its planned point only when the destination is parked; against a visible destination the reflow is real and the fresh point is correct. [#1074](https://github.com/thaw-app/Thaw/issues/1074), [#1102](https://github.com/thaw-app/Thaw/issues/1102), [#1104](https://github.com/thaw-app/Thaw/issues/1104), [#1133](https://github.com/thaw-app/Thaw/issues/1133)
2. **A quit app no longer leaves a dead icon in the Thaw Bar.** A temporarily shown item whose owning process had terminated was re-queued for up to ten not-found attempts before being dropped. Thaw now probes the source PID and drops the item immediately when it is gone, clearing the pending relocation so it is not resurrected later. [#1149](https://github.com/thaw-app/Thaw/issues/1149)
3. **Scrolling on the Thaw icon reveals the hidden section again.** The reveal gesture only accepted empty menu bar space, which deliberately excludes the Thaw icon, so scrolling directly on the icon did nothing. The icon region is now accepted as well. [#1073](https://github.com/thaw-app/Thaw/issues/1073)
4. **New items land where the "New items" placeholder sits.** Default (no-anchor) placement inserted a new item at the section end, while the Layout editor badge defaults to the section start, so a new app appeared next to the Thaw icon instead of at the placeholder. Default placement now uses the same slot the badge defaults to. [#1069](https://github.com/thaw-app/Thaw/issues/1069)
5. **The Smart rehide interval is visible where it is used.** Smart falls back to the same interval Timed uses, but the slider only appeared under Timed, so the value that governed Smart could not be seen or changed. The slider now appears under both. Focus rehides on activation and ignores the interval. [#1049](https://github.com/thaw-app/Thaw/issues/1049)
6. **A renamed anchor still places new items.** A "New items" anchor saved under a helper's name stopped matching after the namespace was canonicalized, so new items fell back to the section default. Anchor lookup now canonicalizes, and the placement names the live item. [#1069](https://github.com/thaw-app/Thaw/issues/1069)
7. **App-icon mode stops sampling the menu bar.** "Always use app icon for menu bar items" only changed what Thaw drew; it still captured the menu bar for previews, which is what raises the screen-recording indicator. With the setting on, Thaw no longer captures. [#1051](https://github.com/thaw-app/Thaw/issues/1051)
8. **The Thaw Bar uses the right icon tint on every display.** Opening the bar on a second display briefly showed the other display's light or dark icon tint. Thaw now keeps a per-display icon snapshot and restores it before the bar appears. [#1065](https://github.com/thaw-app/Thaw/issues/1065)

## [3.0.0-alpha.5] - 2026-09-15

**macOS 27 only · Build 105**

> [!WARNING]
> **Known macOS 27 limitations**
>
> Some native menu bar items may be missing or hidden. Control Center items and Shortcuts may also be unavailable in the menu bar. These are part of the same macOS 27 limitations, rather than separate Thaw bugs. We’re actively investigating ways to support these items.

### Expected behavior and current limits

- **Several items from one app:** some apps’ menu bar items cannot be hidden independently with the current macOS 27 mechanism. An item assigned to Hidden can remain visible when another item from the same app is assigned to Visible. [#1125](https://github.com/thaw-app/Thaw/issues/1125)
- **App icons instead of menu bar previews:** Thaw uses an app-icon fallback when a usable capture is unavailable, including when Screen Recording permission is off. The fallback is intentional; an item disappearing entirely still needs investigation.
- **Spacing changes:** applying spacing can restart menu bar apps so they load the new value. Each app can also add its own padding, so the same setting does not guarantee identical visible gaps.

### New

- **App zoom:** resize Thaw’s app UI from 75% to 200%. Use ⌘+ and ⌘−, or choose Zoom from the settings overflow menu. ⌘0 resets to 100%.
- **Thaw Bar appearance:** the floating bar and its preview now apply your saved appearance correctly. Customize the background, tint, glass, border, and shadow using the same controls as the menu bar.
- **Reapply Spacing:** added to Displays for when apps haven’t picked up your saved spacing. It relaunches menu bar apps to reload the setting. [#1126](https://github.com/thaw-app/Thaw/issues/1126)

### Fixed

- **Displays no longer pushes the sidebar out of the window.** The selector now shows connected displays only. Settings content also has 10% more room. [#1131](https://github.com/thaw-app/Thaw/issues/1131)
- **Removed the Thaw Bar’s unwanted outline and extra shadow.** Turning Border off now removes the drawn outline. [#1125](https://github.com/thaw-app/Thaw/issues/1125)
- **Search selections are easier to read.** The highlighted row uses an opaque background instead of another glass layer.
- **Thaw releases its Dock presence after the floating bar closes** when no other Thaw windows need it.
- **MacThrottle keeps a stable identity when its temperature changes**, addressing duplicate entries and hiding problems. [#1121](https://github.com/thaw-app/Thaw/issues/1121)

### Menu bar reliability

- Improved double-click recognition on the Thaw icon for opening Always Hidden. [#1119](https://github.com/thaw-app/Thaw/issues/1119)
- Corrected Battery item recognition and added a fallback for manual moves when macOS ignores the position change. [#1110](https://github.com/thaw-app/Thaw/issues/1110)
- Added checks to reject icon captures that overlap another item or belong to another app. [#1119](https://github.com/thaw-app/Thaw/issues/1119), [#1125](https://github.com/thaw-app/Thaw/issues/1125)
- Capture sessions are reused between requests, and the screen-recording indicator is excluded from saved item order.
- Automatic order repairs wait until startup layout restoration finishes.

### Still under investigation

- Some icons can still be missing or show an app-icon fallback, including Little Snitch. The broader icon reports remain open. [#1119](https://github.com/thaw-app/Thaw/issues/1119), [#1125](https://github.com/thaw-app/Thaw/issues/1125)
- Battery snap-back, unexpected reordering, and uneven gaps are not fully resolved. [#1110](https://github.com/thaw-app/Thaw/issues/1110), [#1126](https://github.com/thaw-app/Thaw/issues/1126)
- The reported Accessibility crash is still under investigation. This release keeps compact crash diagnostics even when regular logging is off. If Thaw crashes, attach the crash report and the files available through **Troubleshooting → Show Log Files in Finder**.

## [3.0.0-alpha.4] - 2026-09-15

### macOS 27 only

This is one of the last alphas. We are targeting the beta release by the end of this week. Once beta lands and the core functions are stable and reliable, the codebase opens for contributions.

The experimentation phase is over. This release consolidates the UI into a mix of Thaw 2 and fresh polish, keeping everything native to macOS and consistent with the system. If you have a suggestion or an improvement, we want to hear it.

Settings is rebuilt. The fifteen-pane sidebar is gone. What replaces it is a grouped sidebar with no nested tabs, a dedicated Thaw Bar page with a live preview, a customizable sidebar, and a separate appearance for the Thaw Bar itself.

Something broke? [Open an issue](https://github.com/thaw-app/Thaw/issues/new/choose). Something missing? [Tell us here](https://github.com/thaw-app/Thaw/discussions).

---

### Upgrade from 3.0.0-alpha.3

1. Nothing to do. Profiles, saved layouts, hotkeys, appearance, and permissions all carry over.
2. Your last settings pane reopens. If it moved, it remaps to its new home.
3. You can now hide sidebar destinations you don't use. Open the overflow menu and pick "Customize Sidebar."

---

### Settings

- **Fifteen panes down to a grouped sidebar.** General, Layout, Visibility, Appearance, Thaw Bar, Profiles, Shortcuts, Automation, Displays, Spaces, Privacy, Experiments, and Troubleshooting. Grouped with the system's inter-section spacing, no text headings. About lives in the status-item menu. Scripts and Custom Status Icon are reachable through search and Experiments.
- **Layout and Visibility are direct peers, not a nested tab.** Menu Bar used to be one destination with an Arrange / Behavior segmented control inside it. Now Layout and Visibility each have their own sidebar row. Layout holds the bar editor and every layout control. Visibility holds the reveal and rehide lifecycle, search configuration, and tooltips.
- **Advanced is gone.** Its three controls moved to where they belong. App-menu hiding and the secondary context menu are in General. Auto-zen-while-presenting is in Automation. The reorder timeout is parked behind the Advanced layout controls disclosure; its write path is bypassed on macOS 27, so the UI is hidden until it has a visible effect.
- **Customize the sidebar.** Hide destinations you don’t use from the overflow menu’s “Customize Sidebar” sheet. Hidden panes stay reachable through search. The current pane and the last visible pane can’t be hidden.

### Thaw Bar

- **Dedicated page with a live preview.** The Thaw Bar configuration that was buried inside Displays now has its own sidebar entry. The preview shows the hidden section's items in the chosen arrangement (horizontal, vertical, grid), on the real menu-bar surface, with the actual Thaw Bar shape and border from the appearance config. An "Open Thaw Bar" button opens the real panel. When it's off, the button says "Enable & Open."
- **Separate Thaw Bar appearance.** Ported from the 2.1.0 beta versions. The Thaw Bar can now draw with its own shape, tint, and border, independent of the menu bar's. The override is off by default and seeded from the values on screen, so turning it on changes nothing until you edit something. Rounded corners, tint (solid or gradient), tint opacity, border color, and border width. The border shape omits the top edge on square corners so it is not clipped by the display's rounded screen corners.

### Menu Bar editor

- **Section changes appear without another scan.** Moving an item between Hidden and Always Hidden now updates its editor row from the saved assignment, instead of waiting for Accessibility discovery to finish. The editor no longer leaves the item in its old row while that scan catches up. This changes the preview, not how physical moves are verified.
- **One short instruction instead of four.** The heading, drag instructions, the Command-drag tip, and the macOS limitation note collapsed into a single line beside the editor. The OS limitation is a footnote. The refusal notice still appears when a move fails.
- **Empty groups state is a compact row.** The 110pt centered empty state is gone. A one-line footnote says what to do instead.
- **Command-drag toggle moved.** "Show all sections when Command-dragging" moved from Visibility to Layout's Advanced layout controls disclosure, where the other advanced layout behaviors live.

### General

- **Contextual menu controls moved here.** "Hide app menus when showing menu bar items" and "Enable secondary context menu" (plus its quit sub-toggle) moved from the dissolved Advanced pane to General.
- **"No active profile" instead of "None."** The sidebar's profile footer says what it means.

### Profiles

- **Quieter rows.** Creation and modification dates moved into the "Save Current" menu as a detail, not beside the name. "Update" is now "Save Current" with clearer wording. The auto-switching link is a single inline footnote, not a section card.
- **Profile auto-switching moved to Automation.** The display and Space profile-assignment controls moved from Profiles to Automation, with a direct link from Profiles.

### Experiments

- **Shorter caution, feedback below the list.** The large red introductory pill is gone. A one-line caution sits above the experiments. Feedback links (The Lab, Discord) sit below them.
- **Customize before enabling.** The Customize button for the Custom Status Icon is available before the feature is turned on, so you can inspect the builder without adding it to the menu bar.
- **Custom Status Icon moved here.** It is no longer a sidebar destination. It is an Experiments toggle with a Customize link.

### Simple Mode

- **Arrangement picker added.** "Who arranges items" (manual vs. automatic) is now at the top of Simple Mode. The core loop is self-contained: decide who arranges, then drag.
- **Profiles removed.** Simple Mode is the everyday surface. Profiles are a power-user feature available in the full window.

### Menu bar reliability

- **Moves use targeted scans.** Move preparation and verification ask known menu bar owners for fresh bounds instead of repeatedly scanning every running app. New and unresolved owners are still checked, and apps previously found without an item are checked again after a short interval. Cached bounds never count as proof that a move succeeded.
- **Section moves no longer interrupt one another.** Preparing an item's position, verifying the move, and committing its section now share one queue slot. Cancelling a queued move no longer releases another move's slot. Cross-section destination handling also fixes three cases that placed an item on the wrong side of a divider.
- **Discovery makes progress under load.** Scans rotate through app owners so slow apps cannot repeatedly use up the budget before later owners are reached. Late scan results cannot overwrite newer state, and incomplete scans cannot discard retained items or replace your saved order.
- **Thaw's controls keep their identities.** Position-key matching distinguishes the Visible, Hidden, and Always Hidden controls by their titles instead of treating a lone nearby control as a match.
- **Manual arrangement skips the remaining repair paths.** Restriction changes no longer schedule repairs in manual mode. Corrective pulses, automatic unparking, boundary repairs, and structural position rewrites also stop when manual mode is selected during a wait. Refused manual-mode moves no longer count toward repair-failure suppression. Native Command-dragging remains yours to control; hiding and revealing still work.
- **Droppy's persistent panel no longer blocks automatic rehide.** Thaw excludes Droppy's layer-100 overlay from menu detection while retaining its standard popup-menu level. Existing candidate windows are also tracked before their owner's item reaches the cache, so discovering an app no longer turns its already-open panel into a newly opened menu.

### Fixed

- **Capture jitter on 5 items fixed.** Five menu bar items (1Password, Hookshot, WisprFlow, CleanShotX, Okta) oscillated 1 pixel on every capture cycle because of sub-pixel rounding. The capture bounds tolerance is raised from 0.5pt to 1.0pt, so the capture loop stops spinning while Settings is open.
- **49pt menu bar hosting window found.** On displays with a 49pt menu bar (larger displays, different scaling), the hosting window was never matched because the geometry check capped at 40pt. The threshold is raised to 60pt (point space) and 120px (pixel space), so system items (Clock, Control Center, Wi-Fi, Now Playing) get their clean hosting-window captures instead of falling back to the display strip every cycle.

### Under the hood

- **@Observable migration.** StatusIconWidgetController, NotchClockWidget, NotchMediaWidget, and NotchAccessoryWidget migrated from ObservableObject + @Published to @Observable, for per-property observation instead of whole-object invalidation.
- **@Animatable macro.** NotchShape's manual animatableData replaced with the @Animatable macro (macOS 26+), with @AnimatableIgnored on non-animating properties.
- **Native pickers in settings forms.** ThawPicker no longer applies glass to every picker. It uses the system menu style, so settings content reads as stable and opaque while glass is reserved for floating panels.
- **Glass scoping.** The Thaw Bar preview no longer wraps in an extra glass frame. It matches the real panel's treatment: sampled color, card corner, shadow. Colored drop shadows removed from informational notices.
- **Search routing.** Every relocated control's search entry routes to its new home with the right disclosure exposed. Reveal, rehide, search, and tooltip entries land on Visibility directly. Contextual-menu entries land on General. Auto-zen lands on Automation.

### Known issues

- An app with several menu bar items that renamed them in the macOS 27 upgrade may need those items reassigned once by hand.
- Items whose title is live text (a temperature, a clock, a transfer rate) are placed by macOS from memory rather than from the layout table. They can land next to where you put them rather than exactly there.
- Flux cannot be seen or properly handled by Thaw.
- Toggling Hidden can briefly show Always Hidden items in the menu bar during the redraw, even though they return to the correct concealed state. This visual flash remains unresolved.

---

## [3.0.0-alpha.4.1] - 2026-09-15

### macOS 27 only

This is one of the last alphas. We are targeting the beta release by the end of this week. Once beta lands and the core functions are stable and reliable, the codebase opens for contributions.

The experimentation phase is over. This release consolidates the UI into a mix of Thaw 2 and fresh polish, keeping everything native to macOS and consistent with the system. If you have a suggestion or an improvement, we want to hear it.

Settings is rebuilt. The fifteen-pane sidebar is gone. What replaces it is a grouped sidebar with no nested tabs, a dedicated Thaw Bar page with a live preview, a customizable sidebar, and a separate appearance for the Thaw Bar itself.

Something broke? [Open an issue](https://github.com/thaw-app/Thaw/issues/new/choose). Something missing? [Tell us here](https://github.com/thaw-app/Thaw/discussions).

---

### Upgrade from 3.0.0-alpha.3

1. Nothing to do. Profiles, saved layouts, hotkeys, appearance, and permissions all carry over.
2. Your last settings pane reopens. If it moved, it remaps to its new home.
3. You can now hide sidebar destinations you don't use. Open the overflow menu and pick "Customize Sidebar."

---

### Settings

- **Fifteen panes down to a grouped sidebar.** General, Layout, Visibility, Appearance, Thaw Bar, Profiles, Shortcuts, Automation, Displays, Spaces, Privacy, Experiments, and Troubleshooting. Grouped with the system's inter-section spacing, no text headings. About lives in the status-item menu. Scripts and Custom Status Icon are reachable through search and Experiments.
- **Layout and Visibility are direct peers, not a nested tab.** Menu Bar used to be one destination with an Arrange / Behavior segmented control inside it. Now Layout and Visibility each have their own sidebar row. Layout holds the bar editor and every layout control. Visibility holds the reveal and rehide lifecycle, search configuration, and tooltips.
- **Advanced is gone.** Its three controls moved to where they belong. App-menu hiding and the secondary context menu are in General. Auto-zen-while-presenting is in Automation. The reorder timeout is parked behind the Advanced layout controls disclosure; its write path is bypassed on macOS 27, so the UI is hidden until it has a visible effect.
- **Customize the sidebar.** Hide destinations you don’t use from the overflow menu’s “Customize Sidebar” sheet. Hidden panes stay reachable through search. The current pane and the last visible pane can’t be hidden.

### Thaw Bar

- **Dedicated page with a live preview.** The Thaw Bar configuration that was buried inside Displays now has its own sidebar entry. The preview shows the hidden section's items in the chosen arrangement (horizontal, vertical, grid), on the real menu-bar surface, with the actual Thaw Bar shape and border from the appearance config. An "Open Thaw Bar" button opens the real panel. When it's off, the button says "Enable & Open."
- **Separate Thaw Bar appearance.** Ported from the 2.1.0 beta versions. The Thaw Bar can now draw with its own shape, tint, and border, independent of the menu bar's. The override is off by default and seeded from the values on screen, so turning it on changes nothing until you edit something. Rounded corners, tint (solid or gradient), tint opacity, border color, and border width. The border shape omits the top edge on square corners so it is not clipped by the display's rounded screen corners.

### Menu Bar editor

- **Section changes appear without another scan.** Moving an item between Hidden and Always Hidden now updates its editor row from the saved assignment, instead of waiting for Accessibility discovery to finish. The editor no longer leaves the item in its old row while that scan catches up. This changes the preview, not how physical moves are verified.
- **One short instruction instead of four.** The heading, drag instructions, the Command-drag tip, and the macOS limitation note collapsed into a single line beside the editor. The OS limitation is a footnote. The refusal notice still appears when a move fails.
- **Empty groups state is a compact row.** The 110pt centered empty state is gone. A one-line footnote says what to do instead.
- **Command-drag toggle moved.** "Show all sections when Command-dragging" moved from Visibility to Layout's Advanced layout controls disclosure, where the other advanced layout behaviors live.

### General

- **Contextual menu controls moved here.** "Hide app menus when showing menu bar items" and "Enable secondary context menu" (plus its quit sub-toggle) moved from the dissolved Advanced pane to General.
- **"No active profile" instead of "None."** The sidebar's profile footer says what it means.

### Profiles

- **Quieter rows.** Creation and modification dates moved into the "Save Current" menu as a detail, not beside the name. "Update" is now "Save Current" with clearer wording. The auto-switching link is a single inline footnote, not a section card.
- **Profile auto-switching moved to Automation.** The display and Space profile-assignment controls moved from Profiles to Automation, with a direct link from Profiles.

### Experiments

- **Shorter caution, feedback below the list.** The large red introductory pill is gone. A one-line caution sits above the experiments. Feedback links (The Lab, Discord) sit below them.
- **Customize before enabling.** The Customize button for the Custom Status Icon is available before the feature is turned on, so you can inspect the builder without adding it to the menu bar.
- **Custom Status Icon moved here.** It is no longer a sidebar destination. It is an Experiments toggle with a Customize link.

### Simple Mode

- **Arrangement picker added.** "Who arranges items" (manual vs. automatic) is now at the top of Simple Mode. The core loop is self-contained: decide who arranges, then drag.
- **Profiles removed.** Simple Mode is the everyday surface. Profiles are a power-user feature available in the full window.

### Menu bar reliability

- **Moves use targeted scans.** Move preparation and verification ask known menu bar owners for fresh bounds instead of repeatedly scanning every running app. New and unresolved owners are still checked, and apps previously found without an item are checked again after a short interval. Cached bounds never count as proof that a move succeeded.
- **Section moves no longer interrupt one another.** Preparing an item's position, verifying the move, and committing its section now share one queue slot. Cancelling a queued move no longer releases another move's slot. Cross-section destination handling also fixes three cases that placed an item on the wrong side of a divider.
- **Discovery makes progress under load.** Scans rotate through app owners so slow apps cannot repeatedly use up the budget before later owners are reached. Late scan results cannot overwrite newer state, and incomplete scans cannot discard retained items or replace your saved order.
- **Thaw's controls keep their identities.** Position-key matching distinguishes the Visible, Hidden, and Always Hidden controls by their titles instead of treating a lone nearby control as a match.
- **Manual arrangement skips the remaining repair paths.** Restriction changes no longer schedule repairs in manual mode. Corrective pulses, automatic unparking, boundary repairs, and structural position rewrites also stop when manual mode is selected during a wait. Refused manual-mode moves no longer count toward repair-failure suppression. Native Command-dragging remains yours to control; hiding and revealing still work.
- **Droppy's persistent panel no longer blocks automatic rehide.** Thaw excludes Droppy's layer-100 overlay from menu detection while retaining its standard popup-menu level. Existing candidate windows are also tracked before their owner's item reaches the cache, so discovering an app no longer turns its already-open panel into a newly opened menu.

### Fixed

- **Capture jitter on 5 items fixed.** Five menu bar items (1Password, Hookshot, WisprFlow, CleanShotX, Okta) oscillated 1 pixel on every capture cycle because of sub-pixel rounding. The capture bounds tolerance is raised from 0.5pt to 1.0pt, so the capture loop stops spinning while Settings is open.
- **49pt menu bar hosting window found.** On displays with a 49pt menu bar (larger displays, different scaling), the hosting window was never matched because the geometry check capped at 40pt. The threshold is raised to 60pt (point space) and 120px (pixel space), so system items (Clock, Control Center, Wi-Fi, Now Playing) get their clean hosting-window captures instead of falling back to the display strip every cycle.

### Under the hood

- **@Observable migration.** StatusIconWidgetController, NotchClockWidget, NotchMediaWidget, and NotchAccessoryWidget migrated from ObservableObject + @Published to @Observable, for per-property observation instead of whole-object invalidation.
- **@Animatable macro.** NotchShape's manual animatableData replaced with the @Animatable macro (macOS 26+), with @AnimatableIgnored on non-animating properties.
- **Native pickers in settings forms.** ThawPicker no longer applies glass to every picker. It uses the system menu style, so settings content reads as stable and opaque while glass is reserved for floating panels.
- **Glass scoping.** The Thaw Bar preview no longer wraps in an extra glass frame. It matches the real panel's treatment: sampled color, card corner, shadow. Colored drop shadows removed from informational notices.
- **Search routing.** Every relocated control's search entry routes to its new home with the right disclosure exposed. Reveal, rehide, search, and tooltip entries land on Visibility directly. Contextual-menu entries land on General. Auto-zen lands on Automation.

### Known issues

- An app with several menu bar items that renamed them in the macOS 27 upgrade may need those items reassigned once by hand.
- Items whose title is live text (a temperature, a clock, a transfer rate) are placed by macOS from memory rather than from the layout table. They can land next to where you put them rather than exactly there.
- Flux cannot be seen or properly handled by Thaw.
- Toggling Hidden can briefly show Always Hidden items in the menu bar during the redraw, even though they return to the correct concealed state. This visual flash remains unresolved.

---

## [2.1.0-beta.3] - 2026-09-14

Hey, we have a Discord! Come say hi: [discord.gg/KDfWjWDnR4](https://discord.gg/KDfWjWDnR4).

Please report issues at [github.com/thaw-app/Thaw/issues](https://github.com/thaw-app/Thaw/issues).

<a href="https://www.producthunt.com/products/thaw-2?embed=true&amp;utm_source=badge-featured&amp;utm_medium=badge&amp;utm_campaign=badge-thaw-3" target="_blank" rel="noopener noreferrer"><img alt="Thaw - The only app that owns your whole menu bar, in and out | Product Hunt" width="250" height="54" src="https://api.producthunt.com/widgets/embed-image/v1/featured.svg?post_id=1239794&amp;theme=light&amp;t=1788423441056"></a>

Thanks to @wiper2 for the spacing report and crash logs, @lucifercraig12345-create for the search freeze, the spacer crash, and the external-drive trigger request, @Chamiu for the `dropReverted` report, @ppocass for tracing a menu bar that never rendered, @leos for the spacing-restart report, and @balaji-dutt for the stuck-rehide and localized-ghost diagnoses.

Spacing changes no longer kill system services that cannot be brought back, and you can now turn the restart wave off entirely. You can also sort a section alphabetically, remove stale displays from the list, type in the search panel the moment it opens, and reveal a hidden item while an external drive is mounted. Five reported bugs and four more found while fixing them are in here, plus three image-capture performance changes, and three ways automatic layout work used to fight whoever was using the mouse.

---

### Upgrade from 2.1.0-beta.2

1. Update in place through Sparkle on the beta channel. Stable stays on 2.0.1 until 2.1.0 leaves beta.
2. No schema or `defaults` changes. Profiles, saved layouts, and hotkeys carry over untouched.
3. Spacing changes leave some items alone, and you can turn the wave off. An item whose owner Thaw declines to restart keeps its previous spacing until that app next starts, so the bar can look uneven for a while. "When applying spacing" under Settings, Displays has a "Wait until next restart (no apps restarted)" option that stops Thaw restarting apps for a spacing change at all. `FREQUENT_ISSUES.md` lists what Thaw will and will not quit.
4. An app that refuses a quit request is no longer force-terminated. If it is holding an unsaved document, it stays running and keeps its old spacing.

---

### Spacing

1. Changing menu bar spacing no longer kills system services that cannot be brought back (#1070, thanks @wiper2). The relaunch wave now triages each app first: indexed LaunchAgents restart through `launchctl`, system binaries with no label and processes with no launchable bundle are left running, and ordinary apps are quit and launched back. Anything left running is dropped from the set the wave waits to reattach.
2. You can apply a spacing change without restarting your apps (#1071, thanks @leos). "When applying spacing" under Settings, Displays now offers "Wait until next restart (no apps restarted)", which writes the preference and leaves every app running. The new spacing appears the next time each app starts. The "Confirm before relaunching apps" toggle and its save-scope picker only appear when a relaunch wave can actually fire.

### Displays

1. Remove stale displays from the Per Display list (#1054). A Remove control on each disconnected display drops its cached name and settings. A display you connect again reappears on its own.

### Menu bar layout

1. Sort a section alphabetically (#936). Each section heading in Settings, Menu Bar Layout has a Sort A→Z button. Closed apps keep their saved slot, and the order is written to the active profile.
2. A stuck rehide no longer freezes a position in place (#1079, thanks @balaji-dutt). An app that runs since boot never relaunches, so a failed rehide used to block the item's saved position forever. Thaw now ages that state out after a day.
3. Localized Control Center ghosts are pruned (#1080, thanks @balaji-dutt). On a non-English system, Control Center's localized name could land in an item identifier and persist forever, duplicating the canonical entries. Thaw now drops those copies when the canonical namespace is present.

### Triggers

1. Reveal a hidden item while an external drive is mounted (#1053, thanks @lucifercraig12345-create for the request, @alvst). A trigger can now match any external drive, an exact case-insensitive drive name, a removable drive, a network volume, or a volume UUID. Thaw observes volume mount, unmount, and rename notifications and reevaluates triggers when mounted volumes change, so an NTFS helper or any drive-tied utility appears while its drive is connected and hides again when it ejects.

### Layout work stays out of your way

Three separate ways an automatic batch could work against whoever was using the mouse at the time.

1. Bulk layout work has one owner. A profile apply, a background re-sort, and a saved-order restore could all run at once and write over each other. Each claims a lease ranked by authority now: a profile you selected supersedes background work and never the reverse, and a superseded batch stops at its next move.
2. Automatic batches wait for a pause in physical input, and check again between moves, deferring the rest when input resumes. The detector now reads HID timestamps for mouse-down, up, and dragged events across left, right, and other buttons, not just movement and scroll, so a click during a batch is still detected after the button is released.
3. The cursor stays where you left it. Restoration now runs only when the HID timestamps show no physical pointer input since the operation took ownership, so it no longer warps the pointer back if you moved the mouse mid-batch.

### Search

1. The search panel takes your first keystroke (#969). The field is now first responder as soon as the panel opens, instead of needing a click first.
2. Typing in the settings search field no longer freezes the app (#1055, thanks @lucifercraig12345-create). Each row in `SectionedList` re-measured itself on every keystroke. The per-row frame tracking is gone.

### Fixed

1. Adding a spacer to a visible section no longer crashes (#1056, thanks @lucifercraig12345-create). A zero-length status item can stay a synthetic window with no representable window ID. The status item, and now spacers too, start one point wide before taking their intended width.
2. A move started just after an app updates no longer reverts (#1058, thanks @Chamiu). The `isOnScreen` bit was trusted without checking where the item actually sat, so a move that had landed was reported as `dropReverted`. The geometry is checked first.
3. A menu bar that never renders because of a bad window number is caught rather than acted on (#1060, thanks @ppocass). `CGWindowID(exactly:)` accepted any value that fit. `windowServerID(windowNumber:)` rejects zero, negative, and non-representable values.
4. Clicking one of Apple's own menu bar items opens the right thing. Activation tried `AXShowMenu` first, but Apple's status items read that as a contextual-menu request. Only `AXPress` is used now.
5. Moves resolve their endpoints against live windows. Endpoint validation leaned on persisted PID seeds and title-matched ownership, so a stale endpoint could pass for a current one. `refreshMoveEndpoints` re-reads the exact windows a move will use, so a failed live resolution rejects the move.

### Performance

1. Menu bar item images refresh off the main actor. `refreshImages` was `nonisolated`, which under Approachable Concurrency kept the caller's actor, so the bounds queries, crop, and copies ran on the main thread. They run on the background pool now.
2. Blink triggers capture only the items they watch. One enabled trigger used to make the live loop capture every concealed item. The cache now takes the identifiers the enabled triggers name and captures those alone. The global "surface items seeking attention" setting is unaffected.
3. Those captures go out as one request instead of one round trip per watched item.

## [3.0.0-alpha.3] - 2026-09-13
Toggling the hidden section no longer shuffles your items, and Thaw's own icon stays where you put it. Clicking the Clock opens Notification Center without showing the items you hid. Apps that quit leave the layout editor. Siri no longer opens Settings on every message. Right-clicking Thaw's icon works on the first try. And a crash when Thaw pressed one of its own items from a background thread is gone. The Thaw Bar answers on the first click now, closing Settings no longer takes Thaw down with it, and the layout editor shows the same folded bars as Simple Mode. There is also a first prototype of a build-your-own status icon, in Settings under Widgets.

Something broke? [Open an issue](https://github.com/thaw-app/Thaw/issues/new/choose). Something missing? [Tell us here](https://github.com/thaw-app/Thaw/discussions).

---

### Upgrade from 3.0.0-alpha.2

1. Nothing to do. The menu bar layout access grant, profiles, saved layouts, and hotkeys carry over.
2. The first time you show the hidden section after updating, the bar may settle once. After that it stays put.

---

### Build your own status icon (prototype)

- **Compose an icon from three slots.** An outer arc or ring, a center symbol, and a bottom row of dots or bars. Each meter tracks a reading: battery, Wi-Fi strength, volume, or CPU. Find it in Settings under Widgets.
- **The symbol follows the real connection.** On Ethernet it draws Apple's classic Ethernet glyph, on Wi-Fi the bars move with signal strength, and cellular, other connections, and offline each get their own symbol. It reads the actual default route, so a plugged-in Mac shows the cable no matter what the Wi-Fi radio is doing.
- **Publish it as a real menu bar item.** It updates every two seconds, stays up when you close Settings, and comes back on its own at the next launch. Clicking it shows the same readings in a menu, with a shortcut to Network Settings. The pane carries an Alpha badge; live data can be switched off for sliders if you would rather test with your own values.

### Menu bar

- **Manual arrangement is now hands-off.** When manual arrangement is on, Thaw only hides and reveals. It never reorders, repairs, or rewrites positions. You drag, the bar stays. ([#1092](https://github.com/thaw-app/Thaw/issues/1092), thanks @nullsin and @1Hendrix for the weight traces that proved the boundary-repair path was bypassing the manual gate)
- **Show and hide keep your order.** In alpha.2 a reveal could come up in the right order and then re-sort itself half a second later, and the bar sometimes came back in a different order on the next toggle. Both were Thaw rewriting the layout table right after a reveal, once from a scan that had not finished and once from a scan that missed apps still waking up. The pass now waits for its own reveal, finishes with the full item set, and writes nothing when the table is already right. After a restart, with apps still launching, the order held across every toggle we tried.
- **The layout engine re-seats only what moved.** A toggle used to rewrite every item's position weight, 16 to 18 per cycle, with the visible control bouncing to the middle and back. The engine now keeps the weights of items that are already where they belong and seats only the misplaced ones. Toggles write 0 to 3 weights instead of the whole run.
- **Thaw's icon stays at its end of the bar.** A repair pass treated Thaw's own control as a regular item and could seat it in the middle of the bar, beside the section divider. It never moves Thaw's controls now. The small jiggle of the icon on each toggle is gone with it, since it was the side effect of the same redundant writes.
- **Clock click without the reveal.** Opening Notification Center from the Clock used to drop the hiding restriction for as long as the panel stayed open, so every hidden item appeared behind it. The strip is now masked for the instant the press needs, the restriction comes straight back, and the hidden items never paint. The mask now lifts after half a second instead of three and a half, so the panel feels immediate.
- **Quit apps leave the layout on their own.** macOS 27 does not always post the termination notification for agent apps. Some quit without either a launch or a terminate event ever reaching Thaw. The cache is now swept for departed owners on every tick, so a quit item's tile leaves the layout editor and the Thaw Bar within a few seconds instead of waiting for a relaunch. ([#1098](https://github.com/thaw-app/Thaw/issues/1098), thanks @BruceInLouisville for the CardHop report that led us to the notification gap)
- **Quitting Thaw keeps your reorders.** The quit-time restore wrote back a snapshot taken at first launch, undoing every move made during the session and re-laddering them on the next start. It now only puts back the items Thaw itself parked.
- **Stuck repairs come back.** A boundary repair that failed twice was switched off for the rest of the session, which left items stranded until you dragged them by hand. It re-arms after 60 seconds.
- **No false alarm at launch.** macOS registers Thaw's own dividers a second or two after start. The "section dividers are hidden by macOS" alert no longer fires during that window; a divider that stays missing past the settling period still raises it.
- **The Thaw Bar shows on the first click.** On some Macs the first click after launch reported the bar as open but drew it just off the right edge of the screen, so nothing appeared until a second click. The bar is now measured and placed on the display you clicked before it opens.
- **One slow app can't stall the scan.** Processes that answer accessibility slowly (Adobe's IPC broker, WebKit content processes) could use up the whole scan budget before any item was collected, leaving the Thaw Bar stuck on "Loading menu bar items". Each app now gets its own deadline, so one laggard slows its own items, not the bar. The deadline is enforced through a cancellation-aware continuation race, so a hung accessibility call is actually interrupted instead of measured and ignored. ([#1099](https://github.com/thaw-app/Thaw/issues/1099))
- **Joined walk callers see one answer.** Two callers sharing an in-flight walk used to get different results: the initiator got the last-complete fallback, the joiner got the raw partial list, and live items could read as departed. Settling now runs once inside the walk task, so every caller sees the same answer.
- **Cooldown skips are honest.** A slow app skipped by cooldown reported the walk as complete, overwriting the last-complete list without it. Skips now mark the walk truncated.

### Layout editor

- **Same folded bars as Simple Mode.** The layout pane embeds the folded menu bar directly instead of a wrapper around it, which also fixes dragging in the pane that the wrapper had broken.
- **Drop targets light up.** Dragging an item over a section draws an accent band on that strip and highlights its name in the gutter.
- **Reduce Motion is honored.** With it on, reorder slides are skipped.

### Fixed

- Pressing one of Thaw's own items from the runtime's accessibility presser crashed the app on a main-actor assertion. The press now hops to the main thread itself.
- Siri no longer opens Thaw Settings on every message send. The reopen handler now checks whether Thaw is frontmost: a dock or app-icon click brings it forward first, an activation cycle does not. ([#1082](https://github.com/thaw-app/Thaw/issues/1082), thanks @Mason-Boom)
- Right-clicking Thaw's icon no longer flashes the context menu or needs multiple clicks. The menu was opening one run-loop hop after the event tap returned, so a quick right-click raced the menu's tracking loop against the mouseUp. The call is now synchronous, so the menu opens during the event tap callback before the mouseUp is processed.
- Right-clicking an item sometimes took several tries because the hit test used the item's old position after the bar reflowed. The test now allows 10 points of slack.
- Closing the Settings window could quit Thaw outright. macOS 27 can terminate an app that deactivates with no visible windows, and Thaw deactivated itself when its last window closed. It now drops to the background without that call, so the window closes and Thaw stays in the menu bar.
- What's New shows a release on the date the changelog says, instead of a day early in time zones west of UTC.
- Simple Mode's bar uses one continuous corner radius and a hairline separator instead of the themed border.
- Strip captures no longer show black squares or wallpaper bleed. ScreenCaptureKit's first complete frame can arrive before the menu bar finished redrawing, so crops read as solid black or showed the desktop behind the bar. The capture now holds the stream open briefly and prefers the settled composite.
- Saved placements survive startup. The ghost prune no longer deletes entries whose bundle cannot be resolved by LaunchServices. Inner-bundle helpers (Fantastical's team-ID-prefixed helper, for example) are never registered with LaunchServices, and absence from one walk proved nothing.
- The clock reveal mask lands on the right display. On a display stacked above or below the primary, the mask used the target display's height for the coordinate conversion. It now anchors to the primary display's height, so the mask covers the menu bar instead of sitting off it.
- The battery widget reads real charge. IOPSCopyPowerSourcesList returns opaque handles, not dictionaries. Each handle is now resolved through IOPSGetPowerSourceDescription per the SDK contract, so the widget reports the actual percentage instead of 0%. The live system readings (CPU, Wi-Fi, battery), the power source watcher, and the multi-item status bar publishing pattern are all adapted from [Barometer](https://github.com/mackid1993/Barometer) by @mackid1993, used with permission.
- Concealed captures register in the LRU. Disk gap-fill captures that were never read or recaptured sat outside the trimmer. They are now registered on load.
- Routine failures are no longer logged as errors. A window frame that refuses to report (routine on a live bar), a cancelled capture (how a superseded pass retires), and a nil display at startup (fires a few times then never again) are all debug-level now.
- On restart, hidden items could flash for a moment before the Thaw Bar took over. The reveal now sits behind the same mask the Clock uses until the panel is up.

### Thanks

The icon-dancing issue from the earlier alpha.3 builds was rough on a lot of you, and your patience while we tracked it down through the layout engine, the manual-arrangement gate, and the weight-assignment path made the fix possible.

Thank you to @nullsin and @1Hendrix for [#1092](https://github.com/thaw-app/Thaw/issues/1092), @cookie-drummer for testing the fix, @BruceInLouisville for [#1098](https://github.com/thaw-app/Thaw/issues/1098), @mrleblanc101 for [#1087](https://github.com/thaw-app/Thaw/issues/1087) and [#1088](https://github.com/thaw-app/Thaw/issues/1088), @gigecogary for [#1089](https://github.com/thaw-app/Thaw/issues/1089), and @Mason-Boom for [#1082](https://github.com/thaw-app/Thaw/issues/1082). Thank you to @fishcharlie and @joaofrgomes for testing. The live system readings, power source watcher, and status item publishing pattern are adapted from [Barometer](https://github.com/mackid1993/Barometer) by @mackid1993, used with permission. And thank you to everyone in the Discord who reported issues, sent logs, and tested builds between releases. Every report shaped this one.

### Known issues

- iStats menu bar items may be hidden when another item gets hidden. We are working with the iStats developers to resolve this issue.
- An app with several menu bar items that renamed them in the macOS 27 upgrade may need those items reassigned once by hand.
- Items whose title is live text (a temperature, a clock, a transfer rate) are placed by macOS from memory rather than from the layout table. They can land next to where you put them rather than exactly there.
- Flux cannot be seen or properly handled by Thaw.

## [3.0.0-alpha.2] - 2026-09-11
We reenable the cursor free method, reorders now land the moment you drop an item, and the cursor stays yours. Plus, a fix for layouts saved on macOS 26 being discarded on 27.

Hey, we have a Discord! Come say hi: [discord.gg/KDfWjWDnR4](https://discord.gg/KDfWjWDnR4). Something broke? [Open an issue](https://github.com/thaw-app/Thaw/issues/new/choose). Something missing? [Tell us here](https://github.com/thaw-app/Thaw/discussions).

<a href="https://www.producthunt.com/products/thaw-2?embed=true&amp;utm_source=badge-featured&amp;utm_medium=badge&amp;utm_campaign=badge-thaw-3" target="_blank" rel="noopener noreferrer"><img alt="Thaw - The only app that owns your whole menu bar, in and out | Product Hunt" width="250" height="54" src="https://api.producthunt.com/widgets/embed-image/v1/featured.svg?post_id=1239794&amp;theme=light&amp;t=1788423441056"></a>

Thanks to @lathe-agent-oa (@TheBenMeadows) for [#1085](https://github.com/thaw-app/Thaw/issues/1085), the report that showed how layouts saved on macOS 26 were being discarded on 27, complete with the identifier pairs that made the fix possible.

---

### Upgrade from 3.0.0-alpha.1

1. Thaw asks for one new permission on launch: access to the menu bar layout table. A file panel opens on that one file. Select it, press Grant Access, done. Full Disk Access still works if you prefer it.
2. Nothing else to do. Profiles, saved layouts, and hotkeys carry over untouched.
3. Layouts saved on macOS 26 come back. Items that changed identity with the upgrade are matched to their saved entries again.

---

### Menu bar

- Reorders write the layout table. macOS 27 keeps every item's position in one protected file. With access to it, a move is a write and the bar re-sorts on its own in well under a second. The synthetic drag that hid the cursor and held your mouse for a second and a half is off.
- Menu bar layout access is the permission behind that write. You select the file once. The grant survives relaunches, app updates, and system updates. It is required, so onboarding asks for it next to Accessibility.

### Fixed

- When a saved layout does not apply, the log now says whether the order already matched or whether the saved entries no longer resolve to anything on the bar.

### Known issues

- iStats menu bar items may be hidden when another item gets hidden. We are working with the iStats developers to resolve this issue.
- An app with several menu bar items that renamed them in the macOS 27 upgrade may need those items reassigned once by hand.

## [3.0.0-alpha.1] - 2026-09-09

Thaw 3 is Thaw rebuilt and redesigned for macOS 27. A new engine on the platform's own model, a new settings window, new glass everywhere, and Swift 6.4 underneath.

Hey, we have a Discord! Come say hi: [discord.gg/KDfWjWDnR4](https://discord.gg/KDfWjWDnR4). Something broke? [Open an issue](https://github.com/thaw-app/Thaw/issues/new/choose). Something missing? [Tell us here](https://github.com/thaw-app/Thaw/discussions).

<a href="https://www.producthunt.com/products/thaw-2?embed=true&amp;utm_source=badge-featured&amp;utm_medium=badge&amp;utm_campaign=badge-thaw-3" target="_blank" rel="noopener noreferrer"><img alt="Thaw - The only app that owns your whole menu bar, in and out | Product Hunt" width="250" height="54" src="https://api.producthunt.com/widgets/embed-image/v1/featured.svg?post_id=1239794&amp;theme=light&amp;t=1788423441056"></a>

Thank you to the more than 80 people who ran the preview builds, sent logs, and told us what broke. Every one of the areas below was shaped by those reports.

---

### Upgrade from 2.x

1. macOS 27 Beta 8+ is required. There is no 2.x compatibility layer.
2. Update channel is Nightly for now.
3. The Ice-era settings migrations have been removed. They could never run against the new defaults domain, so nothing is lost by dropping them.

---

### Not here yet

Three things from the 2.1 preview line are still on their way to macOS 27. Another one will be available on a future update.

- Scripts: script-driven bar modules are being tested by macOS 26 users on the 2.1.0 beta and will be added in a later 3.0 build. The Scripts pane is here as a preview of where they will live.
- Widgets: the Widgets pane is a placeholder so the destination is discoverable; it holds no settings yet.
- Item triggers: the full condition engine from 2.1, where an item moves on battery level, the frontmost app, a network, a Focus, and the rest, is not ported yet. What is here is the reveal-on-icon-change rule.
- Rotating diagnostic logs: the system for keeping and cycling through diagnostic logs is not yet implemented; it will appear in a future 3.0 build.

---

### New

#### Menu bar

- Manual arrangement: Thaw never moves an item. You arrange the bar yourself with ⌘-drag, Thaw records what it sees and confines itself to hiding. Classic menu bar manager experience.
- Zen mode seals the whole bar with one hotkey. Reveals and hover tricks stand down until you toggle it back.
- Item groups bundle items so they move as one, including across sections. Same-app clusters group on their own and dissolve on request.
- Spacer items create gaps on purpose: pick a width and drag them like any item.
- Items that ask for attention can surface themselves. A blinking icon briefly shows the section holding it, with a cooldown so a chatty icon cannot keep the bar open. Off by default.
- App icons where captures cannot go: items nobody can capture draw their owning app's icon, so the Thaw Bar, the layout pane, and search work with Accessibility alone.
- Presenter mode: with the camera and microphone watch on, the bar collapses to zen mode while either is in use and restores after. It works alongside zen mode while presenting.
- Confirmations: a small capsule under the bar confirms the verbs that otherwise succeed invisibly (zen on, hidden items shown, profile applied).

#### Thaw Bar and appearance

- A Thaw Bar of its own: shape, tint, and border for the bar, independent of the menu bar it mirrors, and one per-display section instead of repeated blocks.
- Adaptive Gradient tint builds a gradient from the wallpaper's two dominant colours instead of one average. Wallpaper changes re-tint the bar at once; the poll stays only for dynamic and aerial wallpapers.
- Per-Space appearance overrides, so the bar can dress differently on each Space.

#### Layout

- A standalone layout editor opens on its own from a hotkey or a `thaw://` action, with glass chrome and last-pane restore. Items can be activated straight from it.
- Hover spotlighting: resting on a tile in the layout pane lights the matching item in the real bar. Clicking it opens the inspector.
- Displays as a spatial picker, arranged the way they sit on your desk, with per-display spacing applied inline.

#### Search and launchers

- Search remembers. Recently activated items sit at the top of an empty query, and selecting a result spotlights the item in the real bar.
- Item palette (Lab): a centred launcher for your menu bar items, hidden ones included. Type part of a name or the owning app and press Return.
- Assisted item palette (Lab): a large list of every item right where the pointer is, with big rows to read and click.
- Menu bar magnifier (Lab): rest the pointer on the bar and a blown-up slice appears below it. Each icon gets a large outline you can click, and the one you point at is named. Works without Screen Recording; the pixels need it.

#### Settings

- Simple Mode collapses Settings to one page, ordered by what you touch. Everything it hides is still there when you switch it off.
- Sidebar by topic: Menu Bar, App, Automation, and More. Rows carry a plain glyph, groups fold, arrow keys move through rows and Return selects, and a profile strip pinned to the foot switches profiles without opening the Profiles pane.
- Search in the toolbar. Results take over the detail column with a result count and an empty state that names the query.
- What's New and Acknowledgements are reading pages: a path of releases along the top, one large title with the release date under it, and the notes at reading size on the app's own glass.
- A Tools pane gathers the troubleshooting helpers in one place, with the destructive ones last.
- Onboarding is restyled in the same language as the rest of the app. Welcome to the new Thaw, arrange the real bar with a Tidy for me option, then ask for access. Denying Accessibility no longer strands you, Screen Recording is asked for once and takes no for an answer, a first-run hint teaches hiding in place, and onboarding can be replayed from Settings.
- Accessibility: Reduce Transparency, Increase Contrast, and Reduce Motion are honoured on every glass surface. Icon-only buttons have names, the sidebar rail is reachable by keyboard, selection is marked without relying on colour, and type sizes follow the Dynamic Type scale.
- Layout backups can be restored inside Thaw, from the Tools pane.

#### Privacy

- A Privacy pane: permissions, the capture inspector that shows exactly what the app reads from the screen, and every network call the app makes, each with a switch and one button to turn them all off. A test fails the build if a network client appears anywhere the list does not account for.
- Camera and microphone watch (Lab): a banner names the app that took the microphone, and another says when a camera turns on. While either is in use, Thaw's menu lists what is using it. Banners can be pinned to a display, or follow the pointer, and placed left, centre, or right.
- Menu bar history (Lab): when items appeared in and disappeared from the bar, stored in Thaw's own settings and cleared when the experiment is turned off.

#### Profiles and Spaces

- Per-Space profiles: bind a profile to a Space the way it binds to a display. Precedence is Focus Filter, then Space, then display.
- Per-Space presentation: show or hide the bar per Space, and see which Space each rule belongs to.
- A profile shows what applying it would change before you apply it.

#### Automation, Shortcuts, and the command line

- Rules: reveal on icon change with a cooldown, global and per-profile hooks that run a script when a profile applies, a script environment with its own variables and timeout, and a whitelist of apps allowed to change settings over `thaw://`.
- Shortcuts and Spotlight: an action opens a chosen item's menu, revealing it first if hidden, alongside actions to reveal hidden items, toggle zen mode, and apply a profile.
- Control Center widgets toggle hidden items and zen mode from Control Center.
- A command-line client: `thawctl` drives the `thaw://` control plane from a terminal.

#### The Lab

- A home for experiments you can opt into early. Turning any experiment off returns the app to normal, and each one says exactly what it does.
- Menu bar overlay: your items drawn in a Thaw strip that appears when you point at the space they left, while the system bar keeps its app menus, clock, and modules.
- Show item details on hover (beta): a small readout under an item while the pointer rests on it, showing what the item already reports.
- Hide Finder menus on the desktop: clicking the desktop puts Finder's menus in the bar; this covers them until you switch away.
- Transport bar: a floating capsule at the bottom of the display your pointer is on, with the active profile, the hidden and always-hidden toggles, zen mode, and a close button. It never takes focus.

### Changed

#### Under the hood

- Rebuilt from the ground up on a new architecture. Thaw 3 is a new codebase, not a patched fork. The item manager cluster, AppState, MenuBarManager, the image cache, the layout bar, ControlItem, appearance, and search were written anew; the Ice-branded identifier vocabulary is Thaw's own, with persisted keys pinned so nothing you saved is lost; and the migrations that could never run are gone. The rewrite paid down years of technical debt at the same time: dead machinery and one-case abstractions are deleted, the engine sits behind explicit seams that can be tested in isolation, and the hot paths were rebuilt with performance in mind.
- Reorders are planned as a diff. The engine computes the smallest set of moves against the live order instead of walking the bar pair by pair. The seconds of silence before a synthetic drag starts are gone, the native overflow chevron is treated as menu bar chrome rather than an item, and on a notched display concealed items are revealed for capture one at a time.
- Swift 6.4 and strict concurrency. The `@Observable` migration is complete, with zero `ObservableObject` conformances left. Detached tasks moved onto `@concurrent` callees, workspace notifications are debounced through swift-async-algorithms, and the engine reads its settings through a configuration protocol instead of reaching into AppState.
- Every ScreenCaptureKit call has a watchdog, so a capture that never answers cannot hang the refresh loop. An XPC capture helper is built in and off by default until it has been verified on macOS 27.
- Less idle work. The polls that used to ask the window server questions whose answers had not changed now latch, memoize, or rate-limit, and the glyph cache publishes only when a glyph actually changed.

### Known issues

- On a notched display, when the frontmost app's menu is long enough to wrap past the notch, Thaw can repeatedly try to move items and briefly take the cursor. A fix is coming in alpha 2.
- iStats menu bar items may be hidden when another item gets hidden. We are working with the iStats developers to resolve this issue.

## [2.1.0-beta.2] - 2026-09-05

Hey, we have a Discord! Come say hi: [discord.gg/KDfWjWDnR4](https://discord.gg/KDfWjWDnR4).

Please report issues at [github.com/thaw-app/Thaw/issues](https://github.com/thaw-app/Thaw/issues).

<a href="https://www.producthunt.com/products/thaw-2?embed=true&amp;utm_source=badge-featured&amp;utm_medium=badge&amp;utm_campaign=badge-thaw-3" target="_blank" rel="noopener noreferrer"><img alt="Thaw - The only app that owns your whole menu bar, in and out | Product Hunt" width="250" height="54" src="https://api.producthunt.com/widgets/embed-image/v1/featured.svg?post_id=1239794&amp;theme=light&amp;t=1788423441056"></a>

Thanks to everyone who tested the beta and sent logs. @commanderk33n found and fixed the Spotlight crash. @CamilleGuillory and @nk-tedo-001 co-authored the settings work. @3raxton reported the launch icon and profile layout bugs, @nickawilliams reported the Thaw Bar toggle, and @joaofrgomes helped pin down how item spacing really behaves.

This build has two new features, a rework of how Thaw moves items on its own, and four reported fixes. The worst of the fixes is not a beta bug at all: changing menu bar spacing could kill Spotlight outright, and it stayed gone until the machine was rebooted (#720, found and fixed by @commanderk33n). Spacing is re-applied whenever a display connects or disconnects, so the crash fired again on every dock and undock. From the beta.1 reports: revealing a hidden item could drop it on the wrong side of the chevron, so the reveal failed and the item stayed put (#1035); the "Thaw took too long to respond" report turned out to be a Control Center window left behind by an exited Thaw process, freezing the item cache for as long as it stuck around (#1032); and the Capture Inspector was showing people the bottom of their screen instead of their menu bar (#1033).

---

### Upgrade from 2.1.0-beta.1

1. Update in place through Sparkle on the beta channel. Stable stays on 2.0.1 until 2.1.0 leaves beta.
2. No schema or `defaults` changes. Profiles, saved layouts, and hotkeys carry over untouched.
3. If you have been clearing a stuck menu bar with `killall ControlCenter`, you should not need to after this update.
4. Menu bar items that launchd owns, Spotlight and Dock and WindowManager among them, are now restarted through `launchctl` when a spacing change is applied. That is a hard restart rather than the graceful quit they used to get, which is the operation launchd is built for but is still a change in behavior.

---

### New

1. Image-change triggers gain comparison modes and a preview (#1006). A condition can compare the current icon to its captured reference in two ways: Fuzzy, which ignores small rendering noise, or Exact, which reacts to any normalized pixel-content difference. The trigger editor shows the captured reference icon and asks for a recapture when an older reference is switched to Exact. Existing saved conditions keep working and read as Fuzzy.
2. Failed automatic moves save a redacted diagnostic report (#994, #1004). Section placement, new-item relocation, control-divider ordering, saved-layout and profile application, and notch-overflow rebalancing all route through the same rule: a definitive failure saves a redacted report, Thaw keeps the newest 20, and a notification opens the file in Finder. Cancelled, superseded, stale, transient, and input-busy outcomes stay silent. Presentation cooldowns keep one failing item from turning into an alert storm, and no cooldown suppresses the report itself.

### Fixed

1. Changing menu bar spacing no longer kills Spotlight until the next reboot (#720, thanks @commanderk33n). Thaw terminated each menu bar item and relaunched it with `NSWorkspace.openApplication(at:)`, which makes Thaw the launching parent. A system LaunchAgent can carry a launch constraint that permits launchd as its only launching parent, so the kernel killed the new process at exec: every `Spotlight-*.ips` report ends in a CODESIGNING termination, "Launch Constraint Violation", with no frames on the faulting thread and a process that lived about ten milliseconds. Two things then made it permanent. The fallback relaunch retried the same illegal launch and produced a second crash report about eight seconds later, and `com.apple.Spotlight` sets `KeepAlive.SuccessfulExit=false`, so launchd would not respawn it either: `terminate()` is a successful exit. Spacing is re-applied on display connect and disconnect, which is why this landed on every dock and undock. Items owned by a system LaunchAgent are now restarted with `launchctl kickstart -k gui/<uid>/<label>` at both relaunch sites. The label comes from the agent's own plist rather than from the bundle identifier, because the two diverge on exactly the items that matter: `com.apple.dock` is labelled `com.apple.Dock.agent`, `com.apple.systemuiserver` is `com.apple.SystemUIServer.agent`, and nine of the twenty-six LaunchAgent-backed processes on a stock system differ this way, so a bundle-identifier rule would have rescued Spotlight and quietly missed the rest. `launchctl` is declared in `Info.plist` the way the existing `defaults` path is, so it is never resolved through `PATH`.
2. A Control Center window left behind by an exited Thaw no longer freezes the item cache (#1032). Control Center can outlive the Thaw process whose status item it hosted and go on serving the window. The reporter carried one across three relaunches until `killall ControlCenter` cleared it: window 639, tagged under Thaw's own bundle identifier, capturing no image and answering to no owner. Thaw took it for one of its own twice over. It was planned against as an unmanaged item, so live items were moved relative to a window with nothing behind it, and the log has Battery moved to the right of it. It is also self-titled under Thaw's own namespace, which makes it the first signal read as a bar-wide window-name degradation, so every reading that contained it was thrown away as a failed observation: 436 of them across the reporter's three logs, each one holding a cache that had been stale since the orphan appeared. A reorder planned against a frozen cache is the "took too long to respond" the report is titled after. These windows are now dropped alongside the duplicate control items, before the degradation check, which already expects ghost windows to be gone by the time it runs. Ownership is decided by window number rather than by title, so a control item of Thaw's own whose title really has degraded stays in the reading and still reaches that check.
3. Revealing a hidden item lands it on the side of the chevron it was aimed at (#1035). A temporary show drops the item left of the chevron at exactly the chevron's own minX. That coordinate is the boundary itself, so AppKit is free to place the item on either side of it, and here it picked the wrong side: attempt 2 in the reporter's log planned a target of 837.0 and then measured the item at 863.0, past the trailing edge of a 26pt chevron. The ordinal check rejected that landing, correctly. The one-point bias added for #923 already solves this, but it skipped the chevron on the grounds that the chevron divides no sections and so resolves no ambiguity. What makes a drop point ambiguous is that it is an item's own edge; whether the item divides two sections has nothing to do with it. The chevron is biased now too. The retry budget behind that move is also restored: the fast path cut it to 2 in 2.0.0-beta.2 so that a failing retry loop would not show as jitter, which left a reveal one wrong guess away from giving up, and that is where the reporter's bisect lands, since 1.2.0 gave the move all 8 attempts. The second half of the report stays open. A move that exhausts its attempts still delivers a real click to whatever sits under the cursor.
4. The Capture Inspector shows the menu bar rather than the bottom of the screen (#1033). It built its band from `NSScreen.frame`, which puts the origin at the bottom left, and then handed that band to a capture path that assigns it to `SCStreamConfiguration.sourceRect`, where the origin is at the top left and y increases downward. Read the second way, `frame.maxY - menuBarHeight` is a distance measured down from the top of the display, so on a display of height H the inspector selected the strip at H minus the menu bar height: the bottom edge of the screen, and whatever window happened to be sitting there. Nothing downstream could catch it. Both readings produce a band of identical size, so the pixel dimensions in the log looked right, and the rect stayed inside the display so the bounds guard passed. The band now comes from `CGDisplayBounds`, which is already in the coordinate space the capture expects, and the screen bounds, display frame, and computed source rect are all logged, so a future misplacement is legible from a log instead of only from a screenshot.

---

1. The Thaw Bar keeps its cached glyphs across window ID changes (#1046). Icons no longer blank out when items are recycled behind the scenes.
2. No blank slot for the Thaw icon at launch (#1043). The icon's hidden preference was applied only after the first asynchronous settings pass, so a launch with the icon disabled showed a blank space in the menu bar until it landed. The preference is now applied during control item setup, before any of that can render.
3. The Displays pane says what it does (#1045, #961). Displays with their own settings are marked Custom, and a note says those settings take precedence over the global template, which explains why toggling the template seemed to do nothing. Per-display item spacing now only edits the display that hosts the menu bar, because macOS keeps one spacing value for the whole system and follows it; other displays show their saved value with an explanation of when it applies.

### How automatic moves work now

The move engine was rebuilt in five steps (#999 to #1003, merged as #1041). Move gestures stay on the menu bar: the press-release guard lives inside the event sequence now, so a stalled drag is always released. Every automatic move runs under a transaction budget with a hard deadline, and a policy decides per attempt whether to retry or stop, so a stuck move can neither walk the bar nor spin without end. Layout editor cache refreshes are transactional, so a dropped refresh cannot strand a frozen editor. Automatic multi-move batches are coordinated: each move re-validates its preconditions while holding the move gate, so a user move invalidates a stale batch instead of racing it. Editor transitions are stabilized with generation-based drag state, stale-thumbnail rejection while a container is frozen, and window-based drag identity that survives Control Center identity resolution.

Earlier in the same batch (#993 to #998), move outcomes became explicit and attributable, hosted item identities are reconciled safely, persisted identity seeds are bounded, moves are serialized and preflighted, and diagnostic reports redact sensitive values before anything is written to disk.

### Dependencies & localization

- Source strings repaired, including the automatic grammar agreement that two of them had lost (#1036).
- Crowdin sync for `Localizable.xcstrings` (#1030, #1037). Russian is the big mover, from 69.3% of the catalogue to 82.6%.
- More Crowdin sync (#1040): new Russian and Japanese translations, improved Thai plural formatting, and Russian plural forms for several messages.
- The build and release workflows run on macOS 27 runners (#1034).
- Copyright headers updated across the project (#1026).
- Two triple-nested closures unnested, which clears both open SonarCloud maintainability issues.

## [2.1.0-beta.1] - 2026-09-03

Hey, we have a Discord! Come say hi: [discord.gg/KDfWjWDnR4](https://discord.gg/KDfWjWDnR4).

First beta of the 2.1.0 line. This is the wave the 2.0.0 notes pointed at: triggers, groups, zen mode, Simple Mode, spacers, and a Thaw Bar that dresses itself. Anything that changes behavior ships switched off; flip it on when you want it.

---

### Upgrade from 2.0.1

1. Pick the beta channel in Settings → Updates. Stable stays on 2.0.1 until 2.1.0 leaves beta.
2. No schema or `defaults` changes. Profiles, saved layouts, and hotkeys carry over untouched.
3. Trigger conditions are gated per feature under Settings → Developer. Battery and power work out of the box; everything else is a switch you flip deliberately.

---

### New

- Item triggers move a menu bar item when something happens: battery level, power source, frontmost or running app, network, VPN, Wi-Fi, Bluetooth, audio device, displays, a time window, a Focus, a place, Energy Mode, thermal pressure, camera or mic use, a script's exit, or another icon changing. Conditions combine with all/any/none, actions invert, and a wrong verdict costs a brief reveal instead of a rearranged bar. Designed and implemented by @alvst (#735, #965).
- Item groups bundle items so they move as one, including across sections, matching the macOS 27 semantics. Same-bundle clusters group automatically and dissolve on request.
- Zen mode seals the whole bar with one hotkey. Auto-reveals and hover tricks stand down, and a blinking icon does not get to reopen what you closed. Toggle it again to hand the bar back.
- Simple Mode collapses Settings to one page, ordered by what you actually touch. Everything it hides is still there when you switch it off.
- A Tools pane gathers the destructive troubleshooting helpers in one place, plus announcements and Sparkle feed pinning.
- Spacer items create gaps on purpose: pick a width and an optional fill, then drag them like any item.
- Per-Space profiles bind a profile to a Space the way it already binds to a display. Bindings use the window server's per-Space `uuid`, since the ID is renumbered at logout. Precedence is Focus Filter, then Space, then display.
- Wallpaper changes re-tint the bar immediately. Thaw now watches the wallpaper store instead of polling for it. The poll stays for dynamic wallpapers, which change their pixels without ever rewriting that file.
- Adaptive Gradient tint builds the gradient from the wallpaper's dominant colours instead of one averaged brown. Colours are bucketed and taken most-covering first, skipping any too close to one already taken.
- Items that ask for attention can surface themselves. A blinking status icon briefly shows the section holding it. A blink is told apart from a clock or a battery percentage by whether the icon keeps returning to a state it already showed. Off by default under Advanced.
- A Thaw Bar of its own: shape, tint, and border for the bar, independent of the menu bar it mirrors (#248, thanks @kn666).
- Hidden icons that refresh at the slider rate. Captures run through a recyclable XPC helper, so the per-call dictionary leak stays out of the app (#942, thanks @CamilleGuillory).
- One Per display section: the repeated per-display blocks collapse into a single picker-driven section.
- A standalone layout editor opens on its own, with per-Space appearance overrides and last-pane restore; items can be activated straight from the editor (#985, thanks @alvst).
- App icons where captures can't go. Items nobody can capture draw their owning app's icon, so the Thaw Bar, the layout pane, and Search work with Accessibility alone.
- A hotkey for automatic rehiding (#665, thanks @nightah).
- Diagnostic logs that rotate by size and time (#974) and diagnostics rows you can edit (#976), both by @nk-tedo-001.

---

### Fixed

- A profile apply no longer walks the visible section into the hidden one (#1027, thanks @nk-tedo-001). On a three-display Mac after a restart, the reporter's bar went from twelve visible items to one in six seconds. The hidden divider was parked off-screen with two visible-bound items already stranded behind it, and Phase 1 had just declined to rescue them. A parked divider cannot be dragged onto (#899), so it hands off to the per-item pass. That pass then anchored its moves on the stranded items. A drop point derives from its anchor's leading edge, so each move pressed at a point off the display, AppKit dropped the item beside the parked anchor, and the next move anchored on the item just stranded: six desired-visible items followed each other out of the bar. Moves bound for the visible section now require an anchor that is actually on screen, and skip when it is not. Moves into the hidden and always-hidden sections are untouched: parking is how concealment works, and gating those would refuse every move into a collapsed section. A skipped move counts as unenacted, so the arrangement is not written back to the saved order as though it had been achieved.
- Control Center modules no longer persist under another app's name, and profiles that already carry one heal on load (#1027). The reporter's `main.json` held `com.techsmith.snagit.capturehelper:Battery`. On a three-display setup, the source-PID resolution matched Control Center's Battery window to Snagit's helper process, the resolved PID became the identifier's namespace, and the wrong spelling persisted. The live item reads `com.apple.controlcenter:Battery`, so it never matched the saved entry again: every apply planned Battery as an unmanaged arrival into the hidden section, and the reporter could not reorder it. No existing guard catches this. The PID did resolve, so the identity is not provisional. The title is not a generic slot, so the item is not transient. And one wrong PID is not a majority, so the #784 gate stayed quiet as designed. What does identify the item is the title: only Control Center names an item "Battery", "WiFi", or "FocusModes". Those titles under any other namespace are now treated as misattributed. The persistence path excludes them the way it excludes an unresolved item, and the load-time prune drops the ghost from saved orders and profiles outright, since the title alone is proof enough and no live twin is needed to confirm it; the module then re-persists under its real name on the next cycle that resolves it properly. The cost of a wrong verdict is small: an app that genuinely titles its item "Battery" or "Clock" keeps its movability and only loses its persisted position. Generic `Item-N` slots are never touched, since a third-party app's own slot is indistinguishable from a misattributed one by title alone.
- A bulk apply no longer dispatches while the section dividers sit out of order (#1027). In the same log, both of the reporter's other control items were classified into the hidden section before any apply ran. The dividers were scattered rather than collapsed onto one coordinate, so the zero-width gate from #868 passed while every section assignment derived from that reading was wrong. Both apply paths, the saved-order dispatch and the profile pass's fresh re-read, now refuse a reading that places the visible control item or the always-hidden divider outside its own section. The refusal also attempts recovery: it un-parks a stranded hidden divider and re-seats the visible chevron, so a scrambled bar returns to a state the gate accepts instead of staying stuck. A divider that is absent still passes. A disabled always-hidden section has no divider by design, and a missing divider is what the #849 gate already handles.

---

### Dependencies

- `swift-system` is declared directly; Collections and AsyncChannel joined the lockfile. The last XCTest suites moved to Swift Testing.

## [2.0.1] - 2026-09-02

Help us translate Thaw at [crowdin.com/project/thaw](https://crowdin.com/project/thaw).

Please report issues at [github.com/thaw-app/Thaw/issues](https://github.com/thaw-app/Thaw/issues).

Five fixes from field reports against 2.0.0, nothing new. The one most people will notice: option-click and double-click on the menu bar toggled the always-hidden section in every 1.x build, and both went dead the moment you upgraded to 2.x (#1012). The largest under the hood: after a restart, the menu bar could sit wherever macOS had dropped the items, and re-applying the profile in Settings refused to run at all (#991). The rest: item previews work again in the layout editor on mixed Retina and non-Retina setups (#990), a drag into an empty collapsed section completes instead of deadlocking or timing out (#988, #1010), and the menu bar appearance follows space switches on multi-display systems, including the macOS 26 setups where the per-display space query stops answering (#794). Two release candidates carried the work; their entries below keep the per-fix detail.

---

### Upgrade from 2.0.0

1. Update in place through Sparkle.
2. If you came from 1.x and never touched the two click-gesture toggles in Settings, General, both come up on after this update, the way they behaved in 1.x. Turn either one off there and Thaw keeps that choice. Anyone who already set them explicitly, on or off, is left alone.
3. No schema or `defaults` changes. Profiles and saved layouts carry over untouched.

---

### Fixed

1. The 1.x click gestures survive the upgrade to 2.x (#1012). Option- click and double-click on the menu bar toggled the always-hidden section unconditionally in 1.x. 2.0 turned both into opt-in settings that default to off, and the keys behind them did not exist for anyone upgrading, so both gestures silently stopped working with no setting visibly changed. Both now come up on when they have never been explicitly set, and an explicit choice, including off, is never overwritten. Separately, the control items' phantom-click suppression sat in front of the whole event switch and swallowed right-click along with it, so the context menu was unreachable whenever the menu bar transiently had no item windows on the active space. That guard is now scoped to the left mouse-down it was written for.
2. Profile applies survive a missing always-hidden divider (#991). After a restart the divider rests parked offscreen, and on macOS 26 that parked window intermittently drops out of the item list Thaw enumerates. Lookup then returned nil for the divider while downstream steps still treated the pair as fully resolved: applies skipped wholesale ("always-hidden divider unresolved while its section is enabled") or abandoned after the hidden-boundary moves had already run ("control items degraded before moving AH_ctrl" in the attached log, four milliseconds after a clean tag resolution). The reporter's bar never matched the saved profile, and manual re-applies failed the same way. The control-item pair now recovers the divider from its own window record, the authoritative channel the hidden divider has had since #754, and refuses to adopt a lookalike window from a duplicate Thaw instance. A divider the window server no longer knows is still refused, now under an accurate message instead of "control items degraded".
3. Layout editor previews render on mixed-scale display setups (#990). Composite captures compared pixel width against bounds times the display scale and rejected any mismatch, but on a 1.0x external beside a Retina display the capture backend picks its own scale: the log recorded 70 rejections, an empty image cache, and gray placeholders for every item. Both composite paths now derive the scale from the capture itself, the same check single-item captures have used since #851, and degenerate zero-width windows are filtered from the bounds union so one orphaned window cannot reject a whole batch.
4. A drag into an empty collapsed section completes instead of refusing forever (#988, #1010). The #923 guard refuses an editor drag whose destination divider is parked offscreen and suggests opening the section first; with every item in always-hidden there was nothing to open and nowhere to drop, which is exactly the reporter's bar. Thaw now reveals the empty destination, retargets the drag onto the freshly revealed divider, and re-conceals the section once the item settles. The first cut of that reveal expanded only the destination section, and the always-hidden divider parks to the left of the hidden section's content: with the hidden section collapsed behind its 10000-point spacer, the revealed divider was re-placed just left of that still-parked content and never came onscreen, so the drag still timed out into the same refusal. The reveal now expands the hidden section alongside the always-hidden section and restores both once the item settles. If the divider does not return within two seconds the old refusal stands. A drag cancelled mid-reveal, or one the move watchdog gives up on, restores the sections' previous state instead of leaving them showing. Disabled sections never reveal.
5. Overlay panels stay on the space you are looking at (#794). A panel kept whatever space was current when it was last shown; with "displays have separate spaces" enabled, every ctrl-arrow switch revealed a vanilla menu bar on both displays, and the tint, shape, and background appeared only on the space that was current at launch. Panels now check per display whether they sit on that display's current space and re-home only when actually stranded. Because the check compares each panel against its own display, the fullscreen drift that forced the old flag's removal cannot return. A re-check shortly after each switch re-shows a panel that a raced space read leaves behind, so the old 60-second housekeeping timer stays a backstop rather than the recovery path. On the macOS 26 setups behind the reports that stayed open after that first cut, the per-display space query stops answering, and the code read the silence as "the overlay panel is already in place", so the tint, shape, and background stayed stuck on the launch space for every recovery path. The panel on the display that owns the active menu bar now falls back to the global active space, which coincides with that display's current space by definition. The decision logs its inputs, so any report that survives this can be pinned to a branch.

---

### Dependencies & localization

- Crowdin sync for `Localizable.xcstrings` (#992, #1019, #1021).
- github-actions group bumped with four updates (#1011), and `softprops/action-gh-release` bumped on its own (#1018).

## [2.0.1-rc.2] - 2026-09-01

Please report issues at [github.com/thaw-app/Thaw/issues](https://github.com/thaw-app/Thaw/issues).

Three fixes from rc.1 field reports, nothing new. The one most people will notice: option-click and double-click on the menu bar toggled the always-hidden section in every 1.x build, and both went dead the moment you upgraded to 2.x. The other two are narrower. A drag into an empty always-hidden section still timed out when the hidden section happened to be collapsed as well, and the space-switch re-homing that landed in rc.1 did nothing at all on the macOS 26 setups where the per-display space query stops answering.

---

### Upgrade from 2.0.1-rc.1

1. Update in place through Sparkle.
2. If you came from 1.x and never touched the two click-gesture toggles in Settings, General, both come up on after this update, the way they behaved in 1.x. Turn either one off there and Thaw keeps that choice. Anyone who already set them explicitly, on or off, is left alone.
3. No schema or `defaults` changes. Profiles and saved layouts carry over untouched.

---

### Fixed

1. The 1.x click gestures survive the upgrade to 2.x (#1012). Option-click and double-click on the menu bar toggled the always-hidden section unconditionally in 1.x. 2.0 turned both into opt-in settings that default to off, and the keys behind them did not exist for anyone upgrading, so both gestures silently stopped working with no setting visibly changed. Both now come up on when they have never been explicitly set, and an explicit choice, including off, is never overwritten. Separately, the control items' phantom-click suppression sat in front of the whole event switch and swallowed right-click along with it, so the context menu was unreachable whenever the menu bar transiently had no item windows on the active space. That guard is now scoped to the left mouse-down it was written for.
2. A drag into an empty, collapsed always-hidden section completes even when the hidden section is collapsed too (#1010). The reveal added in #988 expanded only the destination section, but the always-hidden divider parks to the left of the hidden section's content: with the hidden section collapsed behind its 10000-point spacer, the revealed divider was re-placed just left of that still-parked content and never came onscreen. Every such drag timed out into the "open the section first" refusal, advice that could not help, since only expanding the hidden section puts the always-hidden boundary onscreen. The reveal now expands the hidden section alongside the always-hidden section and restores both once the item settles.
3. Menu bar appearance re-homes after a space switch even where the per-display space query goes quiet (#794). On the macOS 26 setups behind the reports still open against rc.1, that query stops answering, and the old code read the silence as "the overlay panel is already in place", so the tint, shape, and background stayed stuck on the launch space for every recovery path. The panel on the display that owns the active menu bar now falls back to the global active space, which coincides with that display's current space by definition. The decision logs its inputs, so any report that survives this can be pinned to a branch.

---

### Dependencies & localization

- Crowdin sync for `Localizable.xcstrings` (#992).
- github-actions group bumped with four updates (#1011).

## [2.0.1-rc.1] - 2026-08-31

Please report issues at [github.com/thaw-app/Thaw/issues](https://github.com/thaw-app/Thaw/issues).

Four fixes from field reports, nothing new. The largest: after a restart, the menu bar could sit wherever macOS had dropped the items, and re-applying the profile in Settings refused to run at all (#991). The always-hidden divider's window had dropped out of the item list while parked offscreen, so every layout apply that needed it either skipped itself or quit partway through. Thaw now recovers that divider from its own window record instead of searching the list. The rest: item previews work again in the layout editor on mixed Retina and non-Retina setups (#990), a drag into an empty collapsed section completes instead of deadlocking (#988), and overlay panels follow space switches on multi-display systems (#794).

---

### Upgrade from 2.0.0

1. Update in place through Sparkle.
2. No settings, schema, or `defaults` changes in this release. Profiles and saved layouts carry over untouched.

---

### Fixed

1. Profile applies survive a missing always-hidden divider (#991). After a restart the divider rests parked offscreen, and on macOS 26 that parked window intermittently drops out of the item list Thaw enumerates. Lookup then returned nil for the divider while downstream steps still treated the pair as fully resolved: applies skipped wholesale ("always-hidden divider unresolved while its section is enabled") or abandoned after the hidden-boundary moves had already run ("control items degraded before moving AH_ctrl" in the attached log, four milliseconds after a clean tag resolution). The reporter's bar never matched the saved profile, and manual re-applies failed the same way. The control-item pair now recovers the divider from its own window record, the authoritative channel the hidden divider has had since #754, and refuses to adopt a lookalike window from a duplicate Thaw instance. A divider the window server no longer knows is still refused, now under an accurate message instead of "control items degraded".
2. Layout editor previews render on mixed-scale display setups (#990). Composite captures compared pixel width against bounds times the display scale and rejected any mismatch, but on a 1.0x external beside a Retina display the capture backend picks its own scale: the log recorded 70 rejections, an empty image cache, and gray placeholders for every item. Both composite paths now derive the scale from the capture itself, the same check single-item captures have used since #851, and degenerate zero-width windows are filtered from the bounds union so one orphaned window cannot reject a whole batch.
3. A drag into an empty collapsed section completes instead of refusing forever (#988). The #923 guard refuses an editor drag whose destination divider is parked offscreen and suggests opening the section first; with every item in always-hidden there was nothing to open and nowhere to drop, which is exactly the reporter's bar. Thaw now reveals the empty destination, retargets the drag onto the freshly revealed divider, and re-conceals the section once the item settles. If the divider does not return within two seconds the old refusal stands. A drag cancelled mid-reveal, or one the move watchdog gives up on, restores the section's previous state instead of leaving it showing. Disabled sections never reveal.
4. Overlay panels stay on the space you are looking at (#794). A panel kept whatever space was current when it was last shown; with "displays have separate spaces" enabled, every ctrl-arrow switch revealed a vanilla menu bar on both displays, and the tint, shape, and background appeared only on the space that was current at launch. Panels now check per display whether they sit on that display's current space and re-home only when actually stranded. Because the check compares each panel against its own display, the fullscreen drift that forced the old flag's removal cannot return. A re-check shortly after each switch re-shows a panel that a raced space read leaves behind, so the old 60-second housekeeping timer stays a backstop rather than the recovery path.

## [2.0.0] - 2026-08-30

Please report issues at [github.com/thaw-app/Thaw/issues](https://github.com/thaw-app/Thaw/issues).

Hey everyone. Thaw 2.0 rebuilds the app around macOS 26 (Tahoe): Liquid Glass throughout, a redesigned settings surface, an automation layer built on `thaw://`, and a menu bar pipeline rewritten around item identity, layout persistence, and knowing when to leave the bar alone. The cycle ran twenty-two releases: `1.3.0-beta.1` shipped Settings Profiles in April, fifteen betas followed, and six release candidates carried the work home. Nearly everything after beta.15 came out of field logs, real menu bars misbehaving in ways no test caught. This entry walks the run by theme. The detailed per-fix notes live in the RC entries in the [full changelog](https://github.com/thaw-app/Thaw/blob/development/CHANGELOG.md).

---

### Upgrade notes

1. **From 1.x:** Thaw 2.0 requires macOS 26. On macOS 14 or 15 you stay on
   `1.3.0-beta.1` (#427).
2. **From any 2.0 RC:** in-place Sparkle update. Failure-ledger marks clear
   on build change, and an explicit `defaults write` override still beats
   any shipped default.
3. **Per-display spacing:** the schema changed during the beta cycle; older
   profiles fall back to the active display's value rather than failing to
   load.
4. **Update feed:** new installs use `thaw-app/updates`; existing installs
   on the legacy stonerl feed keep receiving the mirrored appcast.

Known issues carried from the RCs are listed at the end of each RC entry in
the [full changelog](https://github.com/thaw-app/Thaw/blob/development/CHANGELOG.md).

### What's next

**2.1.0 is on its way to the beta channel.** It adds:

- Item groups that stay together and move as one unit.
- Item triggers that run scripts and react to Focus, a geofence, camera or mic use, or a script's own result (#735, #965).
- Zen mode, per-Space profiles, and per-Space appearance overrides (#958,
  #960).
- [Simple Mode](https://github.com/orgs/thaw-app/discussions/550), a Tools pane, spacer items you create yourself, and a standalone layout editor.
- A hotkey for automatic rehiding (#665), a Thaw Bar with its own shape and tint, and one Per display section in place of the repeated blocks.
- Hidden icons that refresh at the slider rate (#942) and diagnostic logs that rotate by size and time (#974).

Screen Recording also becomes optional in practice. Items with no capture draw their owning app's icon, so the Thaw Bar, the menu bar layout pane, and Search work with Accessibility alone instead of refusing to draw.

**Thaw 3.0.0 brings macOS 27 support**, on the nightly / alpha channel, which
you can select once you are on macOS 27. Thaw 3.0 is a rebuilt menu bar core. It adds:

- A quick-edit panel you summon with a hotkey.
- Hover spotlighting, so a search result lights up the item in the bar itself.
- A panel that descends from the notch with media transport.
- Control Center widgets, App Intents for Shortcuts, and `thawctl` as a headless
  CLI.

**Full Changelog**: https://github.com/thaw-app/Thaw/compare/1.3.0-beta.1...2.0.0

<p align="center">
  <a href="https://www.raycast.com/diazdesandi/thaw"><img alt="Works with Raycast" src="https://raw.githubusercontent.com/thaw-app/brand-assets/main/badges/works-with-raycast.svg" height="36" /></a>
  <a href="https://getdroppy.app/"><img alt="Works with Droppy" src="https://raw.githubusercontent.com/thaw-app/brand-assets/main/badges/works-with-droppy.svg" height="36" /></a>
</p>

---

### New

#### Built for macOS 26

- Native Tahoe support with the Liquid Glass design system across the main app, Settings, Search, and onboarding, including the glass tour for first launch.
- New macOS 26-style app icon designed and delivered by @JamesLautner (issue #5), with the clear-mode display refinement reported by @a35hie (#616).
- The minimum deployment target is now macOS 26. Systems on macOS 14 or 15 stay on the 1.x line (#427).

#### Profiles & Focus

The feature that started the cycle, from `1.3.0-beta.1`, implemented by @nightah:

- Save your entire Thaw configuration as a profile and switch instantly: create, duplicate, rename, and delete profiles; import and export them for backup or sharing; update an existing profile with the current layout, configuration, or both.
- Display Auto-Switch applies a display's assigned profile when you connect it.
- Focus Filter integration switches profiles as Focus modes activate and restores the previous one after.
- Profile hotkeys switch between favourites from the keyboard.
- Later in the cycle: capture previews next to the key behaviours (#887), Update All marks a profile active when its capture matches the running state (#904), applying a profile uses that profile's spacing offset (#903), snapshots became forward-compatible so new settings cannot break old files, legacy layouts import (#778, #779), and the layout cache re-arms when the active profile changes (#679).

#### Automation

- The `thaw://` scheme reads and writes settings, including doubles, enums, and per-display keys, with live UI sync.
- `thaw://authorize` triggers the permissions dialog without a settings operation, and `thaw://get?key=version` returns app version and build without whitelist auth.
- ThawCtl, a companion test app, drives the URI scheme from the command line with a `thawctl://` callback.
- Pre/post apply script hooks run globally or per profile, with configurable timeouts, environment variables such as `THAW_PROFILE_NAME`, non-blocking failures, and their own Automation pane.
- Per-item global hotkeys open any menu bar item's menu, across all sections; Electron and Chromium items go through an AX press, and bindings persist in profiles (#148).
- A version copy button in About puts the build identifier on the clipboard.

#### Menu bar appearance

- Configurable background and shape tint: none, solid, or gradient with light/dark variants, a Regular/Clear glass picker backed by `NSGlassEffectView`, borders, shadows, and opacity sliders. Tints render behind menu bar items at user-chosen opacity.
- Adaptive modes sample the wallpaper color behind the bar per display, cache colors before sleep, restore them on wake without a white flash, and stagger recapture for slow external displays until the color settles.
- The `.notch` shape kind splits the background at the physical notch, with a margin slider (0 to 15 px) and four-corner end-cap control; it behaves as full width on displays without a notch.
- Per-display menu bar spacing applies dynamically, preserves settings for disconnected displays, skips the full relaunch when only resolution changed (#551), warns before spacing relaunches with the choice saved per profile (#691), prompts before first apply, and falls back to a global template.

#### Thaw Bar & IceBar

- Horizontal, vertical, and grid layouts, left/right alignment options, panel resizing that follows its content, pill shapes that match the container, and grid columns with per-column max widths.
- Independent shape and border settings for the overlay versus Thaw Bar (#248), plus a per-display option to route only the always-hidden section to Thaw Bar (#751).
- Item reveal survives CPU load, a grace period stops the "no items" flash on display changes, and the live window ID is re-checked after sleep.
- Icon foreground colors adapt to each screen's menu bar background, including notched MacBooks and secondary displays.

---

### Reliability

#### Item identity & restoration

- Section restoration follows one deterministic path (baseIdentifier match to saved order, else macOS placement), replacing the namespace fallbacks that pulled unsaved items visible on restart. Blocked items are skipped instead of forced, and placed items stop drifting back into the new-items section.
- Startup settling waits on source-PID resolution rather than timers, auto-relocation is suppressed while settling runs, and stale PID resolution can no longer mis-namespace items after cmd-drag moves.
- A serialized cache gate prevents concurrent rebuild races, and lightweight 60-second polling catches late-registering items from background-only apps that never become frontmost.
- The item cache re-checks after every app launch so late arrivals sort into place, confirms stability across two reads, and keeps `displayID` handling off the main thread.
- LayoutReconciler consolidates the scattered icon-restore paths into one phase-based orchestrator with deferred post-apply refreshes and chevron position persistence.
- Menu bar height queries lost the `-1` sentinel that poisoned the height cache, and item bounds verify against the window server so temporary system items (recording indicators, mic, camera) leave no stale ghosts.

#### Control Center-hosted items

- MarkerPairResolver identifies proxies hosted by Control Center (Little Snitch among them) through width-matched marker windows.
- On single-display Macs a headless virtual display forces marker windows to publish, resolving those widgets to their real owners (#643). The phantom display was later hardened to 640×480 off-main, held briefly, with a one-strike blacklist (#661), and it never appears in Thaw's own display enumeration. Orphans stay put and are never relocated.
- Title-offset items (AirBuddy, SpamSieve, Cotypist) resolve by corroborated title with a width backstop, system status-item clones are excluded regardless of namespace (#662), and generic slots stay unresolved for the marker pass rather than guessing (#690).

#### Notch overflow

- Items that would hide behind the notch on MacBook displays are managed instead of lost, ejected to Thaw Bar (since `1.3.0-beta.1`).
- Overflow budgeting stopped double-counting spacing that ejected correctly-placed profile items at default settings, runs only against settled geometry (#681), and keeps the visible control item in place during ejection.

#### Interaction & everyday fixes

- Clicking File, Edit, View no longer trips show-on-click, hover, or scroll behaviours; event monitors health-check and recover themselves instead of dying until relaunch.
- Synthetic clicks keep out of Hot Corners and Show Desktop, restore the cursor reliably, and rehide logic stops stuck items saturating rehide or spinning popup detection.
- The always-hidden section answers option-click, double-click on the Thaw icon (configurable), and ctrl/option clicks on empty space; transient Live Activities and Game Mode agents are excluded from search, moves, and profile budgets.
- Right-click context menus work on secondary displays, quit lives in the secondary menu with ⌥-hold switching it to Restart Thaw, and a localized Support menu item links help resources.
- The search panel keeps its text between openings if asked, regains focus from the hotkey, and lets sections reorder and filter; layout-bar drags land across sections cleanly without false move alerts.
- Settings gained sidebar auto-fit, freed window sizing, per-pane polish, hidden dependent toggles when a section is disabled, and an option to disable icon refresh entirely (0 FPS).

The headline of the RC cycle was reliability: deterministic ordering with stable identities replaced the drift that let saved layouts scramble, reorder storms are bounded instead of endless, persist gates stop transient states from being written as user intent, and control-item pairing, notch overflow budgeting, scan cost, name memory, and divider recovery were rebuilt from field logs. Cold-start restore works, the 47 GiB memory growth is gone, hidden previews render, and the bar stops repairing itself into collapse. Details live in the RC entries in the [full changelog](https://github.com/thaw-app/Thaw/blob/development/CHANGELOG.md).

---

### Platform

#### Performance, memory & engineering

- Swift strict concurrency landed in beta.3 and deepened to Swift 6.2 with MainActor default isolation on the app target; locks migrated to `OSAllocatedUnfairLock`.
- ScreenCaptureKit replaced the SkyLight capture paths that leaked; the XPC item service answers one batch request instead of 40 to 64 concurrent per-window calls, which ended the jetsam kills; wallpaper capture went away entirely.
- The image cache got an LRU/concurrency overhaul with lossless disk keys, retain cycles in live refresh were closed, duplicate entries after reconnect removed, and caches rebuild on display connect/disconnect.
- Icon refresh normalized onto one grid: off, or `1/n` seconds for integer n in 1…30.

#### Distribution, security & localization

- Sparkle payloads publish to `thaw-app/updates`, mirrored to the legacy stonerl Pages feed; DMGs are built with a background image, signed, notarized, and carry SLSA Build L3 provenance.
- OSV dependency scanning gates releases, CodeQL analysis runs in CI, SonarCloud findings were cleared, explicit Xcode versions pin reproducible builds, and the project holds OpenSSF Best Practices Gold.
- Crowdin-driven localization with plural-aware strings and separated copy strings for cleaner translation; the tour ships complete in Spanish.

---

### Contributors

Thaw 2.0.0 was built by Toni Förster (@stonerl), René Jiménez (@diazdesandi), and Amir Zarrinkafsh (@nightah), with contributions, reports, diagnostics, translations, and patient testing from:

@aliaskar-rockeater · @alvst · @andredlng · @auspic7 · @beantownbytes · @billchirico · @bpresles · @brucemakes012 · @bytepl · @CamilleGuillory · @cbguder · @danielhopkins · @davidnichols-ops · @Daventure91 · @eli-yip · @exsesx · @gitmichaelqiu · @howardhey · @hxu · @JamesLautner · @jamesyc · @Jizzy015 · @kn666 · @kylewhirl · @lathe-agent-oa · @looseboy · @lucifercraig12345-create · @MashnoorKek · @nk-tedo-001 · @SAY-5 · @ShiroKSH · @Skyearn · @slatlasdev · @stu-carter · @subway-jack · @t4sh · @TheBenMeadows · @VailElla · @volcbs · @warmup72 · @wizaard88 · @yoodu · @YuriNachos · @ZeterMordio · @Zophiekat

and every translator working through Crowdin.

Thank you. This release would not exist without you.

---

### Support

If you find Thaw useful and want to support its development:

- GitHub Sponsors: https://github.com/sponsors/stonerl
- Ko-fi: https://ko-fi.com/stonerl
- Patreon: https://www.patreon.com/c/stonerl
- PayPal: https://www.paypal.me/tonifoerster

## [2.0.0-unreleased]

_Fixes made after 2.0.0-rc.5. Never tagged on their own; they ship inside
the 2.0.0 stable build, so they are not repeated in its release notes._

### Changed

- The update channel picker in Settings › About offers Stable, Beta, and
  Alpha instead of Stable and Development. The old "Development" setting
  subscribed to alpha and beta together, so there was no way to take
  release candidates without also taking the rewrite. Beta continues to
  mean release candidates of this app and still receives stable releases
  alongside them. Alpha is a parallel track carrying the rewritten app
  built against a new macOS, and it no longer drags the release candidates
  along with it. Alpha appears in the picker only on the macOS the
  rewrite targets, sharing its threshold with the startup compatibility
  warning that points users at it. Existing "Development" subscribers
  migrate to Beta, not Alpha.

### Fixed

- A hidden section that collapsed to zero width no longer stays collapsed.
  The divider recovery could not reach the state it repairs: it ran only
  when an apply reported a boundary mismatch, but the applies that mattered
  refused before computing one, and a divider can strand while the
  visible/hidden boundary reads consistent. A refused apply now counts as
  evidence, the streak that arms the rebuild survives a clean cycle, and
  the parked test reads both edges so a healthy collapsed section is never
  mistaken for a stranded one (#978).
- A relaunch clears a stranded divider again. macOS had autosaved the
  hidden divider to the left of the always-hidden one, and "keeping its
  stored position" during a rebuild restored the value that stranded it, so
  the app came back up already broken. An inverted stored position is now
  replaced with one that orders the two chevrons correctly (#978).
- Thaw no longer places the always-hidden divider beside an anchor that is
  itself parked offscreen. The drop point derives from the anchor's leading
  edge, so anchoring on a parked item dragged both further out. That is the path
  behind the mass hidden-to-always-hidden re-sectioning users reported, and
  behind a stranded divider acquiring a second fault (#978, #980).
- A profile no longer commits its saved section order when the apply that
  produced it left planned moves unenacted, so a partial arrangement cannot
  become the saved one (#978, #980).
- Dragging an item between sections in the layout editor now survives a
  restart. The move was recorded after placement had settled, by which
  point the save had already been skipped as being inside the post-move
  cooldown; the restore then read the drag as drift and reverted it (#983).
- Dragging an item onto a collapsed section in the layout editor is now
  refused with an alert naming the section, instead of spending eight
  attempts dragging the item offscreen and reporting a generic failure. A
  collapsed section's divider expands into an offscreen spacer, so the drop
  point sat thousands of points off the display (#923).
- An item's placeholder in the layout editor picks up its app's icon once
  the app becomes launchable, instead of keeping the generic symbol for the
  life of the view. The re-resolved icon is now also drawn in the same pass
  rather than waiting on an unrelated redraw (#981).
- The alert shown when a drag lands on a collapsed section's parked divider
  read "The hidden section section is collapsed"; it also had no entry in
  the string catalog, so it stayed English in localized builds.

## [2.0.0-rc.5] - 2026-08-25

Please report issues at
[github.com/thaw-app/Thaw/issues](https://github.com/thaw-app/Thaw/issues).

Planned as the last release candidate before 2.0 stable. Almost all of it comes from field logs, and the reports fall into two clusters: layout repair that damaged the arrangement it was trying to fix (#958, #863), and scans that re-probed every running application until the machine stuttered and every item answered to "Menu Bar Item" (#956).

---

### Upgrade from 2.0.0-rc.4

1. Update in place through Sparkle.
2. Move budgets now default to 250 ms, or 350 for Bento Boxes. An explicit
   `defaults write` override still takes precedence over either value.

---

### Fixed

1. Hidden-divider recovery no longer collapses the bar. Both recovery paths discarded a stale autosave position by writing the fresh-install seed through the route that bypasses the guard, so the divider landed back beside the visible chevron and the next save persisted the collapsed span. On the five-hour log attached to #958, a routine notch overflow scored one boundary mismatch, the rebuild fired, and three seconds later the visible section held nothing but Thaw's own icon.
2. Boundary repair moves items instead of dragging the divider across them. Phase 1 reached for one drag of H_ctrl whenever any managed item sat on the wrong side of it; when that drag would have crossed the entire visible section, the bar collapsed to a 33-point span and the apply still reported a clean classification afterwards. Small mismatches now walk the offending items back one drag each, and the divider drag stays reserved for the empty-side cases it was built for (#879, #958).
3. Ejected items stop bouncing between the overflow planner and the repair pass. On bars persistently over the notch budget, every apply ejected the same item and then recalled it as wrongly concealed, two synthetic drags per cycle for as long as the bar stayed over budget. That matches the "icons jumping randomly and relocating between layouts" reports. Ejected items are now exempt from the boundary tally until the budget frees up (#958).
4. Items keep their names while source-PID resolution catches up. Naming requires knowing which process created an item, and the first cache pass deliberately runs without waiting for the accessibility scan, so for its duration every item answered to the generic "Menu Bar Item" on hover and in Search. An item now falls back to the name it resolved to last time. Control Center's generic Item-N slots are refused because their key encodes hosting order rather than identity and a wrong name gets clicked; custom names still take precedence (#956).
5. Slow item owners get room to answer. The move budget started at 100 ms, but escalation averaged each raise against the standing value, so even eight attempts reached only 476 ms, and every unresponsive-owner failure was filed twice, burning through the ledger's mark threshold right away. Defaults are now 250 ms (350 for Bento Boxes), growth is adopted as computed up to a one-second ceiling, failures are filed once, and marking takes three. Fixes the cursor hijack of #687 and the misplaced relaunched items of #960.

---

### Source-PID scanning

- The negative-cache flag was cleared for every reused app on every cache cleanup, and cleanup runs whenever any process starts or exits because `NSWorkspace.runningApplications` drives it; the #956 log shows 46 cleanups in seven minutes. The flag is now a deadline that survives cleanup and backs off as consecutive empty checks accumulate. Early rungs stay inside the startup window, so an application that publishes its status item shortly after launch is still found quickly.
- Consecutive-miss counts are remembered per bundle identifier across launches and seed the first scan of a session, which measured 3.85 s in the log. Seeding decides where to look, never what was found: skipping an application can reorder work but cannot attribute an item to the wrong owner.
- A zero-area window no longer selects scan drivers. An unresolved window is what picks the driver, and one zero-area window started eight of nine scans in seven minutes with nothing else on the bar asking for one. Bounds are re-read on every request, so a window that gains area stops being skipped.
- Scan summaries now log total wall time and name any single app whose extras-bar probe exceeds 50 ms, since accessibility reads are serviced by the target process and bounded only by its unresponsive timeout.

### Save gates

- `saveSectionOrder` honours the same five-second post-move cooldown as `applySavedLayout`, except when the user's own move was the most recent one, so a Layout-editor drag cannot undo itself. In the #958 log the save landed one millisecond after the restore stood down.
- The multi-display gate counted visible items, so a relocation that stranded items in the wrong section erased its own evidence: it fired correctly with sixteen visible items and passed when four were left, which was the save that did the damage. It now reads whether the menu bar changed display since the cache cycle being compared, a signal that never looks at the items and therefore survives misclassification.

### Divider recovery

- A hidden-divider rebuild stamps a seed position only when the bar holds no managed items. Discarding the stale `NSStatusItem` still gives the divider a window on the current bar, and the follow-up apply walks it to the saved boundary (#958).
- The H_ctrl boundary move no longer anchors on Thaw's own chevron. When every profile item has been dragged to the other side, anchoring on the last remaining candidate dragged H_ctrl past it and concealed it; returning nil leaves the boundary alone and hands the work to the per-item LCS pass, which has barred Thaw's own items as anchors since #924. The two nil cases log separately (#958).
- Parked dividers are measured at their leading edge instead of their centre. A collapsed hidden divider is 5000 points wide, so its centre sat 2500 points to the right and read as on-screen on multi-display arrangements, defeating both the parked-divider drag guard (#899) and the rebuild detector; five hours of log recorded neither warning.
- Chevron relocation and always-hidden control-item ordering skip when the hidden divider fails the on-screen check, so neither drops its target into the parked zone beside a physically parked divider. Existing recovery paths already handle the states these guards refuse.
- An enabled always-hidden section whose divider stops resolving gets its status item recreated once per episode, after three authoritative cycles with no reading, and keeps its stored position rather than seeding. Provisional AX-frame correlations never advance, reset, or re-arm the streak. The #863 re-plug log showed `alwaysHidden=nil` on every cycle for 12+ hours while the whole always-hidden section drained into Visible (#863).
- The one-pixel drop-point bias now applies to every control-item divider regardless of width. Expanded dividers thousands of points wide still produced placements landing one point into the wrong section: a divider's width provides visual concealment, not hit-test slack (#923).

### Appearance & capture

- Preview batches exclude degenerate zero-width windows from the bounds union. Capture APIs dropped them from the composite while including them in the union, which dragged the geometry across the gap between displays, mismatched the widths, and discarded the whole batch. The windows behind this were Control Center-hosted slots orphaned by an earlier Thaw process: Control Center owns them, they outlive restarts, and their bundle-ID names keep them out of `ControlItemPair`'s strip list (#962, thanks @alvst).

### Dependencies & docs

- Sparkle bumped in the swift group (#971); github-actions group bumped with four updates (#972).
- README OpenSSF badges switched to live shieldcn scorecard/openssf endpoints (#920); contributor image source updated; repository notice added.
- FUNDING.yml gained Ko-fi and PayPal entries.

## [2.0.0-rc.4] - 2026-08-17

Please report issues at
[github.com/thaw-app/Thaw/issues](https://github.com/thaw-app/Thaw/issues).

This release closes the field reports against rc.3, hidden items dead
for the first minute after launch, and a cache stall with no deadline at
all, and pays down the debt that made them possible: the item manager's 11,500-line file, the hand-rolled identity
matching that drifted, and a test suite that wrote into the real settings
of whoever ran it.

---

### Highlights

- Hidden items work from launch, and the cache can no longer stall for good. On a cold start the item cache froze for a full minute on unresolved identities: every Thaw Bar tooltip read "Menu Bar Item" and every click silently did nothing until the settling deadline expired (#943). In the worse interleaving the settling task deadlocked awaiting itself, past every deadline. One report had the cache rejecting every refresh for 20+ hours, with the Visible row in Settings → Layout permanently empty (#945).
- The Thaw icon stops drifting left across restarts. The stalled early apply executed a minute late with the desired order it had narrowed at launch, when only a handful of identities had resolved. Everything that resolved during the stall was re-inserted as "unmanaged" at saved indices, which changed the chevron's planned neighbors and moved it left of the leftmost item; macOS remembers the new position, so each restart ratcheted it further (#947).
- Items stop shuffling mid-session on localized systems. Saved-order ghosts namespaced by a localized app name (`Control Centre:WiFi`, minted while a bundle ID transiently read nil) counted as "real owners" and deleted their genuine `com.apple.controlcenter` twins from the saved order on every load. The live items then planned as unmanaged and were repositioned by every apply, with the cursor contested for each synthetic drag (#949).
- Spanish onboarding restored: two strings shipped as translated-but-empty, so Spanish systems rendered a blank tour slide description and a blank New Items badge hint.
- XPC session race closed: a stale cancellation handler could tear down a healthy, newer session and race the lock every other access went through.

---

### Changed

#### XPC service

- The single-window `sourcePID` request was dead wire protocol, since the batch request replaced it in production, yet its round-trip tests were the only wire-format coverage at all. The request is gone and the tests now exercise the batch case both sides actually use.

#### Internal

- `MenuBarItemManager.swift` (11,526 lines) is now a folder of per-concern files cut along its existing MARK seams, each importing only what it uses; sonar and the SwiftLint input list follow the new paths.
- Item identity matching (tag plus effective PID), the click-target refetch chain, and live-bounds reads are single-sourced helpers instead of hand-rolled copies across the manager and the IceBar, the same drift that produced #943.
- The test process points the `Defaults` facade at a scratch suite before any test runs, so no suite can write into the real `com.stonerl.Thaw` domain of whoever runs the tests. The tour-slide test that failed on Spanish-locale machines while passing on English CI is green everywhere.
- The search panel reads `AppState` from its SwiftUI environment instead of reaching through the item manager's back-pointer, which no external caller uses anymore.

### Fixed

#### Menu bar & layout

- The settling-period early apply no longer waits for settling to end while holding the serial cache gate. The wait deadlocked the pair both ways: when the launch cache cycle owned the gate, settling's early exit needed a cache cycle the held gate rejects, so it ran the full 60 s deadline with the item cache frozen on fallback tags: generic names in Thaw Bar and Search, and every click aborted with no return destination (#943). When the settling task's own poll owned the gate, the apply awaited the very task it was running on, and the deadline check inside that blocked loop could never fire, so the gate stayed held indefinitely and every later recache was rejected (#945).
- Clicking an item whose cached tag predates source-PID resolution re-maps it onto its freshly fetched counterpart by windowID, so the click survives a stale cache snapshot instead of dying in the return-destination lookup (#943).
- Because the early apply now runs the moment it is dispatched, it plans against the bar it narrowed itself to. Executed at the deadline instead, its restriction inverted: identities that resolved during the stall were no longer provisional (which excludes them) but "unmanaged" (which re-inserts them at saved indices), and the re-insertion handed the chevron a move to the far left of the bar (#947).
- Saved-order pruning no longer counts a localized display-name namespace as a real owner, and drops such a ghost when its canonical twin exists: the Control Center entry sharing its title, Thaw's own control items by their reserved titles, or a real owner claiming the same non-generic title. A display-name entry with no twin survives, since it may be the only identity a bundle-ID-less app ever got (#949).
- The namespace fallback recovers a transiently nil bundle ID through the app's bundle URL before reaching for the window's owner name, so localized ghosts stop being minted in the first place (#949).

#### XPC service

- The session cancellation handler cleared the stored session outside the lock that guarded every other access, and a handler outliving its session could clear a newer one created after it. Storage now synchronizes internally, and invalidation is identity-guarded so only the cancelled session is dropped.

#### Localization

- The Spanish descriptions for the Hotkeys & Automation tour slide and the New Items badge hint were empty strings marked translated. A catalog sweep found exactly these two; both are filled in the register the catalog already uses.

## [2.0.0-rc.3] - 2026-08-15

Please report issues at
[github.com/thaw-app/Thaw/issues](https://github.com/thaw-app/Thaw/issues).

Almost all of this release is one reliability track through the launch/move
pipeline, driven by field logs from rc.2.1: cold-start restore, move planning,
control-item pairing, and the persist gates that decide whether any of it
reaches disk. Each storm fix exposed the next failure mode in the same chain,
so they land together.

---

### Highlights

- Launch restore actually runs: the saved layout is applied at cold start instead of losing to a move cooldown that launch itself had stamped ~0.4 s earlier (#881, #900).
- Storms are bounded: a failed or parked-divider move can no longer hijack the cursor indefinitely or write a half-finished order into `savedSectionOrder`.
- Control-item pairing repaired: Thaw's visible chevron is no longer mistaken for the hidden divider, the mispair behind hidden sections reading zero width (#923, #924, #927).
- Memory leak closed: recache backoff stops the CA fence port growth reported at 47 GiB on macOS 26 (#933).
- Field repair: `Thaw --reset-layout` clears persisted order and re-seeds dividers without starting the app.

---

### New

#### Settings, profiles & onboarding

- Independent shape and border settings for the menu bar overlay and Thaw Bar (#248, thanks @kn666).
- Per-display option to route only the always-hidden section to Thaw Bar (#751, thanks @MashnoorKek).
- Optional Advanced toggle moves the pointer onto a revealed search result, off by default (#769, thanks @brucemakes012).
- New CLI: `Thaw --reset-layout` clears persisted order, pinning, and relocation bookkeeping and re-seeds divider positions without starting the app. It and the settings reset both clear the stale-identifier ledger.

### Changed

#### Cold start and settling

- Launch restore bypasses the saved-layout and move cooldowns that launch itself stamped. `applySavedLayout` had been rejected on every launch by the cooldown its own chain created when it moved our control item (#881).
- Early apply moves identities whose `sourcePID` has already resolved rather than waiting out the full resolution pass, which runs ~8 s on a dense bar while Control Center is slow to answer. The match is exact on `uniqueIdentifier`, so an unresolved sibling cannot be moved by mistake.
- The Thaw icon relocates immediately when macOS parks it left of the hidden divider, instead of leaving the menu bar without a Thaw icon for the whole settling period.

#### Move planning and storm bounds

- The full-sort planner that rearranged the entire bar is gone. Bulk apply keeps the per-item and control-item paths (#885).
- Move success is verified by adjacency in a single snapshot instead of exact `CGFloat` coordinate equality against a target that reflows mid-drag. Stale destinations abort rather than burn retries.
- Automatic re-applies are capped: one retry after an unfinished batch, then a 60 s cooldown, and a batch abandons after three consecutive failures. Notch-overflow ejections now go through the failure ledger (#900).
- An automatic bulk apply waits for a 300 ms lull in input before issuing its sequence, capped at 2 s so the batch still runs. A batch holds the cursor for its whole length, so one dispatched the instant a late arrival is noticed used to take the pointer mid-interaction and then contest it move by move (#899, #723).
- Synthetic move events address the window's owner instead of the app that owns the item. On macOS 26 Control Center hosts every status item window, so those are different processes; addressing the host is what lets a slot with an unresolved owner move at all, and it clears move failures that were timing out against a process that did not own the drag (#900, #923, #924).
- Parked off-screen items are excluded from the `H_ctrl` drag anchor, and a parked divider skips the boundary move and records ledger backoff (#899).
- Diagnostics log a section-order digest instead of counts alone.

#### Control items and identity

- Divider seeding and restore write through the section-divider guard, and hide or removal restores divider positions too (#890).
- AX-correlated identity can promote an unresolved Control Center placeholder, so layout-editor moves and saved order use the owning app's identifier (#905).
- Silent move refusals log the stage, gate, and owner instead of a bare `cannotComplete` (#905).

#### Persist gates

- The always-hidden display-spread gate ignores parked items. It had been skipping `saveSectionOrder` on every cache cycle on multi-display setups, 1088 skips and zero writes in one day of field logs, which left always-hidden items looking new and let quitting any app drag them back to Visible (#930, thanks @nightah).

#### Settings, profiles & onboarding

- Profile list rows preview the saved layout next to the key behaviour settings (#887).
- "Update All" marks a profile active when its capture matches the running state (#904).
- Applying a profile uses that profile's spacing offset instead of a stale `0` (#903).
- Profiles prune Control-Center-hosted empty-title identifiers that can never match a live item.
- The layout editor names the display it is showing (#886).
- Advanced settings reset clears every persisted boolean, not just some of them (#910, thanks @YuriNachos). The two toggles added later in this cycle, "Arrange menu bar items" and "Move the pointer to revealed items", are covered too; leaving automatic arrangement off and then resetting to defaults used to keep it off with nothing on screen to explain why layouts stopped restoring.
- `leftAligned` and `rightAligned` accepted as valid `iceBarLocation` values (#911, thanks @YuriNachos).
- Settings search weights un-inverted: title now outranks keywords (#918, thanks @YuriNachos).
- Icon refresh rate normalized onto one grid shared by the slider, URI handler, live capture floor, and Defaults: off, or `1/n` seconds for integer `n` in 1…30 (#929, thanks @CamilleGuillory).
- Relaunches after a revoked permission show the onboarding permissions flow rather than the pre-redesign `PermissionsView`.

#### Appearance, capture & IceBar

- ScreenCaptureKit picks the display with the largest intersection and rejects zero-area ones, and refreshes shareable content when cached topology leaves a window looking orphaned (#794, thanks @bpresles).
- IceBar color sampling survives a horizontal bar that overflows to full screen width; the inset-frame math falls back to panel center instead of dividing by zero (#915, thanks @YuriNachos).
- `IceGradient.averageColor` returns `nil` on an all-nil sample count instead of averaging by zero (#914, thanks @YuriNachos).

#### Platform & engineering

- `swift-subprocess` 1.0.0 adopted; the env trampoline is gone.
- `AlphaChannelView` centralizes alpha-channel access and transparency scanning, so bounds validation happens in one place instead of in each `isTransparent` implementation.
- `LayoutSolver` base-ID extraction deduplicated; three inline copies and a dead helper became one (#906, thanks @YuriNachos).
- Statement coverage raised toward 90% by splitting untestable live AppKit / WindowServer paths out of `ProfileManager` and `DisplaySettingsManager` and covering the decision logic that remains (#916).
- New suites around the storm bounds: layout storm replay, move timeout, section-order digest, control-item seeding and recovery, stale destination, unfinished batch, early-apply restriction, parked divider, section geometry, placeholder alias, Thaw Bar routing.

#### Release, CI & docs

- Workflows migrated to Blacksmith runners (#901), then narrowed to the release workflows.
- CodeQL runs on GitHub-hosted macOS 26.
- Issue triage keeps regressions open instead of closing P0 reports (#882, thanks @jamesyc), and no longer trips its own threat detection.
- Agentic workflows upgraded to v0.85.4; native GitHub issue taxonomy adopted (#867).
- OpenSSF Best Practices badge moved from Silver to Gold; README badges and links reworked.
- github-actions dependency group bumped (#926).

### Fixed

#### Move planning and storm bounds

- Failed move attempts no longer starve the operation timeout budget.
- An unfinished bulk apply no longer writes its partial order into `savedSectionOrder`.
- Bulk apply restores membership in the hidden and always-hidden sections but no longer reorders *within* them. Each of those moves costs a cursor hijack and a synthesised drag to land an item thousands of points off-screen, where Thaw Bar renders from the cache anyway. Dropping them is most of what shortens long batches on the bars where length hurts.
- Late-arrival detection ignores unresolved identities, so a `sourcePID` flap no longer reads as a bar full of new items.
- Display-sized overlay windows (Droppy's drag catcher, for one) are no longer treated as an open menu.

#### Control items and identity

- Control-item pairing no longer selects Thaw's visible chevron as the hidden divider. The mispair made the hidden section read zero width, so every item landed visible after a restart (#927), hidden icons left of the notch had no region to render into (#924), and layout-editor drags had no divider to verify against (#923).
- `preflightSetup` no longer re-stamps the hidden divider to `1` on every launch and status-item recreation. That second write had been draining `savedSectionOrder` across launches, 64/46/12 down to 42/52/12 in two clean starts (#895).
- Source PID resolution no longer skips Thaw's own disabled dividers, which is the normal state of a collapsed section (#899).
- Owner-titled degraded readings (`bundleId:bundleId`) count as a failed observation rather than a new bar, so they stop minting a second identifier set (#881, #927).
- Stale saved identifiers stop matching once the bar retires them, and foreign items are no longer namespaced under `com.stonerl.Thaw:`.
- Source PIDs are re-asked when the first scan after login leaves items provisional, and a dead cached PID no longer wins over live resolution.

#### Persist gates

- An emptied hidden section (everything dragged into Visible) no longer latches `hiddenSectionHasRoom` permanently read-only. A genuine collapse still refuses; parked off-display items are what tell the two apart (#868).
- Temporarily shown items no longer register as layout drift, so opening a hidden item's menu stops dispatching a bulk apply that dumps the hidden section (#907).
- LyricsX-style lyric titles collapse to a stable identity, so a song change stops minting new items (#815, thanks @yoodu).
- Saved-layout entries that can never match a live item again are pruned.

#### Settings, profiles & onboarding

- Sections holding nothing but the new-items badge accept drops again (#897, thanks @alvst).
- Auto-rehide `focusedApp` and timed strategy guards restored after a merge dropped them.

#### Appearance, capture & IceBar

- Screen recording no longer pushes notch overflow into a `cannotComplete` ejection loop that holds the cursor (#935, thanks @Zophiekat).

#### Performance & memory

- Change-detector recaches back off while control-item lookups keep failing, exponential and capped at 60 s. Each rebuild was leaking a CA fence Mach port on macOS 26; bounding the retry cadence stops the 47 GiB owned-unmapped growth reported against rc.2.1 (#933, thanks @slatlasdev). This bounds the storm, it does not patch AppKit's `NSSceneStatusItem`.
- No-op status-item rewrites on state reassignment dropped, same leak class.

### Contributors

Thanks to everyone who reported, diagnosed, or landed fixes in this RC:

@aliaskar-rockeater · @alvst · @bpresles · @brucemakes012 · @CamilleGuillory · @Daventure91 · @howardhey · @jamesyc · @Jizzy015 · @kn666 · @lathe-agent-oa · @lucifercraig12345-create · @MashnoorKek · @nightah · @nk-tedo-001 · @slatlasdev · @stu-carter · @VailElla · @warmup72 · @yoodu · @YuriNachos · @Zophiekat

---

### Notable issue closures

| Area | Issues |
|------|--------|
| Cold start / launch restore | #881, #900 |
| Move planning / storms | #885, #899, #930 |
| Control items / identity | #890, #895, #905, #923, #924, #927 |
| Persist gates / hidden section | #815, #868, #907 |
| Profiles | #887, #903, #904 |
| Settings / layout editor | #886, #897, #910, #911, #918, #929 |
| Appearance / capture / IceBar | #794, #914, #915, #935 |
| Memory | #933 |
| Feature requests | #248, #751, #769 |
| Ops / CI | #867, #882 |
| Closed without code in this release (duplicate, not planned, user-resolved, or already fixed) | #800, #891, #893, #902, #908, #931 |

Merged PRs behind the above: #889, #892, #897, #901, #906, #910, #911, #914, #915, #916, #918, #926, #928, #929, #930.

---

### Known issues

- Control Center source PID resolution is still slow on dense bars (~8 s). Early apply only moves identities that have already resolved.
- The first-press warm-up nudge after a move-drag remains open.
- #788, #634, and #791 need a field pass. The emptied-section and parked-divider work helps some #868 collapse cases, but the docked / notched / secondary-display combination still wants verification.
- #898 and #939 were reviewed against this branch and left open; the evidence does not yet point at a code path here.

---

### Upgrade notes

1. **From 2.0.0-rc.2.1:** in-place Sparkle update. If the bar is already scrambled, run `/Applications/Thaw.app/Contents/MacOS/Thaw --reset-layout` once before launching.
2. **AX click delivery** is now on by default and no longer shown in Advanced. It ran behind an experimental flag without failure reports and still falls back to a synthetic click on any error. Anyone who set `UseAXClickDelivery` explicitly keeps their choice, and with the toggle gone from Settings, a tester who switched it off during the RC stays off. `defaults delete com.stonerl.Thaw UseAXClickDelivery` restores the new default.
3. **The reliability gates ship on.** `postMoveEventsToWindowOwner` (on), `bulkApplyIdleThresholdMs` (300 ms), and `enforceConcealedSectionOrder` (off, trading invisible ordering moves for shorter batches) now default to the configuration the test build handed to reporters, rather than the conservative values they were developed behind. They remain hidden diagnostic flags, so `defaults write com.stonerl.Thaw <key> …` still overrides any of them. Note that an override set during RC testing survives the update and wins over the new default; `defaults delete com.stonerl.Thaw <key>` returns that machine to shipping behaviour.
4. **Icon refresh rate** is normalized to off or `1/n` seconds for integer `n` in 1…30. Values off that grid are snapped on read, so a custom URI or defaults value may shift slightly.
5. **Legacy Ice / V1 appearance:** still converted on import.
6. **Update feed:** unchanged. New installs use `thaw-app/updates`; the legacy stonerl feed keeps receiving the mirrored appcast. macOS 27 remains on the alpha channel, which requires beta updates to be enabled.

## [2.0.0-rc.2.1] - 2026-08-05

### Hotfix

- Hidden divider boundary and layout-editor drags: repair the visible/hidden boundary when `H_ctrl` drifts before the per-item reorder pass, so `applyProfileLayout` no longer reports "all items already in correct positions" while the whole hidden section sits misplaced. Drops into an empty hidden section that only contains the new-items badge no longer snap back, and persistent status-level windows (shelf/HUD) no longer defer every move, though deferral still applies while the pointer is inside a long-open menu (#880, fixes #879).

---

This RC is a large reliability and platform update: menu bar identity/ordering, layout persistence, notch overflow, settings UI, Swift 6.2 / concurrency, and Sparkle update hosting.

---

### Highlights

- Menu bar reliability overhaul: safer saved-layout apply/persist, stronger item identity matching, and fewer false “reorder storms,” especially with Control Center items, dynamic titles, and multi-display setups.
- Settings & onboarding refresh: redesigned settings UI, glass tour onboarding, stronger AX identity / click paths.
- Swift 6.2 + approachable concurrency: MainActor default isolation on the app target, AXSwift6, EventTap synchronization, and cleanup of pre–Swift 6 GCD/Timer patterns.
- Update distribution: Sparkle ZIP/deltas/appcast publish to `thaw-app/updates`, with a mirror for legacy `stonerl` Pages installs.

---

### New

#### Identity, ordering, and clicks

- Optional AX click delivery (`useAXClickDelivery`, default off) with synthetic-click fallback.

### Changed

#### Identity, ordering, and clicks

- Deterministic visual ordering with stable identifier tie-breaks (no more shuffle when `minX` ties).
- Volatile metric titles (e.g. `CPU 12%` → `CPU 43%`) canonicalized so saved layouts and failure ledgers keep matching; prune stale title-variant saved entries that fueled reorder storms (#842, thanks @danielhopkins).
- Failure ledger stamped with build version so marks clear on update; avoid exclusivity violation when persisting the ledger (thanks @VailElla).
- Click reaction verification: success only if the owner shows a real UI reaction, not just event delivery.
- Report control items the menu bar accepts but does not render (notch occlusion), with consecutive-sample confirmation (#570).
- Unresponsive owner / window-mismatch error types for clearer click failure handling.

#### Saved layout & persistence

- Do not move items on untrustworthy observations (#849).
- Block `saveSectionOrder` while layout divergence is still pending.
- Do not persist collapsed hidden sections (#795).
- Do not persist layouts with an unresolved always-hidden divider (#849).
- Do not persist notch-overflow ejections as user intent (#790 / #796, thanks @lathe-agent-oa).
- Skip bulk apply while source PIDs are unresolved (#784 / #785, thanks @lathe-agent-oa).
- Refuse saved-layout bulk apply while the hidden-section dividers are collapsed / zero-width, the same `hiddenSectionHasRoom` gate the save path already uses, so a collapsed reading cannot drag the whole hidden section and then get persisted (#868 / #876, thanks @TheBenMeadows).
- Revalidate hidden-section geometry before the move batch runs so apply does not proceed on a stale collapsed reading (#876).
- Prefer exact saved identifiers; avoid ambiguous multi-instance divergence matches (#714 / #716, thanks @t4sh).
- Defer apply/persist on unsettled or cross-display geometry; clear stuck profile flags (#702, #717, #743).
- Ignore unresolved Control Center placeholders (#810, thanks @VailElla).
- Resolve parked items titled with their bundle ID (e.g. Little Snitch) (#709, #795 / #797, thanks @lathe-agent-oa).
- Delete profile manifest entries even when the file is already missing.
- Negative-cache TTL for source PID lookups uses per-window backoff instead of a flat 60s (#856, thanks @lathe-agent-oa).

#### Notch overflow

- Only run overflow on the main display; fail closed if active menu bar display is unknown (#808 / #809, thanks @lathe-agent-oa).
- Keep the visible control item in place during overflow (#742).
- Keep overflow running outside profile applies.

#### Moves, rehide, and multi-instance

- Defer item moves while a menu bar item menu is tracking.
- Require stable divergence; suppress bulk cursor warps (#705, #723, #736, #750).
- Keep menu bar move events out of screen corners, which stops Hot Corner / Show Desktop false triggers (#625, #766 / #774, thanks @ZeterMordio).
- Recover blocked items before alerting on hidden-section drags (#744).
- Recover control items after lookup failure.
- Bail instead of trapping on inverted control-item order.
- Keep timed rehide armable after deferred rehide; anchor rehide to a neighbor in the item’s own section so temporarily shown items are not rehidden into Visible (#859 / #860, thanks @andredlng).
- Prevent duplicate Thaw instances from competing (#821, thanks @alvst).
- Each layout-reset waiter gets its own cache continuation.
- Configurable pre-move input-pause threshold (#756, thanks @subway-jack).
- Fall back to Thaw Bar when hiding app menus under fullscreen (#740 / #741, thanks @auspic7).
- Defer/stabilize moves that previously relocated system modules mid-interaction (e.g. AudioVideoModule / WeType, #746) and reduced cursor teleport / dance storms (#718, #723, #750).

#### Settings, profiles & onboarding

- Settings UI redesign: native grouped forms, relocated options, refreshed Ice UI primitives, sidebar search.
- Glass tour onboarding in first-launch and settings.
- Ice V1 appearance data converted at import time.
- Cleared hotkey bindings removed instead of persisting JSON `null`.
- Authorization retry allowed after denial (#780 / #781, thanks @VailElla).
- Full onboarding button hit targets (#724, thanks @eli-yip).
- IceBar naming leftover on an Advanced setting corrected (#829).
- Settings About/repository URL updated (thanks @cbguder).
- Hidden debug flags moved into the Defaults registry.
- Unreachable Ice-era migrations removed.
- Layout reset target picker with legacy section moves.

#### Appearance, capture & IceBar

- Capture bounds validated before WindowServer handoff (#759 / #813).
- Individual captures use the captured scale (layout icon sizing, #703).
- SCStream pinned to 32BGRA; shareable-content fetches coalesced.
- Image cache: LRU/concurrency overhaul, lossless disk keys, rate-limited on-screen capture, stale display ID fallback (#749, thanks @hxu).
- Memory: detach cropped glyphs, lower icon refresh, stop background captures (#680).
- Tooltips stay above Thaw Bar / IceBar grid (#760 / #782, thanks @VailElla) with watchdog placement (#734).
- Virtual display resolver removed (brief resolution / screen-shrink side effects, #708).

#### Accessibility, hooks & events

- Bounded AX messaging timeouts in the item service and event path (#767).
- Consolidated item failure ledgers; quieter expected `procNotFound`.
- Mouse-moved handling throttled by time, not event count.
- Shared/adaptive Mission Control detection (#777).
- EventTap shared runtime state synchronized.

#### Performance

- Rate-limited on-screen image capture path.
- Memoized per-row item search work.
- Shared Mission Control detection.
- Time-based mouse-moved throttle.

#### Platform & engineering

- Swift 6.2 packaging alignment.
- MainActor default isolation on the app target.
- `@Observable` migration for ObservableObject surfaces.
- `SourcePIDCache` converted to an actor.
- Hooks/spacing via `swift-subprocess` (0.5).
- `swift-algorithms` adopted; package-underuse cleanup.
- Virtual display resolver removed.
- `SettingsURIParser` extracted; fuzz + contract tests.
- Broader unit coverage (settings, HID, replay, layout gates, URI, search, Swift Testing migration).
- Sonar excludes Icon Composer bundles (thanks @VailElla).

#### Release, CI & docs

- Sparkle payloads published to **`thaw-app/updates`** (#840); DMGs remain on GitHub Releases.
- Appcast mirrored to legacy **stonerl Pages** (#843).
- Org CI / brand-assets adoption; Sparkle no longer auto-publishes on every tag push.
- OpenSSF / Scorecard / CodeQL / SLSA provenance / OSV SCA hardening; Sonar coverage path fix.
- README restyle/restructure; `RELEASES.md`, verifying releases, governance/security docs; contribution/install docs (thanks @t4sh); URI scheme docs (thanks @davidnichols-ops).
- Crowdin / localization syncs (#694, #804–#807).

### Fixed

#### Identity, ordering, and clicks

- Stop provisional identities from scrambling saved layout (#863).
- AX identity catalog + ControlItemPair frame fallback (fixes silent hidden-section death when control items could not be identified, #754).

#### Saved layout & persistence

- Restore unresolved-`sourcePID` gate in `applySavedLayout`.
- Restore legacy profile layout snapshots (#778 / #779, thanks @ShiroKSH).

#### Notch overflow

- Avoid redundant full-sort replays (#822, thanks @alvst).

#### Moves, rehide, and multi-instance

- Stop bulk-apply pointer hijack; release on user input.
- Avoid repeated source PID cache scans (#820, thanks @alvst).

#### Settings, profiles & onboarding

- Unconfigured displays fall back to **global configuration** instead of hardcoded defaults (fixes spacing resets on Space/display changes).

#### Appearance, capture & IceBar

- Tint no longer covers menu bar items; tint renders above the menu bar under Reduce Transparency (#844, #700).
- Cursor restore after profile apply uses CoreGraphics space (fixes multi-monitor warp).

#### Accessibility, hooks & events

- Hook timeouts bounded with process-group teardown; teardown restored after Subprocess 0.5 upgrade.
- Clicking items in Thaw Bar no longer spikes CPU via runaway work (#757).

### Contributors

Thanks to everyone who landed fixes in this RC:

@alvst · @andredlng · @auspic7 · @cbguder · @danielhopkins · @davidnichols-ops · @eli-yip · @hxu · @lathe-agent-oa · @ShiroKSH · @subway-jack · @t4sh · @TheBenMeadows · @VailElla · @ZeterMordio

---

### Notable issue closures

| Area | Issues |
|------|--------|
| Layout / identity / persist | #702, #705, #709, #714, #717, #718, #776, #778, #783, #784, #789, #790, #795, #826, #828, #849, #863, #868 |
| Notch / overflow | #570, #808 |
| Moves / cursor / Hot Corners | #625, #723, #736, #744, #746, #750, #766 |
| Control items / hidden section | #740, #754, #859 |
| Appearance / capture / memory | #680, #700, #703, #708, #734, #759, #760, #844 |
| Search / AX / Mission Control | #767, #777, #757 |
| Settings / permissions / UX | #701, #724, #780, #829 |
| Releases | #840, #843 |
| Closed as duplicate | #727 |
| Closed without code change (stale / upstream / not planned / user-resolved) | #571, #610, #649, #664, #707, #720, #721, #722, #726, #851, #852 |

Related merged fix PRs called out above include #716, #741, #749, #756, #774, #779, #781, #782, #785, #796, #797, #809, #810, #813, #820, #821, #822, #838, #842, #856, #860, #862, #876. Reliability stack landed via #811 → revert #857 → re-land #858.

---

### Upgrade notes

1. **From 2.0.0-rc.2:** in-place Sparkle update; hotfix only, no behaviour changes beyond the fix above.
2. **From 2.0.0-rc.1:** in-place Sparkle update; failure-ledger marks clear on build change.
3. **Legacy Ice / V1 appearance:** converted on import.
4. **Update feed:** new installs use `thaw-app/updates`; existing stonerl feed users keep updating via the mirrored appcast.
5. **Experimental:** Advanced → AX click delivery remains off by default.

## [2.0.0-rc.2] - 2026-08-04

This RC is a large reliability and platform update: menu bar identity/ordering, layout persistence, notch overflow, settings UI, Swift 6.2 / concurrency, and Sparkle update hosting.

---

### Highlights

- **Menu bar reliability overhaul** — safer saved-layout apply/persist, stronger item identity matching, and fewer false “reorder storms,” especially with Control Center items, dynamic titles, and multi-display setups.
- **Settings & onboarding refresh** — redesigned settings UI, glass tour onboarding, stronger AX identity / click paths.
- **Swift 6.2 + approachable concurrency** — MainActor default isolation on the app target, AXSwift6, EventTap synchronization, and cleanup of pre–Swift 6 GCD/Timer patterns.
- **Update distribution** — Sparkle ZIP/deltas/appcast publish to `thaw-app/updates`, with a mirror for legacy `stonerl` Pages installs.

---

### New

#### Identity, ordering, and clicks

- Optional AX click delivery (`useAXClickDelivery`, default off) with synthetic-click fallback.

### Changed

#### Identity, ordering, and clicks

- Deterministic visual ordering with stable identifier tie-breaks (no more shuffle when `minX` ties).
- Volatile metric titles (e.g. `CPU 12%` → `CPU 43%`) canonicalized so saved layouts and failure ledgers keep matching; prune stale title-variant saved entries that fueled reorder storms (#842, thanks @danielhopkins).
- Failure ledger stamped with build version so marks clear on update; avoid exclusivity violation when persisting the ledger (thanks @VailElla).
- Click reaction verification: success only if the owner shows a real UI reaction, not just event delivery.
- Report control items the menu bar accepts but does not render (notch occlusion), with consecutive-sample confirmation (#570).
- Unresponsive owner / window-mismatch error types for clearer click failure handling.

#### Saved layout & persistence

- Do not move items on untrustworthy observations (#849).
- Block `saveSectionOrder` while layout divergence is still pending.
- Do not persist collapsed hidden sections (#795).
- Do not persist layouts with an unresolved always-hidden divider (#849).
- Do not persist notch-overflow ejections as user intent (#790 / #796, thanks @lathe-agent-oa).
- Skip bulk apply while source PIDs are unresolved (#784 / #785, thanks @lathe-agent-oa).
- Refuse saved-layout bulk apply while the hidden-section dividers are collapsed / zero-width — same `hiddenSectionHasRoom` gate the save path already uses — so a collapsed reading cannot drag the whole hidden section and then get persisted (#868 / #876, thanks @TheBenMeadows).
- Revalidate hidden-section geometry before the move batch runs so apply does not proceed on a stale collapsed reading (#876).
- Prefer exact saved identifiers; avoid ambiguous multi-instance divergence matches (#714 / #716, thanks @t4sh).
- Defer apply/persist on unsettled or cross-display geometry; clear stuck profile flags (#702, #717, #743).
- Ignore unresolved Control Center placeholders (#810, thanks @VailElla).
- Resolve parked items titled with their bundle ID (e.g. Little Snitch) (#709, #795 / #797, thanks @lathe-agent-oa).
- Delete profile manifest entries even when the file is already missing.
- Negative-cache TTL for source PID lookups uses per-window backoff instead of a flat 60s (#856, thanks @lathe-agent-oa).

#### Notch overflow

- Only run overflow on the main display; fail closed if active menu bar display is unknown (#808 / #809, thanks @lathe-agent-oa).
- Keep the visible control item in place during overflow (#742).
- Keep overflow running outside profile applies.

#### Moves, rehide, and multi-instance

- Defer item moves while a menu bar item menu is tracking.
- Require stable divergence; suppress bulk cursor warps (#705, #723, #736, #750).
- Keep menu bar move events out of screen corners — stops Hot Corner / Show Desktop false triggers (#625, #766 / #774, thanks @ZeterMordio).
- Recover blocked items before alerting on hidden-section drags (#744).
- Recover control items after lookup failure.
- Bail instead of trapping on inverted control-item order.
- Keep timed rehide armable after deferred rehide; anchor rehide to a neighbor in the item’s own section so temporarily shown items are not rehidden into Visible (#859 / #860, thanks @andredlng).
- Prevent duplicate Thaw instances from competing (#821, thanks @alvst).
- Each layout-reset waiter gets its own cache continuation.
- Configurable pre-move input-pause threshold (#756, thanks @subway-jack).
- Fall back to Thaw Bar when hiding app menus under fullscreen (#740 / #741, thanks @auspic7).
- Defer/stabilize moves that previously relocated system modules mid-interaction (e.g. AudioVideoModule / WeType, #746) and reduced cursor teleport / dance storms (#718, #723, #750).

#### Settings, profiles & onboarding

- **Settings UI redesign** (native grouped forms, relocated options, refreshed Ice UI primitives, sidebar search).
- **Glass tour** onboarding in first-launch and settings.
- Ice V1 appearance data converted at import time.
- Cleared hotkey bindings removed instead of persisting JSON `null`.
- Authorization retry allowed after denial (#780 / #781, thanks @VailElla).
- Full onboarding button hit targets (#724, thanks @eli-yip).
- IceBar naming leftover on an Advanced setting corrected (#829).
- Settings About/repository URL updated (thanks @cbguder).
- Hidden debug flags moved into the Defaults registry.
- Unreachable Ice-era migrations removed.
- Layout reset target picker with legacy section moves.

#### Appearance, capture & IceBar

- Capture bounds validated before WindowServer handoff (#759 / #813).
- Individual captures use the captured scale (layout icon sizing, #703).
- SCStream pinned to 32BGRA; shareable-content fetches coalesced.
- Image cache: LRU/concurrency overhaul, lossless disk keys, rate-limited on-screen capture, stale display ID fallback (#749, thanks @hxu).
- Memory: detach cropped glyphs, lower icon refresh, stop background captures (#680).
- Tooltips stay above Thaw Bar / IceBar grid (#760 / #782, thanks @VailElla) with watchdog placement (#734).
- Virtual display resolver removed (brief resolution / screen-shrink side effects, #708).

#### Accessibility, hooks & events

- Bounded AX messaging timeouts in the item service and event path (#767).
- Consolidated item failure ledgers; quieter expected `procNotFound`.
- Mouse-moved handling throttled by time, not event count.
- Shared/adaptive Mission Control detection (#777).
- EventTap shared runtime state synchronized.

#### Performance

- Rate-limited on-screen image capture path.
- Memoized per-row item search work.
- Shared Mission Control detection.
- Time-based mouse-moved throttle.

#### Platform & engineering

- **Swift 6.2** packaging alignment.
- MainActor default isolation on the app target.
- `@Observable` migration for ObservableObject surfaces.
- `SourcePIDCache` converted to an actor.
- Hooks/spacing via `swift-subprocess` (0.5).
- `swift-algorithms` adopted; package-underuse cleanup.
- Virtual display resolver removed.
- `SettingsURIParser` extracted; fuzz + contract tests.
- Broader unit coverage (settings, HID, replay, layout gates, URI, search, Swift Testing migration).
- Sonar excludes Icon Composer bundles (thanks @VailElla).

#### Release, CI & docs

- Sparkle payloads published to **`thaw-app/updates`** (#840); DMGs remain on GitHub Releases.
- Appcast mirrored to legacy **stonerl Pages** (#843).
- Org CI / brand-assets adoption; Sparkle no longer auto-publishes on every tag push.
- OpenSSF / Scorecard / CodeQL / SLSA provenance / OSV SCA hardening; Sonar coverage path fix.
- README restyle/restructure; `RELEASES.md`, verifying releases, governance/security docs; contribution/install docs (thanks @t4sh); URI scheme docs (thanks @davidnichols-ops).
- Crowdin / localization syncs (#694, #804–#807).

### Fixed

#### Identity, ordering, and clicks

- Stop provisional identities from scrambling saved layout (#863).
- AX identity catalog + ControlItemPair frame fallback (fixes silent hidden-section death when control items could not be identified, #754).

#### Saved layout & persistence

- Restore unresolved-`sourcePID` gate in `applySavedLayout`.
- Restore legacy profile layout snapshots (#778 / #779, thanks @ShiroKSH).

#### Notch overflow

- Avoid redundant full-sort replays (#822, thanks @alvst).

#### Moves, rehide, and multi-instance

- Stop bulk-apply pointer hijack; release on user input.
- Avoid repeated source PID cache scans (#820, thanks @alvst).

#### Settings, profiles & onboarding

- Unconfigured displays fall back to **global configuration** instead of hardcoded defaults (fixes spacing resets on Space/display changes).

#### Appearance, capture & IceBar

- Tint no longer covers menu bar items; tint renders above the menu bar under Reduce Transparency (#844, #700).
- Cursor restore after profile apply uses CoreGraphics space (fixes multi-monitor warp).

#### Accessibility, hooks & events

- Hook timeouts bounded with process-group teardown; teardown restored after Subprocess 0.5 upgrade.
- Clicking items in Thaw Bar no longer spikes CPU via runaway work (#757).

### Contributors

Thanks to everyone who landed fixes in this RC:

@alvst · @andredlng · @auspic7 · @cbguder · @danielhopkins · @davidnichols-ops · @eli-yip · @hxu · @lathe-agent-oa · @ShiroKSH · @subway-jack · @t4sh · @TheBenMeadows · @VailElla · @ZeterMordio

---

### Notable issue closures

| Area | Issues |
|------|--------|
| Layout / identity / persist | #702, #705, #709, #714, #717, #718, #776, #778, #783, #784, #789, #790, #795, #826, #828, #849, #863, #868 |
| Notch / overflow | #570, #808 |
| Moves / cursor / Hot Corners | #625, #723, #736, #744, #746, #750, #766 |
| Control items / hidden section | #740, #754, #859 |
| Appearance / capture / memory | #680, #700, #703, #708, #734, #759, #760, #844 |
| Search / AX / Mission Control | #767, #777, #757 |
| Settings / permissions / UX | #701, #724, #780, #829 |
| Releases | #840, #843 |
| Closed as duplicate | #727 |
| Closed without code change (stale / upstream / not planned / user-resolved) | #571, #610, #649, #664, #707, #720, #721, #722, #726, #851, #852 |

Related merged fix PRs called out above include #716, #741, #749, #756, #774, #779, #781, #782, #785, #796, #797, #809, #810, #813, #820, #821, #822, #838, #842, #856, #860, #862, #876. Reliability stack landed via #811 → revert #857 → re-land #858.

---

### Upgrade notes

1. **From 2.0.0-rc.1:** in-place Sparkle update; failure-ledger marks clear on build change.
2. **Legacy Ice / V1 appearance:** converted on import.
3. **Update feed:** new installs use `thaw-app/updates`; existing stonerl feed users keep updating via the mirrored appcast.
4. **Experimental:** Advanced → AX click delivery remains off by default.

## [macos-27-preview.5] - 2026-07-25

Experimental build for **macOS 27 (Golden Gate)** — not on the Sparkle update channel.

| | |
|---|---|
| Commit | [`528b950`](https://github.com/stonerl/Thaw/commit/528b9503b051cc1ccccae766014e64404670088b) |
| Branch | `feat/macos-27-experimental` |
| Build | [Build DMG #29982043048](https://github.com/stonerl/Thaw/actions/runs/29982043048) |
| Artifact | [Thaw-dmg](https://github.com/stonerl/Thaw/actions/runs/29982043048/artifacts/8553636866) |
| Announced | [#687 comment](https://github.com/stonerl/Thaw/issues/687#issuecomment-5055005624) |
| Feedback | [Discussion #737](https://github.com/stonerl/Thaw/discussions/737) · Tracking [#687](https://github.com/stonerl/Thaw/issues/687) |

**Out of update channel** — install manually; Sparkle / `appcast.xml` were not updated.

> Active development preview. Issues with Focus and multiple items from the same app should be improved versus earlier builds. Items from the same app still cannot be separated independently.

---

### Changed

#### macOS 27 menu bar reliability

- Dampen menu bar churn from recache / visible-control restore
- Prune orphaned control-item position keys on startup
- Capture Thaw’s own icon from the display strip
- Preserve Focus and Now Playing assignments
- Preserve section order during reveal; stop reveal-time position rewrites that blocked rehide clicks
- Keep refresh signatures stable when concealed items leave the cache
- Show real names for item tooltips
- Group same-bundle items and exclude strip overlays

#### Ice Bar / capture

- Hide stale app-icon fallbacks
- Coalesce shareable-content fetches
- Icon fallback path; retire stale capture paths
- Refine layout icon previews and adaptive icon presentation

#### Memory / concurrency

- Detach cropped glyph images before caching
- Lower default icon refresh rate (10 fps → 4 fps)
- Synchronize shared runtime state

#### Settings / UI

- Tools safety disclaimer
- Reduce-motion-gated animations (Ice Bar, badge, tour)
- Settings / Layout Bar cleanup and glass vocabulary unification
- Profile delete confirmation alert hoisted to pane root
- Localization: plural rules, punctuation, locale-safe timing labels

#### Tooling

- CI on Xcode 27 runners

### Fixed

#### macOS 27 menu bar reliability

- Stop Visible-section snap-back and Layout chevron glyph glitches

#### Ice Bar / capture

- Avoid native overflow arrow captures

#### Settings / UI

- Automation URI warning icon fix

### Notes
- Still experimental — expect edge cases on Public Betas; please report in [#737](https://github.com/stonerl/Thaw/discussions/737).
- App marketing version in the binary may still read `2.0.0-rc.1 (47)`; the Git tag is the preview identifier.

## [macos-27-preview.4] - 2026-07-25

Experimental build for **macOS 27 (Golden Gate)** — not on the Sparkle update channel.

| | |
|---|---|
| Commit | [`88bc31474b7d`](https://github.com/stonerl/Thaw/commit/88bc31474b7d542f825f4e7ab01d52b87218aa06) |
| Branch | `feat/macos-27-experimental` |
| Build | [Build DMG #28663219830](https://github.com/stonerl/Thaw/actions/runs/28663219830) |
| Artifact | [Thaw-dmg](https://github.com/stonerl/Thaw/actions/runs/28663219830/artifacts/8067684698) |
| Announced | [#687 comment](https://github.com/stonerl/Thaw/issues/687#issuecomment-4876833738) |
| Feedback | [Discussion #737](https://github.com/stonerl/Thaw/discussions/737) · Tracking [#687](https://github.com/stonerl/Thaw/issues/687) |

**Out of update channel** — install manually; Sparkle / `appcast.xml` were not updated.

---

### macOS 27 Preview 4 — Release Notes

This is the highly likely the final experimental preview for macOS 27. If no further critical issues are found, the next build will transition to the Alpha phase as we shift from initial API adaptation to stabilization and regression testing. The target is the v2.1.0 development cycle, but the exact timing depends on the team’s migration to the macOS 27 beta environment, so the availability date may still shift.

Download [here](https://github.com/stonerl/Thaw/actions/runs/28663219830/artifacts/8067684698) or [here](https://drive.proton.me/u/0/7w4Loq0NTcsxYG81gdbk9MXJvIXkXKLV8Yh_rFeln9DkBKWpGPpptQRgNecC2r4OIZKpIZ-4fdlvUDZ-znhX2w==/folder/MT_92-linBrSRLdydaoZhcjcQVdk01MY-XlQKmFEehCijZwPhKUgNkekw9rQ2E35P5TZeJAmVu-zVB7TQBRVZA==?r=/7w4Loq0NTcsxYG81gdbk9MXJvIXkXKLV8Yh_rFeln9DkBKWpGPpptQRgNecC2r4OIZKpIZ-4fdlvUDZ-znhX2w==/folder/a3sx9nb6seeps_q-U2nD-ARgDb8Z7OSkPw-KT5v_WilQLxvqbWvWV_Qe57vA-lX4Igq85I48_cy66TFoW-J-RQ==)

> [!NOTE]
>Please log all issues in [#737](https://github.com/stonerl/Thaw/discussions/737). Include your environment details (Mac model, notch, conflicting menu bar apps) and diagnostic logs.

#### Fixed

- Fixed duplicate icons, repeated arrow icons, and icons showing the wrong app — caused by macOS 27's new "overflow" arrow being mistaken for a regular menu bar item.
- Your cursor no longer gets pulled around while Thaw is rearranging icons — mouse movement during a reorder used to throw things off, that's fixed now.
- Fixed Thaw's own icon (and the overflow arrow) sometimes ending up stuck in the wrong spot near the notch.
- Fixed your saved icon layout occasionally being overwritten with a temporary, unsettled layout — for example right after waking from sleep or reconnecting a display.
- Fixed the icon in the menu bar staying highlighted/stuck-looking after you clicked it.
- Fixed hidden sections sometimes not resetting properly after you closed them.
- Cleaned up spacing and wording in the Display & Layout settings pane.
- Fixed the settings search field not matching the frosted-glass look used elsewhere.
- Searching in the menu bar or settings no longer shows hidden/always-hidden icons mixed in with visible ones.
- Fixed a case where clicking a hidden icon could cause it to immediately hide again by mistake.
- The divider between hidden and visible icons now animates smoothly instead of snapping open/closed.
- Fixed a visual glitch where the background overlay would briefly appear in the wrong place.
- Fixed the onboarding walkthrough sometimes appearing twice after resetting settings.
- Fixed the saved position of hidden icons not always being remembered correctly.
- Fixed a memory leak that could occur when icons were removed from the menu bar.
- Fixed automatic icon movement continuing even while you were manually dragging an icon yourself.
- Fixed leftover icons sometimes appearing after quitting and restarting Thaw.
- Fixed small cursor jitter/flicker when hovering right at the edge of the menu bar.
- Fixed Option-click not being recognized correctly for Always Hidden on macOS 27.
- Improved the permissions flow so first launch and missing-permission recovery now use the same onboarding-style permissions screen.
 - Fixed Screen Recording permission requests so Thaw is properly added to macOS System Settings when access is requested.
 - Improved permission detection after granting access, reducing cases where Thaw still appeared to be missing Screen Recording permission.
 - Updated the layout editor to keep Apple system items like Clock, Control Center, and Siri anchored to the trailing edge when Thaw Bar is disabled.
 - Prevented users from creating menu bar layouts that macOS cannot actually apply.
 - Cleaned up old permissions UI code for a more consistent onboarding and setup experience.

#### Re-enabled

- **Always Hidden section** — turned off since the earliest macOS 27 previews, now back and working, including Option-click to reveal it. It may still behave a little differently than on macOS 26 depending on system state.

#### New

- **Settings search** — search across all of Thaw's settings from one place; results are grouped by section, and tapping one jumps you straight there.
- **Reset layout** — one button to reset your icon layout, with a picker to choose whether to reset **Visible**, **Hidden**, or **Always Hidden** icons.
- **New onboarding walkthrough** — a refreshed, more polished first-run tour. You can replay it anytime from the About page.
- **System item hiding** is no longer marked experimental — it's now a regular, supported setting.
- **Deep link support** — Thaw can now be told to reveal a specific icon via a `thaw://` link, useful for automation/shortcuts.
- Thaw now tells you in the app when it can't hide something instead of silently doing nothing.
- Refreshed the app icon's colors and lighting to better match macOS 27's new visual style.
- Proper support for macOS 27's native menu bar "overflow" icon.

## [macos-27-preview.3] - 2026-07-25

Experimental build for **macOS 27 (Golden Gate)** — not on the Sparkle update channel.

| | |
|---|---|
| Commit | [`eb9198c3db90`](https://github.com/stonerl/Thaw/commit/eb9198c3db9056c0ce7a1d118aad18804c54ae89) |
| Branch | `feat/macos-27-experimental` |
| Build | [Build DMG #28287610903](https://github.com/stonerl/Thaw/actions/runs/28287610903) |
| Artifact | [Thaw-dmg](https://github.com/stonerl/Thaw/actions/runs/28287610903/artifacts/7924008392) |
| Announced | [#687 comment](https://github.com/stonerl/Thaw/issues/687#issuecomment-4818318577) |
| Feedback | [Discussion #737](https://github.com/stonerl/Thaw/discussions/737) · Tracking [#687](https://github.com/stonerl/Thaw/issues/687) |

**Out of update channel** — install manually; Sparkle / `appcast.xml` were not updated.

---

Download [here](https://github.com/stonerl/Thaw/actions/runs/28287610903/artifacts/7924008392)
[Backup](https://drive.proton.me/u/0/7w4Loq0NTcsxYG81gdbk9MXJvIXkXKLV8Yh_rFeln9DkBKWpGPpptQRgNecC2r4OIZKpIZ-4fdlvUDZ-znhX2w==/folder/MT_92-linBrSRLdydaoZhcjcQVdk01MY-XlQKmFEehCijZwPhKUgNkekw9rQ2E35P5TZeJAmVu-zVB7TQBRVZA==?r=/7w4Loq0NTcsxYG81gdbk9MXJvIXkXKLV8Yh_rFeln9DkBKWpGPpptQRgNecC2r4OIZKpIZ-4fdlvUDZ-znhX2w==/folder/a3sx9nb6seeps_q-U2nD-ARgDb8Z7OSkPw-KT5v_WilQLxvqbWvWV_Qe57vA-lX4Igq85I48_cy66TFoW-J-RQ==)

### Highlights

- Much more complete support for hiding, showing, and reordering menu bar items on macOS 27.
- Hidden items, visible item order, and Thaw's own menu bar icon are restored more reliably after quitting and reopening Thaw.
- The menu bar appearance overlay is more stable on macOS 27, especially when using the split pill style.
- Temporarily shown hidden items now respect the configured delay before being hidden again.
- Hidden item icons and thumbnails are more reliable in Thaw Bar, Search, and the layout editor.

### New

#### macOS 27 Menu Bar Improvements

- Added preview support for hiding and reordering supported Apple system menu bar items on macOS 27.
- Added safeguards so Thaw avoids repeatedly trying moves that macOS refuses.

#### Hidden Items and Re-Hiding

- Added a setting for how long temporarily shown hidden items stay visible before being hidden again.

#### Settings and Profiles

- Added macOS 27 preview options for experimental Apple system item hiding.

#### Display and Layout Reliability

- Added more protections around apps and system items that macOS does not allow Thaw to hide safely.

### Changed

#### macOS 27 Menu Bar Improvements

- Improved hiding and restoring menu bar items on macOS 27, including items that quit, relaunch, or briefly disappear from the menu bar.
- Reduced flicker, misplaced bounds, and transient full-width overlay shapes while the menu bar is settling.
- Improved behavior around dynamic menu bar items, including iStat Menus.
- Improved behavior for Control Center, Clock, Sound, Wi-Fi, Bluetooth, Battery, Display, Keyboard, and similar Apple menu bar items.

#### Hidden Items and Re-Hiding

- Re-hide timing now follows the configured delay more consistently.
- Re-hide timers now pause while menus are open, reducing cases where an item hides while you are interacting with it.
- Always Hidden hotkeys are ignored when Always Hidden is unavailable or disabled, avoiding confusing no-op behavior.

#### Thaw Bar, Search, and Icons

- Improved prewarming for concealed sections so hidden item icons appear sooner.
- Improved icon refresh after reordering items.
- Reduced incorrect icon crops for concealed items.
- Simplified Thaw Bar hover styling for a cleaner layout.

#### Settings and Profiles

- Profiles now save and restore the temporarily shown item delay.
- Resetting settings now restores the new delay setting to its default.
- Imported Ice settings now include the new temporary-show timing option.
- Updated the macOS 27 preview help text in the About pane.

#### Display and Layout Reliability

- Improved startup settling so Thaw is less likely to capture or save a temporary menu bar layout.
- Improved behavior on notched displays and multi-display setups.
- Improved layout handling while native macOS menu bar auto-hiding changes visibility.
- Improved cursor-free reordering on macOS 27 to reduce visible cursor jumps.

### Fixed

#### macOS 27 Menu Bar Improvements

- Fixed hidden item choices not being remembered after quitting and reopening Thaw.
- Fixed visible item order not being restored correctly after relaunch.
- Fixed Thaw's own menu bar icon not keeping its saved position after relaunch.
- Fixed cases where the split pill appearance did not wrap Thaw's own menu bar icon.
- Fixed cases where the split pill appearance stretched too far left across empty menu bar space.

#### Hidden Items and Re-Hiding

- Single-item temporary reveal is more reliable and no longer flashes entire hidden sections unnecessarily.

#### Thaw Bar, Search, and Icons

- Fixed hidden item thumbnails being blank after opening Thaw Bar.
- Fixed stale blank thumbnails being kept in the icon cache.

### Known issues

- macOS 27 support is still preview. Apple system items and Control Center items do not behave like normal third-party menu bar items.
- Some Apple system items may still resist hiding or reordering depending on macOS state and System Settings.

## [macos-27-preview.2] - 2026-07-25

Experimental build for **macOS 27 (Golden Gate)** — not on the Sparkle update channel.

| | |
|---|---|
| Commit | [`7c3aa5cc2b45`](https://github.com/stonerl/Thaw/commit/7c3aa5cc2b456ce2bacd38b958975f3d7090cc68) |
| Branch | `feat/macos-27-experimental` |
| Build | [Build DMG #28003830057](https://github.com/stonerl/Thaw/actions/runs/28003830057) |
| Artifact | [Thaw-dmg](https://github.com/stonerl/Thaw/actions/runs/28003830057/artifacts/7812060096) |
| Announced | [#687 comment](https://github.com/stonerl/Thaw/issues/687#issuecomment-4783679720) |
| Feedback | [Discussion #737](https://github.com/stonerl/Thaw/discussions/737) · Tracking [#687](https://github.com/stonerl/Thaw/issues/687) |

**Out of update channel** — install manually; Sparkle / `appcast.xml` were not updated.

---

New version [here](https://github.com/stonerl/Thaw/actions/runs/28003830057/artifacts/7812060096).

The goal is to leave you with at least hidden and visible working.

### macOS 27 Preview build 2 — Release Notes

#### Fixed
- Thaw's own menu bar icon now fully works with macOS 27's reorder, hide, and layout system — it can be dragged in Layout settings, persists in saved order, stays visible correctly when sections conceal, and the background pill now wraps around it instead of leaving it outside.
- Fixed a cursor-thrashing infinite loop caused by retrying unachievable item moves (e.g. forced beside anchored system items like Sound) every ~2s.
- Restored hover-to-reveal and click handling, which had stopped working.
- Fixed disappearing icon images for concealed/hidden items caused by an overly aggressive cache cleanup.
- Fixed duplicate menu bar items appearing when an app's live AX title metrics changed.
- Fixed split-pill background positioning on multi-display setups.

Edit:
It should say `macOS 27 - Unsupported preview` in the about page.

## [macos-27-preview.1] - 2026-07-25

Experimental build for **macOS 27 (Golden Gate)** — not on the Sparkle update channel.

| | |
|---|---|
| Commit | [`7a4ce9fd68c1`](https://github.com/stonerl/Thaw/commit/7a4ce9fd68c1ba614d409000afef3d18d4b2db3d) |
| Branch | `feat/macos-27-experimental` |
| Build | [Build DMG #27930266042](https://github.com/stonerl/Thaw/actions/runs/27930266042) |
| Artifact | [Thaw-dmg](https://github.com/stonerl/Thaw/actions/runs/27930266042/artifacts/7783521840) |
| Announced | [#687 comment](https://github.com/stonerl/Thaw/issues/687#issuecomment-4765237728) |
| Feedback | [Discussion #737](https://github.com/stonerl/Thaw/discussions/737) · Tracking [#687](https://github.com/stonerl/Thaw/issues/687) |

**Out of update channel** — install manually; Sparkle / `appcast.xml` were not updated.

---

Here is an early preview build of Thaw for macOS 27.

This build is **experimental and not officially supported**, so issues and bugs are expected. We won’t be actively triaging or fixing bug reports for this build yet, but high-level feedback and findings about macOS 27 compatibility are appreciated.

All current functionality is present except for the “always hidden” state. You may also encounter minor UI glitches, and in some cases reordering can take a bit of time to complete (though it generally shouldn’t be excessive). So far this build has only been tested on my own setup as a daily driver since macOS 27 was released, and I’ve tried to address every issue I’ve run into.

[~Download here~](https://github.com/stonerl/Thaw/actions/runs/27930266042/artifacts/7783521840)
[New version here](https://github.com/stonerl/Thaw/actions/runs/28003830057/artifacts/7812060096).

In case the link above expires, you can also get it here [Thaw macOS 27](https://drive.proton.me/urls/1SZX1KYBPM#i88OktVMK6Nc)

Note: I am going to later open a discussion for macOS 27 issues so we start having a backlog for them, just do not report them via issues.

## [2.0.0-rc.1] - 2026-06-16

This is the first release candidate for Thaw 2.0. It brings improved display-switch handling (no unwanted layout re-sorts), per-profile spacing relaunch preferences, and a resolution fix for generic Control-Center-hosted slots.

#### New & Improved

- **Display Switch Stability:** Switching active displays no longer triggers a saved-layout re-sort ([#698](https://github.com/stonerl/Thaw/pull/698)).
- **Spacing Relaunch Preference:** Warn before per-display spacing relaunches; choice saved per profile ([#691](https://github.com/stonerl/Thaw/pull/691)).
- **Control Center Resolution:** Generic slots kept unresolved for marker-pair pass ([#690](https://github.com/stonerl/Thaw/pull/690)).
- **Documentation:** Updated contribution guidelines and install docs.

### New Contributors
* @t4sh made their first contribution in https://github.com/stonerl/Thaw/pull/715

**Full Changelog**: https://github.com/stonerl/Thaw/compare/2.0.0-beta.15...2.0.0-rc.1

## [2.0.0-beta.15] - 2026-06-08

This release adds the ability to assign global hotkeys to individual menu bar items, hardens Control-Center-hosted widget resolution for single-display Macs and title-offset items, prevents system status item clones from corrupting the managed layout, and enhances the onboarding experience.

### New & Improved

- **Per-Item Hotkeys:** Assign global hotkeys to any menu bar item to open its menu. Supports all sections. Electron/Chromium items use AX press. Persisted in profiles. Closes [#148](https://github.com/stonerl/Thaw/issues/148) via [#665](https://github.com/stonerl/Thaw/pull/665).
- **Control Center Resolution by Title:** `HostedItemOwnership.titleIndicatesOwner` resolves title-offset items (AirBuddy, SpamSieve, Cotypist) with title-corroborated 20pt backstop.
- **Single-Display Resolution Hardening:** Phantom reanchored to non-main, shrunk to 640×480, hold 12s→4s, one-strike blacklist. Missing `AXEnabled` treated as enabled. Fixes [#661](https://github.com/stonerl/Thaw/issues/661) via [#667](https://github.com/stonerl/Thaw/pull/667).
- **System Status Item Clone Fix:** Clones matched regardless of namespace; excluded from cache, placement, and move. Fixes [#662](https://github.com/stonerl/Thaw/issues/662) via [#668](https://github.com/stonerl/Thaw/pull/668).
- **Notch Overflow Guard:** Profile layout guarded against unsettled display geometry ([#681](https://github.com/stonerl/Thaw/pull/681)).
- **Deferred Layout for Relaunched Apps:** Layout defers while item re-pairs with window ([#677](https://github.com/stonerl/Thaw/pull/677)).
- **Profile Cache Re-Arm:** Layout cache re-armed when active profile is updated ([#679](https://github.com/stonerl/Thaw/pull/679)).
- **Onboarding:** Enhanced onboarding and app icon management ([#682](https://github.com/stonerl/Thaw/pull/682)).
- **Display Spacing Warning:** Warning callout for differing per-display spacing with WarningColor asset ([#670](https://github.com/stonerl/Thaw/pull/670)).

**Full Changelog**: https://github.com/stonerl/Thaw/compare/2.0.0-beta.14...2.0.0-beta.15

## [2.0.0-beta.14] - 2026-06-02

This beta stabilizes Control Center widget resolution on single-display setups via a virtual display provoker, adds section reorder and filtering to the search panel, introduces a global template for per-display configuration, and enables LCS sorting on notched displays by default.

### New & Improved

- **Single-Display Widget Resolution:** `VirtualDisplayProvoker` creates a headless virtual display to force marker window publication on single-display Macs, resolving Control-Center-hosted widgets (Little Snitch) to their real owning app. Orphans left in place — never relocated. Phantom display excluded from Thaw display enumeration. Fixes [#643](https://github.com/stonerl/Thaw/issues/643) via [#655](https://github.com/stonerl/Thaw/pull/655).
- **Search Panel Reorder:** Sections in search panel reorderable and filterable.
- **Global Display Template:** Global template for per-display configuration defaults.
- **Layout Bar Fixes:** Cross-section drag landing and false move alerts fixed ([#644](https://github.com/stonerl/Thaw/pull/644)).
- **LCS Default:** LCS sorting on notched displays enabled by default.
- **Search UI Polish:** Dividers between rows, increased annotation spacing.
- **Plural-Aware Localization:** Proper plural forms via `String(localized:)` interpolation.
- **Hook Label Width:** Automation labels size to widest localized string. Fixes [#650](https://github.com/stonerl/Thaw/issues/650) via [#653](https://github.com/stonerl/Thaw/pull/653).
- **Localization:** Multiple Crowdin updates.

**Full Changelog**: https://github.com/stonerl/Thaw/compare/2.0.0-beta.13...2.0.0-beta.14

## [2.0.0-beta.13] - 2026-05-27

Hey everyone,

This beta introduces a new `LayoutReconciler` for reliable profile layout application, global and per-profile pre/post apply script hooks, ScreenCaptureKit-based window capture to reduce SkyLight memory leaks, and dozens of stability fixes for profile restoration, notch overflow, third-party widget interactions, and XPC performance.

### New & Improved

- **LayoutReconciler:** Consolidated icon-restore paths into a single phase-based orchestrator. Deferred post-apply cache refresh, divider-duplicate fix for notched full-sort, per-item section-mismatch gate, chevron position persistence, `computeSectionOrder` helper.
- **Pre/Post Apply Script Hooks:** Global and per-profile hooks with configurable timeouts, env vars (`THAW_PROFILE_NAME`, etc.), and non-blocking failures. New Automation UI.
- **ScreenCaptureKit Migration:** Cut SkyLight memory leaks via ScreenCaptureKit-based window capture.
- **XPC Batching:** Single batch request replaces 40-64 concurrent per-window calls - eliminates jetsam kills.
- **Third-Party Widget Deferral:** AX hit-test defers reveal/click/scroll/right-click to notch overlays and pop-up menus. Cancellable delayed right-click reveal.
- **System Menu Bar Auto-Hidden:** Clicks ignored when menu bar auto-hidden offscreen in fullscreen.
- **MarkerPairResolver:** Resolves Control-Center-hosted proxies (Little Snitch) via width-matched marker windows.
- **Notch Overflow Budget Fix:** Removed `NSStatusItemSpacing` double-counting that ejected profile items at default spacing.
- **Cross-Section Apply Fix:** Items destined for always-hidden no longer stranded in hidden.
- **Display Spacing Prompt:** Prompt before applying display spacing. Auto-Switch shows Notch/Disconnected badges.
- **Diagnostic Logging:** XPC logs unified into main app file. Git SHA stamped in Info.plist and log headers.
- **Capture Tolerance:** Bounds overshooting `NSScreen.frame` tolerated instead of dropped.
- **Localization:** Multiple Crowdin updates, non-translatable string exclusion.
- **Profiles:** Forward-compatible snapshot decoding. `useOptionClick`, `useLCSSorting`, `enableOverflow` captured in snapshot.

**Full Changelog**: https://github.com/stonerl/Thaw/compare/2.0.0-beta.12...2.0.0-beta.13

## [2.0.0-beta.12] - 2026-05-12

This release fixes per-display menu bar spacing from triggering unnecessary app relaunch waves on resolution-only screen changes.

### New & Improved

- **Display Spacing Fix:** Per-display menu bar spacing no longer triggers full app relaunch on resolution-only changes (resolution switch, lid open/close, GPU transitions). Active display UUID cached and compared — only actual display changes run the spacing apply. Fixes [#551](https://github.com/stonerl/Thaw/issues/551) via [#569](https://github.com/stonerl/Thaw/pull/569).

**Full Changelog**: https://github.com/stonerl/Thaw/compare/2.0.0-beta.11...2.0.0-beta.12

## [2.0.0-beta.11] - 2026-05-12

This release makes profile decoding forward-compatible with newer settings, fixes Apple Event sender detection on macOS 26 arm64, and adds a companion ThawCtl test app for URI scheme automation.

### New & Improved

- **Profile Forward Compatibility:** Profiles saved before `useDoubleClickToShowAlwaysHiddenSection` was added no longer fail to load. `AdvancedSettingsSnapshot` uses `decodeIfPresent` with defaults. `enableSecondaryContextMenuQuit` now captured in snapshot.
- **Apple Event Sender Detection:** Fixed `extractSenderBundleId` to handle `typeUInt32` (`'magn'`) on macOS 26 arm64 for `keySenderPIDAttr`.
- **ThawCtl:** Added companion test app for `thaw://` URI scheme automation with `thawctl://` callback support.
- **Documentation:** Updated README layout, badges, added Trendshift badge.
- **CI:** Explicit Xcode version in workflow for reproducible builds.

**Full Changelog**: https://github.com/stonerl/Thaw/compare/2.0.0-beta.10...2.0.0-beta.11

## [2.0.0-beta.10] - 2026-05-11

This release introduces adaptive background and tint modes that use the wallpaper's average color, per-screen adaptive colors for multi-monitor setups, robust wake-from-sleep color handling, and fixes for always-hidden section display and Thaw Bar flashing on multi-monitor.

### New & Improved

- **Adaptive Background & Tint:** New adaptive mode uses average wallpaper color as menu bar background or shape tint. Respects opacity sliders. Capture retries at launch (1s × 10).
- **Per-Screen Adaptive Colors:** Each display captures own wallpaper color via `averageColors[displayID]`. Overlay panels use owning screen's color.
- **Wake-from-Sleep Stability:** Colors cached before sleep, restored immediately on wake — no white flash. Staggered recapture at 0.5/2/5/10s for slow external displays. Polls until color settles instead of fixed 8s delay.
- **Always-Hidden Section Fix:** Only shows when mouse and active menu bar are on same display.
- **Thaw Bar "No Items" Flash Fix:** 1s grace period after `show()` on screen parameter change. 500ms settle delay before background cache recache.
- **Memory & Concurrency:** Added `deinit` cleanup, weak self guards, restored `HIDEventManager` deinit, `healthCheckTimer` cleanup, removed `memoryMonitoringTask`, Swift 6 concurrency fixes.
- **Game Mode Support:** `GamePolicyAgent` treated as transient non-hideable system item.
- **Blocked-Item Recovery:** Restricted to moves adjacent to hidden divider only.
- **Control Center:** Refined transient item handling in move logic.
- **Localization:** Crowdin updates.

**Full Changelog**: https://github.com/stonerl/Thaw/compare/2.0.0-beta.9...2.0.0-beta.10

## [2.0.0-beta.9] - 2026-05-10

This release fixes overlay panels drifting to the wrong display during fullscreen, adds a Restart Thaw menu item via Option-key alternate and a Support menu item and treats transient Control Center Live Activities as non-hideable.

### New & Improved

- **Overlay Fullscreen Fix:** Removed `.moveToActiveSpace` from overlay and probe windows — panels stay pinned to their owning display. Removed stale fullscreen checks from `validate()`.
- **Restart Thaw Menu Item:** Hold ⌥ Option in the context menu to change "Quit Thaw" → "Restart Thaw".
- **Support Menu Item:** Added localized Support menu item for help resource access.
- **Live Activities as Non-Hideable:** Transient Control Center Live Activities excluded from search, move/layout, and profile width budgeting.
- **DMG Packaging:** Added `create-dmg` step with background image, fixed paths and icon handling.
- **CI Improvements:** Notarytool timeout removed, formatting fixes, skip Crowdin updates, permission fixes.
- **Issue Triage Workflow:** Repos guard policy added, `min-integrity` lowered, automatic maintainer assignment removed.
- **Documentation:** Updated macOS requirements, security policy, contributing guidelines, Code of Conduct.
- **Code Clarity:** Enhanced comments in MenuBar and Permissions views, removed noisy debug log.
- **Localization:** Crowdin updates.

**Full Changelog**: https://github.com/stonerl/Thaw/compare/2.0.0-beta.8...2.0.0-beta.9

## [2.0.0-beta.8] - 2026-05-07

This release introduces a fully configurable menu bar background (solid, gradient, or glass with dynamic light/dark support), per-display menu bar spacing, a new glass effect for shapes, and a double-click Thaw icon gesture to show the always-hidden section.

### New & Improved

- **Configurable Background:** Choose between none, solid, or gradient with dynamic light/dark appearance. Full colour, opacity, border, and shadow controls. Background fills full area, shape tint clips on top. Removed implicit black@0.2 tint with `.noTint` + shape.
- **Glass Effect:** New `.regular` glass via `NSGlassEffectView` for background and shape tint. Configurable style picker (Regular/Clear). Borders and shadows work with glass. Fixed clear glass variant and height mismatch.
- **Per-Display Menu Bar Spacing:** `itemSpacingOffset` moved from `GeneralSettings` to per-display `DisplayIceBarConfiguration`. Spacing slider lives on Displays pane. `KnownDisplay` cache preserves disconnected display settings. Dynamic apply with settling, relaunch recovery. **Breaking schema change** - existing profiles fall back to active display's value.
- **Double-Click Thaw Icon:** New setting to show always-hidden section via double-click on Thaw icon. Works alongside option-click toggle.
- **Context Menu Quit:** Added "Quit" option to secondary context menu.
- **Profile Restoration Reliability:** `applyProfileLayout` awaits startup settling. `cacheItemsRegardless` detects relaunched apps by `windowID` change and triggers re-sort.
- **Overlay Panel Retry:** 500ms retry when Window Server unsettled (display connect/disconnect).
- **Space Switch Polish:** Removed fade animation flicker. Axis check distinguishes Mission Control from space swipes.
- **CI & Release:** Signing, archiving, notarization steps added. Composite actions extracted ([#530](https://github.com/stonerl/Thaw/pull/530)).
- **Code Quality:** SonarCloud issues addressed ([#525](https://github.com/stonerl/Thaw/pull/525)).
- **Localization:** Multiple Crowdin updates, removed stale strings and hardcoded "Thaw".

**Full Changelog**: https://github.com/stonerl/Thaw/compare/2.0.0-beta.7...2.0.0-beta.8

## [2.0.0-beta.7] - 2026-05-03

This beta introduces a new Notch shape kind that splits at the physical display notch, adds tint opacity control and Thaw Bar left/right alignment options, fixes a permanent menu bar height cache poison that silently dropped clicks, and eliminates memory growth on multi-monitor hotplug.

### New & Improved

- **Notch Shape:** New `.notch` shape kind that splits the menu bar background at the physical display notch. Full 4-corner end cap control via the split shape picker. Behaves as full on non-notched displays.
- **Thaw Bar Alignments:** New `leftAligned` and `rightAligned` location options with 24px edge padding.
- **Notch Margin Slider:** Adjustable notch margin (0–15px) shown as spacers in shape preview.
- **Tint Opacity:** New opacity slider (0–1, default 0.2). Tints rendered behind menu bar at user-chosen opacity. `.noTint` only draws when shape is active.
- **Menu Bar Height Cache Fix:** Removed permanent `-1` sentinel that poisoned height cache. Failed queries retry after 500ms. Fixes empty clicks, Thaw Bar dimensions, dual-monitor asymmetry.
- **Stale Cache Verification:** Menu bar item bounds verified against window server. Temporary system items (recording, mic, camera) no longer leave stale false-positive entries.
- **Memory Growth Eliminated:** Fixed retain cycle in live refresh loop, removed duplicate image entries post-reconnect, fixed LRU eviction, force cache rebuild on display connect/disconnect.
- **Default Icon Refresh Rate:** Increased from 2fps to 10fps.
- **Localization:** Updated translations via Crowdin.
-
**Full Changelog**: https://github.com/stonerl/Thaw/compare/2.0.0-beta.6...2.0.0-beta.7

## [2.0.0-beta.6] - 2026-05-02

This beta rewrites section restoration for predictable item placement, removes the complex `DynamicItemOverrides` namespace fallback in favour of a deterministic approach, fixes icon cache corruption during layout moves, and improves Thaw Bar resizing and grid layout.

### New & Improved

- **Section Restoration Rewrite:** Removed `DynamicItemOverrides` namespace fallback. Every item now follows a single deterministic path: `baseIdentifier` match → saved section or keep macOS placement. Removed `restoreSavedItemOrder` - items land at section boundary after restart and can be cmd-dragged to position.
- **Restart Position Stability:** Unsaved items no longer pulled to visible on restart - macOS placement is respected. Blocked items (`x = -1`) are skipped in classification instead of forced to hidden. `saveSectionOrder` guards against transient `x = -1` bounds.
- **Icon Cache Stability:** `refreshImages` guarded against recent moves and layout resets. `failedCaptures` wrapped with `OSAllocatedUnfairLock` for Swift 6 thread safety.
- **Thaw Bar Dynamic Resize:** Panel resizes dynamically when content changes. Thaw Bar honors item spacing offset; pill shape matches container shape.
- **Thaw Bar Grid:** Per-column max widths and single-row natural sizing enforced correctly.
- **Conflicting Apps:** Added Barbee and SaneBar to known conflicting apps list.
- **UI Strings:** Replaced hardcoded "Thaw" with `Constants.displayName` in 7 user-facing strings. Separated leading space from " Copy" for cleaner translations.
- **Localization:** Updated Czech and Polish translations, added missing translation comments, multilingual updates.

**Full Changelog**: https://github.com/stonerl/Thaw/compare/2.0.0-beta.5...2.0.0-beta.6

## [2.0.0-beta.5] - 2026-05-01

This beta brings a complete overhaul of menu bar item spacing, a new macOS 26-style app icon, and a new `thaw://` authorization endpoint.

### New & Improved

- **macOS 26 App Icon:** Redesigned app icon in the new macOS 26 visual style. Big thanks to @JamesLautner
- **Menu Bar Item Spacing Overhaul:** Replaced continuation+Combine with polling (no hang risk), fixed Swift 6 data races, added rollback on partial failure, increased force-terminate delay 1s → 5s, always writes explicit defaults, includes Control Center in the task group, clamps and rounds `itemSpacingOffset`, syncs the slider on external changes, and removed the BetaBadge — spacing is now stable.
- **60-Second Cache Polling:** Lightweight periodic cache check detects late-registering items from background-only apps that never become frontmost.
- **Cache Serialization:** Serialized `cacheItemsRegardless` via a `CacheGate` actor to prevent concurrent-call races during item moves.
- **Stale PID Protection:** PID stability checks prevent stale AX `sourcePID` resolution from assigning wrong namespaces after cmd-drag layout moves.
- **Authorization Endpoint:** New `thaw://authorize` endpoint triggers the auth dialog without a settings operation. `thaw://get?key=version` returns app version + build number without whitelist auth. User-facing alerts use plain language and translatable strings.
- **Profiles Polish:** Localized Profiles strings and redesigned Focus mode footer as a `CalloutBox`.
- **UI Refinements:** Limited settings sidebar to 220px, tightened IceGroupBox paddings, restructured whitelist header, added 24pt spacing between tint/border groups in dynamic mode, adjusted editor panel height.
- **Option-Click Always-Hidden:** Option-click now correctly toggles the always-hidden section instead of being silently swallowed.
- **Thaw Bar Height:** Removed the `min()` clamp on non-notched displays — macOS 26 can report a legitimate 30pt menu bar; trusting live measurement.
- **Hold to Preview:** Overlay panels created on-demand when preview is active, even without visual settings.
- **Localization:** Updated multilingual translations, cleaned stale strings, enabled base internationalization.

**Full Changelog**: https://github.com/stonerl/Thaw/compare/2.0.0-beta.4...2.0.0-beta.5

## [2.0.0-beta.4] - 2026-04-30

This release introduces configurable Thaw Bar layouts (horizontal, vertical, grid), removes wallpaper capture overhead for faster shape updates, and improves menu-bar stability after fast restores.

### New & Improved

- **Thaw Bar Layout Options:** Choose between horizontal, vertical, or grid layout for the Thaw Bar. Padding is only applied to the last row when multiple rows exist, and loading spinners have been replaced with plain text for a cleaner look.
- **Performance:** Removed wallpaper capture and adopted a fast-first `settledCount` approach for both shape loops, significantly speeding up shape updates.
- **Menu Bar Stability:** Fixed icon drift during fast restore with unresolved `sourcePIDs`. Clamped menu bar height on non-notched displays for multi-monitor DPI safety.
- **Localization:** Updated multilingual translations.

### Known issues

- In multi monitor setups, the MenuBarListener sometimes fails to detect menubar clicks on external monitors.

**Full Changelog**: https://github.com/stonerl/Thaw/compare/2.0.0-beta.3...2.0.0-beta.4

## [2.0.0-beta.3] - 2026-04-29

Hello everyone,

This beta brings **Swift 6 strict concurrency** adoption, eliminates several deadlocks and race conditions, improves menu-bar item tracking after sleep and app launches, and polishes the layout bar and slider UI.

### Improvements & Fixes

- **Swift 6 Concurrency:** Adopted strict concurrency mode throughout the codebase, modernized Swift 5 patterns, migrated `NSLock` to `OSAllocatedUnfairLock`, and fixed a double-continuation resume in `FrameCaptor.waitForFrame`.
- **Menu-Bar Tracking:** Re-checks the item cache after app launches to sort late-arriving items, confirms the cache across two reads before updating the trailing shape, hoists `displayID` before background Tasks to avoid off-main `NSScreen` access, and suppresses the "Unable to display" flash while the image cache is still loading.
- **Startup & Auto-Relocation:** Gated startup settling on `sourcePID` resolution instead of a timer alone, suppressed auto-relocation during the settling period, prevented a relocation cascade when items transiently lose their section, and stopped placed items from moving back to the new-items section.
- **Rehide & Semaphore Stability:** Fixed a deadlock caused by signal races combined with clone-window storms, and prevented `appHasVisiblePopup` from spinning when switching apps.
- **Ice Bar & Input:** Synthetic clicks no longer trigger hot corners and restore the cursor more reliably; fixed toggle/close behaviour for the always-hidden section with the Thaw Bar; option/ctrl clicks on empty space and the Ice icon work correctly again; restored double-click to expand the always-hidden section; and the Ice Bar now uses a live `windowID` check after sleep.
- **Layout Bar & Slider UI:** Shows more available space in the visible layout bar when a notch is present, increased the notch indicator corner radius, corrected the notch indicator size and position in layout settings, moved scales back to the top of sliders, set the scale length to 6 px, and updated slider label opacity. Also updated CompactSlider to v2.1.0 and added an option to disable icon refresh (0 FPS).
- **Restore:** Section order is now persisted in-session and cross-pass app relaunches are detected correctly.
- **Localization:** Updated multilingual translations.

### Known issues

- In multi monitor setups, the MenuBarListener fails sometime fails to detect menubar clicks on external monitors.

### New Contributors
* @beantownbytes made their first contribution in https://github.com/stonerl/Thaw/pull/482

**Full Changelog**: https://github.com/stonerl/Thaw/compare/2.0.0-beta.2...2.0.0-beta.3

## [2.0.0-beta.2] - 2026-04-25

### Changed

- refactor: replace timer/sleep races with event-driven panel-close and… by @stonerl in https://github.com/stonerl/Thaw/pull/453
- [LOCALIZATION] Update of CS translation by wizaard based on 2.0.0 BETA1 by @wizaard88 in https://github.com/stonerl/Thaw/pull/454
- New Crowdin updates by @stonerl in https://github.com/stonerl/Thaw/pull/459
- New Crowdin updates by @stonerl in https://github.com/stonerl/Thaw/pull/460

### Fixed

- fix(menu-bar): cache raw AX frame and remove ignoreNotch variant by @stonerl in https://github.com/stonerl/Thaw/pull/446
- fix: use .contains() for modifier flag checks in ControlItem by @stonerl in https://github.com/stonerl/Thaw/pull/450
- fix: hide dependent settings when always-hidden section is disabled by @stonerl in https://github.com/stonerl/Thaw/pull/451
- fix(icebar): make item reveal reliable under CPU load by @stonerl in https://github.com/stonerl/Thaw/pull/452
- fix: remove Material-era opacity reductions for Glass design by @stonerl in https://github.com/stonerl/Thaw/pull/457
- fix(rehide): prevent permanent semaphore saturation from stuck items by @stonerl in https://github.com/stonerl/Thaw/pull/461

**Full Changelog**: https://github.com/stonerl/Thaw/compare/2.0.0-beta.1...2.0.0-beta.2

## [2.0.0-beta.1] - 2026-04-24

Hey everyone,

This beta brings native macOS 26 (Tahoe) support, adopting the new Liquid Glass design language throughout the app. It also expands the thaw:// Settings URI scheme for advanced automation.

> [!IMPORTANT]
> This release requires macOS 26. Users on macOS 14 or 15 will not receive this update and will remain on `1.3.0-beta.1`. For more information see here #427

### New

- macOS 26 (Tahoe) Support: Thaw is now built exclusively for macOS 26. The minimum deployment target has been raised accordingly.
- Liquid Glass Design: Adopted the new macOS 26 Liquid Glass design system across the main interface, Settings window, and Search window.
- Settings URI — Write Support: Change Thaw settings programmatically via the thaw:// URI scheme. Supports boolean, double, enum, and per-display settings with live UI sync.
- Settings URI — Read Support: Read the current value of any Thaw setting via URI, enabling external tools and scripts to query your configuration.
- Version Copy Button: Click the version number in About settings to copy it to the clipboard.

### Improvements & Fixes
- Show-on-Click Reliability: Overhauled the click-guard logic to close race conditions on dual-display setups, double-click reveal, second-click edge cases, and spurious startup rearms.
- App Menu Click-Through: Refined detection of application menu regions to more accurately distinguish AX states, reducing false triggers when clicking File, Edit, View, and other app menus.
- Hover & Rehide Stability: Hardened hover rearm retries near the menu bar and improved smart rehide detection to prevent items staying visible longer than intended.
- Startup Performance: Reduced menu-bar scan overhead at startup and improved source PID resolution with a timeout to prevent indefinite blocking.
- Layout Bar Colors: Layout bar preview, badge, and notch indicator now correctly adapt colors to the active display's menu bar background, including on notched MacBooks.
- Settings Sidebar: Sidebar width now auto-fits its content, icons are correctly sized, and the selected item foreground color is correct for inactive windows.
- Settings Window: Removed fixed maximum size constraints so the window resizes freely.
- Reset Layout Drag Errors: Increased the delay after Reset Layout to prevent drag errors immediately following a reset.
- Tooltip Layout: Fixed tooltip panel positioning with an improved label container layout.
- Thaw Bar Foreground Color: Fixed brightness detection ignoring its screen parameter, causing incorrect icon colors on secondary displays.
- Screen Capture: Replaced deprecated CGWindowList API with SkyLight private API for more reliable empty-space hit testing and background capture.
- App Termination Handling: App termination replies are now handled asynchronously with a single-attempt scope to avoid hangs.
- Presentation Mode: Fixed a crash when the app menu frame was nil during presentation mode calculation.
- New Items Badge: Profile capture now correctly saves the new items badge position.
Full Changelog: https://github.com/stonerl/Thaw/compare/1.3.0-beta.1...2.0.0-beta.1

### New Contributors
* @Skyearn made their first contribution in https://github.com/stonerl/Thaw/pull/406

**Full Changelog**: https://github.com/stonerl/Thaw/compare/1.3.0-beta.1...2.0.0-beta.1

### Donations

If you find Thaw useful and want to support its further development, consider throwing a coin in my hat.

* GitHub Sponsor: https://github.com/sponsors/stonerl
* Patreon: https://www.patreon.com/c/stonerl

## [1.3.0-beta.1] - 2026-04-16

Hello everyone,

This beta introduces Settings Profiles, allowing you to save and switch between different Thaw configurations. Profiles can be triggered automatically based on display changes or Focus modes.

### New

- Settings Profiles: Save your entire Thaw configuration as a profile and switch between different setups instantly. Perfect for different workflows, presentations, or multi-monitor configurations.
  - Create, duplicate, rename, and delete profiles
  - Import and export profiles for backup or sharing
  - Update existing profiles with current layout, configuration, or both

  Thanks to @nightah for implementing this feature!
- Display Auto-Switch: Assign profiles to specific displays. When you connect a display, its associated profile is automatically applied.
- Focus Mode Integration: Switch profiles automatically when Focus modes activate. Add Thaw as a Focus Filter in System Settings → Focus → Mode → Focus Filters to assign a profile to each Focus mode. The previous profile is restored when the Focus mode deactivates.
- Profile Hotkeys: Assign keyboard shortcuts to quickly switch between your favorite profiles.
- New Items Badge: A draggable badge in Menu Bar Layout settings lets you control exactly where newly detected menu bar items will appear. Drag it to position new items to the left or right of existing icons.
- Option-Click Always Hidden: New setting to toggle the always-hidden section with Option+click on empty menu bar space.
- Icon Overflow for Notch Displays: Improved handling of menu bar items on MacBooks with a notch. Items that would be hidden behind the notch are now properly managed.
- Keep Search Toggle: New toggle in the search panel to preserve the search text when reopening.

### Improvements & Fixes
- App Menu Click-Through: Fixed issues where clicking on application menus (File, Edit, View, etc.) would incorrectly trigger Thaw's show-on-click, hover, or scroll behaviors. App menus now work reliably.
- Event Monitor Recovery: Added automatic health checking and recovery for background event monitors. If mouse click detection stops working, Thaw now recovers automatically instead of requiring a restart.
- Layout Bar Stability: Fixed items disappearing from the layout bar during reorder operations, after reset, or when new items appear.
- New Items Badge Position: Fixed the badge jumping to incorrect positions when reordering other items around it. The badge now stays in place unless explicitly dragged.
- Search Panel Focus: Fixed the text field sometimes not receiving focus when opening the search panel via keyboard shortcut.
- IceBar Click Responsiveness: Reduced click jitter when interacting with items in the IceBar.
- Context Menu Size: Fixed context menus appearing unexpectedly large in certain situations.
- Secondary Display Support: Fixed right-click context menu not working on secondary displays.

### New Contributors
* @SAY-5 made their first contribution in https://github.com/stonerl/Thaw/pull/362
* @looseboy made their first contribution in https://github.com/stonerl/Thaw/pull/360
* @gitmichaelqiu made their first contribution in https://github.com/stonerl/Thaw/pull/305
* @kylewhirl made their first contribution in https://github.com/stonerl/Thaw/pull/349
* @exsesx made their first contribution in https://github.com/stonerl/Thaw/pull/387

**Full Changelog**: https://github.com/stonerl/Thaw/compare/1.2.0-rc.4...1.3.0-beta.1

## [1.2.0] - 2026-04-13

**The Global Thaw**

Hey everyone,

Finally, `1.2.0` is here.

**Important Note:** This release introduces significant improvements to how Thaw manages menu bar item positions. Your icon positions are now automatically saved and restored across app restarts. If you experience any issues with icon positioning, use the new **"Reset Thaw"** button in Advanced Settings to restore default settings.

### New

- **Icon Position Persistence:** Thaw now remembers where your icons belong! Menu bar items are automatically restored to their saved sections (visible, hidden, or always-hidden) after app restarts or system reboots. No more manually re-sorting icons after logging in.
- **Custom Menu Bar Item Names:** You can now rename any menu bar item with a custom name of your choice. Perfect for giving cryptic icons a more descriptive label or organizing your workflow.
- **Menu Bar Item Tooltips:** Enable optional tooltips that appear when hovering over items in the actual menu bar. Know exactly what each icon represents without clicking.
- **URL Scheme Support:** External tools like Raycast can now control Thaw via the `thaw://` URL scheme. Toggle the Thaw Bar, show or hide sections, and more using custom commands.
- **Manual Application Menu Toggle:** Added a configurable hotkey to manually toggle application menu visibility. Useful for presentations or when you need the full menu bar width temporarily.
- **Thaw Bar Hover Highlight:** Items in the Thaw Bar now show a subtle background highlight when hovered, making it easier to identify which item you're about to interact with.
- **Conflicting Apps Detection:** Thaw now detects when other menu bar management apps are running and warns you about potential conflicts.
- **Per-Display Settings:** Configure "Always show hidden items" and Thaw Bar positioning independently for each connected display. Perfect for multi-monitor setups with different screen sizes or notch configurations.
- **Reset Thaw Button:** A new reset button in Advanced Settings allows you to quickly restore all Thaw settings to their defaults when troubleshooting.

### Improvements & Fixes
- **Startup Stability:** Fixed the "icon parade" issue where icons would continuously shuffle for 10–15 seconds after login. Thaw now enters a settling period during startup to prevent premature rearrangement.
- **Multi-Icon App Support:** Apps with multiple menu bar icons (such as Stats, Hammerspoon, and iStat Menus) now stay properly organized in their designated sections instead of gradually migrating to the visible menu bar over time.
- **Memory Optimizations:** Reduced memory usage by skipping wallpaper captures when not needed, clearing stale caches when displays disconnect, and adding proper cleanup for background tasks.
- **Performance:** Throttled mouse event handling and optimized image caching to reduce CPU usage and improve overall responsiveness.
- **Privacy:** Added screen recording permission checks for tooltips and search features. These options are now hidden in settings when permissions are not granted.
- **Visual Refinements:** Improved IceBar item highlight sizing with better corner radius and padding for a more modern appearance that matches macOS design language.
- **Same-Icon Differentiation:** Fixed a bug where different apps sharing the same icon were conflated. Thaw now correctly identifies items by their source application.
- **Auto-Rehide Reliability:** Improved the rehide logic to prevent items from staying visible longer than intended, and fixed cases where manual hide states could get stuck.

### Localization
Thaw now supports **17 languages** with 100% completion! A huge thank you to our community contributors:
| Language | Contributor |
|----------|-------------|
| Bahasa Indonesia | @volcbs |
| Čeština (Czech) | *new in this release* |
| Deutsch | @Mutzki13 |
| Español | @diazdesandi |
| Français | @PipaCode |
| Italiano | @zichichi |
| 日本語 (Japanese) | *new in this release* |
| 한국어 (Korean) | @YuriHan |
| Magyar (Hungarian) | @johnnybakucz |
| Nederlands (Dutch) | @SeBr28 |
| Polski (Polish) | *new in this release* |
| Português (Brasil) | *new in this release* |
| Русский (Russian) | *new in this release* |
| 简体中文 (Chinese Simplified) | @PiCpo |
| 正體中文 (Chinese Traditional) | @7a6163 |
| ภาษาไทย (Thai) | @priesdelly |
| Türkçe (Turkish) | *new in this release* |

### New Contributors
* @MarcoTerzulli made their first contribution in https://github.com/stonerl/Thaw/pull/132
* @dyxushuai made their first contribution in https://github.com/stonerl/Thaw/pull/136
* @afuno made their first contribution in https://github.com/stonerl/Thaw/pull/139
* @mrclrchtr made their first contribution in https://github.com/stonerl/Thaw/pull/156
* @josericardo-fo made their first contribution in https://github.com/stonerl/Thaw/pull/152
* @CamilleGuillory made their first contribution in https://github.com/stonerl/Thaw/pull/168
* @FormalSnake made their first contribution in https://github.com/stonerl/Thaw/pull/210
* @musanmaz made their first contribution in https://github.com/stonerl/Thaw/pull/214
* @william-laverty made their first contribution in https://github.com/stonerl/Thaw/pull/221
* @coygeek made their first contribution in https://github.com/stonerl/Thaw/pull/238
* @Tsingv made their first contribution in https://github.com/stonerl/Thaw/pull/241
* @alinco8 made their first contribution in https://github.com/stonerl/Thaw/pull/253
* @exsesx made their first contribution in https://github.com/stonerl/Thaw/pull/256
* @weihaog1 made their first contribution in https://github.com/stonerl/Thaw/pull/263
* @IraXu made their first contribution in https://github.com/stonerl/Thaw/pull/269
* @SeBr28 made their first contribution in https://github.com/stonerl/Thaw/pull/290
* @wizaard88 made their first contribution in https://github.com/stonerl/Thaw/pull/294

**Full Changelog**: https://github.com/stonerl/Thaw/compare/1.1.0...1.2.0

## [1.2.0-rc.4] - 2026-03-23

### Changed

- Finalized Czech (CS) language updates for the 1.2.0 release cycle.
- Updated Turkish (TR) translations.

### Fixed

- Reverted "Robust Icon Position Handling" to address regression issues and maintain system stability while the feature is further refined.

**Full Changelog**: https://github.com/stonerl/Thaw/compare/1.2.0-rc.3...1.2.0-rc.4

## [1.2.0-rc.3] - 2026-03-22

Hey everyone,

This release introduces significant under-the-hood improvements to icon management and display logic, specifically targeting "icon jumping" and MacBook notch compatibility.

### New Features & Improvements

* **Robust Icon Stability:** Implemented a multi-layered tracking system including an InstanceTracker for multi-item apps, PositionConsensus (requiring 3 consistent observations), and an AppLifecycleTracker to defer restoration during app initialization.
* **Intelligent Notch Handling:** Added logic to calculate if items fit in available space, automatically falling back to the Thaw Bar if items would be hidden by the notch or screen edge.
* **Overlay Precision:** Added an `ignoreNotch` parameter for the overlay panel to allow the split shape to render correctly even when the menu extends past the notch.

### Fixed

* **Click Detection:** Fixed an issue where clicking newly-shown hidden items would incorrectly hide the section immediately.
* **Window Server Fallback:** Added a fallback to query the Window Server directly when the cache misses, ensuring clicks on newly-visible items are correctly detected.
* **Startup Reliability:** Resolved a bug where the IceBar could appear over the menu bar during startup by using sensible height estimates (37pt for notched, 22pt for standard).
* **Modifier Key Precision:** Captured `modifierFlags` directly from the event instead of global state, fixing intermittent issues with Option-clicking the Always-Hidden section.
* **Overlay Visibility:** Fixed panel visibility at launch by consistently initializing at the `.statusBar` level.
* **Stuck Item Recovery:** Added a mechanism to automatically detect and recover menu items that become stuck at invalid coordinates `(x = -1)`.
* **Cache Management:** Improved width calculations with a `bypassCache` parameter to prevent showing the previous application's menu width when switching apps.

### Localization & Documentation

* **Translations:** Updated Czech (CS) translations based on the 1.2.0 RC1 baseline.
* **Documentation:** Added official contributing guidelines and updated `CONTRIBUTING.md`.

**Full Changelog**: https://github.com/stonerl/Thaw/compare/1.2.0-rc.2...1.2.0-rc.3

### Donations

If you find Thaw useful and want to support its further development, consider throwing a coin in my hat.

* GitHub Sponsor: https://github.com/sponsors/stonerl
* Patreon: https://www.patreon.com/c/stonerl

## [1.2.0-rc.2] - 2026-03-19

Hey everyone,

this is the second release candidate, primarily fixing bugs.

### Improvements & Fixes

* **Fixed Icon "Jumping":** Resolved an issue where icons in hidden sections would unexpectedly relocate when other apps (like OneDrive) launched and triggered a macOS windowID refresh.
* **Identity-Based Relocation:** Refined logic to only relocate items if their identity (namespace and title) is truly unknown, rather than moving them based on new windowIDs.
* **Improved Multi-Icon Protection:** Enhanced protection for apps with multiple icons (e.g., Stats, Hammerspoon) by extracting bundle IDs directly from the saved section order.
* **Section Persistence:** Fixed a bug where protection failed for multi-icon apps when the "always-hidden" section was disabled.

**Full Changelog**: https://github.com/stonerl/Thaw/compare/1.2.0-rc.1...1.2.0-rc.2

### Donations

If you find Thaw useful and want to support its further development, consider throwing a coin in my hat.

* GitHub Sponsor: https://github.com/sponsors/stonerl
* Patreon: https://www.patreon.com/c/stonerl

## [1.2.0-rc.1] - 2026-03-18

### Improvements & Fixes
* **Multi-Icon App Protection:** Fixed a regression where apps with multiple icons (such as Stats, Hammerspoon, and iStat Menus) would unintentionally migrate from hidden sections to the visible menu bar over time.
* **Smart Relocation Refinement:** Improved logic to skip auto-relocation for items with explicitly saved sections, ensuring multi-icon apps stay in their designated areas while still allowing new items to relocate.
* **Compatibility Update:** Removed **TopNotch** from the conflicting apps list as it only modifies menu bar appearance and does not provide menu bar icon handling.
* **Code Quality:** Fixed unused variable warnings in the application termination process and performed general string cleanup.

### Localization
* **New Language:** Added support for **Czech (cs)**.
* **Updated Translations:**
    * **Thai & Indonesian:** Added more Thai translations and revised Indonesian strings for consistency.
    * **Chinese:** Extensive corrections for Simplified Chinese and improved clarity for menu bar display settings.
    * **Spanish:** Fixed errors and added missing strings in `Localizable.xcstrings`.
    * **Additional Updates:** Korean (ko), Italian (it), and Dutch translations have been updated with missing entries.

### New Contributors
* @SeBr28 made their first contribution in https://github.com/stonerl/Thaw/pull/290
* @wizaard88 made their first contribution in https://github.com/stonerl/Thaw/pull/294

**Full Changelog**: https://github.com/stonerl/Thaw/compare/1.1.99-beta.11...1.2.0-rc.1

### Donations

If you find Thaw useful and want to support its further development, consider throwing a coin in my hat.

* GitHub Sponsor: https://github.com/sponsors/stonerl
* Patreon: https://www.patreon.com/c/stonerl

## [1.1.99-beta.11] - 2026-03-15

Hello everyone,

this is beta.11 which mainly updates translations and fixes some issues with disappearing icons.

### Menu Bar Reliability & Performance
This beta focuses on resolving issues with third-party menu bar items becoming "blocked" or invisible, alongside performance optimizations to reduce interaction latency.

### Improvements & Fixes

* **Menu Bar Recovery:** Fixed a critical issue where third-party items (like SwiftBar) could become permanently invisible by getting stuck at off-screen coordinates.
* **Smart Relocation:** Removed bundle ID pinning to ensure new menu bar items are automatically moved to the visible section instead of being blocked in hidden sections.
* **Termination Cleanup:** The app now automatically restores items stuck in a "blocked" state (x=-1) to the visible section upon quitting.
* **Move Validation:** Added background safeguards to detect and recover items that fail to move correctly into hidden sections.
* **Reduced Latency:** Optimized click interactions by removing redundant window lookups, eliminating unnecessary Window Server IPC round-trips.

### Localization

* **Updated:** Russian, Traditional Chinese, Simplified Chinese, Brazilian Portuguese, French, and German.

### New Contributors
* @IraXu made their first contribution in https://github.com/stonerl/Thaw/pull/269

**Full Changelog**: https://github.com/stonerl/Thaw/compare/1.1.99-beta.10...1.1.99-beta.11

### Donations

If you find Thaw useful and want to support its further development, consider throwing a coin in my hat.

* GitHub Sponsor: https://github.com/sponsors/stonerl
* Patreon: https://www.patreon.com/c/stonerl

## [1.1.99-beta.10] - 2026-03-13

Hello everyone,

This beta focuses on modernizing the **Thaw Bar** visual experience to align with the latest macOS design language and significantly improving memory management during display changes.

### New

#### Thaw Bar & Visuals

- **Hover Highlights**: Added a subtle rounded-rectangle background highlight when hovering over items in the Thaw Bar (IceBar).

### Changed

#### Thaw Bar & Visuals

- **Adaptive Styling**: Highlight colors now derive from actual menu bar brightness for perfect integration across all system appearances.
- **Modern Geometry**: Increased the hover backdrop corner radius from 4pt to 16pt to better match macOS 26's design language.
- **Improved Interaction**: Increased backdrop opacity and implemented `NSTrackingArea` in `IceBarItemClickView` for more reliable mouse enter/exit detection.

#### Memory & Performance

- **Wallpaper Optimization**: The app now skips periodic wallpaper captures when `showsMenuBarBackground` is enabled to reduce memory overhead.
- **Aggressive Cleanup**: Added logic to clear stored wallpapers, `windowImage`, and `averageColorInfo` when panels are hidden or displays are changed.

#### Permissions & Localization

- **Privacy Controls**: Screen recording permissions are now checked before enabling tooltips or search features; relevant controls are hidden if permissions aren't granted.
- **I18n**: Updated the **German** translation.

### Fixed

#### Thaw Bar & Visuals

- **Refined Sizing**: Added vertical padding to the hover backdrop so it no longer extends the full height of the menu bar, matching the Ice icon's native appearance.

#### Memory & Performance

- **Display Stability**: Fixed memory growth issues by cleaning up caches for disconnected displays, specifically `menuBarHeightCache` and `applicationMenuFrameCache`.
- **Leak Fixes**: Resolved a notification observer leak in the Search Panel and improved the `close()` routine to release all retained states.

### New Contributors
* @weihaog1 made their first contribution in https://github.com/stonerl/Thaw/pull/263

**Full Changelog**: https://github.com/stonerl/Thaw/compare/1.1.99-beta.9...1.1.99-beta.10

### Donations

If you find Thaw useful and want to support its further development, consider throwing a coin in my hat.

* GitHub Sponsor: https://github.com/sponsors/stonerl
* Patreon: https://www.patreon.com/c/stonerl

## [1.1.99-beta.9] - 2026-03-11

Hello everyone,

here is beta 9, and we hopefully have finally fixed the random icon shuffling.

### New

**URL Scheme Integration**
* Registered `thaw://` URL events for external tools (like Raycast) and added support to handle Apple Events.
* Added CFBundleURLTypes to fully implement URL scheme handling for specific actions.

### Improvements & Fixes

**Startup & Layout Stability**
* Introduced a startup settling period to suppress restore operations during login.
* Prevented the "icon parade" consisting of 10–15 seconds of continuous icon shuffling caused by app launch notifications.
* Prevented a race condition during app restarts that could reverse icon order by stopping concurrent cache calls from saving the incorrect order.
* Prevented multiple concurrent settling tasks from accumulating on setup re-entry by properly tracking and cancelling in-flight tasks.
* Ensured user-initiated layout resets immediately end the settling period.
* Fixed a bug where different apps sharing the same icon were conflated into a single logical item.
* Resolved issues where clicking triggered the wrong item or caused auto-hide to twitch by comparing the `instanceIndex` to differentiate items.

**Visual & UI Refinements**
* Aligned the control item hover background.
* Fixed an issue where `isManuallyHidingApplicationMenus` could get stuck if a hide action failed.

### Under-the-Hood

**Performance**
* Optimized menu bar height retrieval with a new caching mechanism to fix cursor sweep IPC floods.
* Ensured stale menu bar height caches are cleared on reset.

**Architecture**
* Removed redundant `Sendable` conformance that is already implicitly synthesized by the Swift compiler.

**Localization**
* Added a new Japanese translation and updated the Italian translation.

### New Contributors
* @Tsingv made their first contribution in https://github.com/stonerl/Thaw/pull/241
* @alinco8 made their first contribution in https://github.com/stonerl/Thaw/pull/253
* @exsesx made their first contribution in https://github.com/stonerl/Thaw/pull/256

**Full Changelog**: https://github.com/stonerl/Thaw/compare/1.1.99-beta.8...1.1.99-beta.9

### Donations

If you find Thaw useful and want to support its further development, consider throwing a coin in my hat.

* GitHub Sponsor: https://github.com/sponsors/stonerl
* Patreon: https://www.patreon.com/c/stonerl

## [1.1.99-beta.8] - 2026-03-01

Hello everyone,

This new beta hopefully fixes the issues of shuffling icons that where introduced with beta.6 & beta.7

### New

* **Advanced Reset Options:** Added a new 'Reset' section in Advanced Settings that allows users to reset all settings to their default values.
* **Reset Confirmation:** Includes a confirmation dialog to prevent accidental resets.
* **Screen Sharing Support:** Added `SSMenuAgent` (Screen Sharing) to the immovable items list to prevent "item response timeout" errors and unnecessary retries.

### Improvements & Fixes
#### Restoration Reliability:
* **Identity Tracking:** Updated the restoration logic to track item tags (namespace and title) rather than window IDs to accurately detect app restarts and prevent random icon movement.
* **Shuffle Prevention:** Added a base identifier fallback to handle apps that change their instance index after a restart, preventing icon shuffling and duplicates.
* **Infinite Loop Fix:** Resolved a bug where an infinite restoration loop occurred if items were already in their correct positions.
* **Multi-Icon Handling:** Improved reliability by skipping restoration for multi-icon apps and indexed items that handle their own positioning.

#### Visual & UI Refinements:
* **Overlay Logic:** The overlay now defaults to a higher drawing level for better visibility, only drawing behind icons when "Show menu bar background" is enabled.
* **Frame Updates:** Fixed an issue where the overlay panel failed to redraw when the frame changed.
* **Auto Layout:** Resolved vertical constraint ambiguity for control items to ensure consistent UI alignment.

#### Under-the-Hood:
* **Architecture:** Centralized all default values and reset logic into a unified namespace for better maintainability.
* **Circular Dependencies:** Extracted `RehideStrategy` and `SectionDividerStyle` enums into standalone files to improve project organization.
* **Project Maintenance:** Updated Xcode recommended settings and applied global code formatting.

### Localization
* Updated Indonesian and German translations.

### New Contributors
* @musanmaz made their first contribution in https://github.com/stonerl/Thaw/pull/214
* @William-Laverty made their first contribution in https://github.com/stonerl/Thaw/pull/221
* @coygeek made their first contribution in https://github.com/stonerl/Thaw/pull/238

**Full Changelog**: https://github.com/stonerl/Thaw/compare/1.1.99-beta.5...1.1.99-beta.8

## [1.1.99-beta.5] - 2026-02-24

Hey everyone,

This beta release focuses on improving the reliability of menu bar item placement and optimizing internal caching mechanisms for better system performance.

### New

* **Layout Persistence**: Implemented functionality to restore menu bar items to their saved sections.

### Improvements & Refinements
* **Enhanced PID Caching**:
    * Improved the efficiency and reliability of the `SourcePIDCache`.
    * Optimized `MenuBarItemService` to handle PID cache updates and cleanups more effectively.
    * Refined and renamed the negative cache reset logic for better clarity and performance.
* **Memory Management**: Added `autoreleasepool` to the cache cleanup process (`performCleanup`) to ensure better memory handling during background tasks.
* **Event Accuracy**:
    * Fixed a bug where clicking visible section items would incorrectly trigger the hidden section to reopen because window bounds were stale.
    * Now queries fresh bounds from the Window Server and rebuilds the lookup immediately before checking click locations in `handleShowOnClick`.

### New Contributors
* @FormalSnake made their first contribution in https://github.com/stonerl/Thaw/pull/210

**Full Changelog**: https://github.com/stonerl/Thaw/compare/1.1.99-beta.4...1.1.99-beta.5

### Donations

If you find Thaw useful and want to support its further development, consider throwing a coin in my hat.

* GitHub Sponsor: https://github.com/sponsors/stonerl
* Patreon: https://www.patreon.com/c/stonerl

## [1.1.99-beta.4] - 2026-02-23

Hello everyone,

this beta contains more performance and stability improvements contributed by @7a6163, fixes some newly discovered bugs and refines the overall UX.

### New Features:

* **Mission Control Integration:**
    * The menu bar overlay now hides instantly during Mission Control and App Exposé for a seamless system transition.
    * Implemented an invisible "probe" window and high-frequency timer to reliably track system-wide window transformations.
* **Enhanced Search Window:**
    * Added a magnifying glass icon and clickable edit buttons to the search panel bottom bar.
    * Improved keyboard handling: pressing `Esc` now clears the search field or closes the window if the field is empty.
    * Search results now feature a periodic refresh loop to keep animated icons, like sync spinners, live while the panel is open.
* **Advanced Customization:**
    * Added a configurable "Icon refresh rate" slider (1–30 fps) to Advanced settings, allowing users to tune the live refresh interval.
    * The application now persists and restores specific item orders per-section for more reliable layout management.

### Improvements & Fixes:

* **Performance & Battery Life:**
    * Rewrote the transparency check engine to read alpha bytes directly from memory, eliminating constant allocations during the refresh loop.
    * Reduced interaction latency by 100-500ms when clicking Ice Bar items by skipping redundant input pause polling.
    * Moved initial cache preloading to background tasks to ensure smoother UI transitions in the settings and search panels.
* **Menu Bar Stability:**
    * Fixed a race condition that could cause missing menu bar items after a drag operation.
    * Improved stability for external drags and suppressed caching during active move operations to prevent layout flickering.
* **Bug Fixes & Maintenance:**
    * Removed debug log spam from computed properties that were evaluated dozens of times per render pass.
    * Excluded internal control items from image captures to eliminate unnecessary failure and retry cycles.
    * Updated the Sparkle framework to version 2.9.0 for improved update reliability.

**Full Changelog**: https://github.com/stonerl/Thaw/compare/1.1.99-beta.3...1.1.99-beta.4

### Donations

If you find Thaw useful and want to support its further development, consider throwing a coin in my hat.

* GitHub Sponsor: https://github.com/sponsors/stonerl
* Patreon: https://www.patreon.com/c/stonerl

## [1.1.99-beta.3] - 2026-02-22

Hello everyone,

This beta release introduces significant performance optimizations (big THANKS goes out to @7a6163) to reduce CPU impact and energy consumption, alongside new customization options for multi-display setups and menu bar styling.

### New

* **Per-Display Settings**: You can now toggle "Always show hidden items" and the "Thaw Bar" for specific monitors.
* **Advanced Appearance**:
    * Added horizontal margin controls (left and right) for the menu bar shapes.
    * New menu bar icon option: Vertical chevrons (up/down) are now available as a section divider.
* **Dynamic Wallpapers**: Improved support for dynamic system backgrounds and third-party wallpaper apps (like Motiondesk), eliminating the "black gap" issue by compositing layers correctly.
* **Interaction Refinement**: "Show on click" and "Double-click for always-hidden" are now separate toggles for finer control over how you interact with hidden sections.

### Performance & Efficiency
* **CPU Optimization**: Drastically reduced WindowServer queries and mouse event overhead by implementing a height cache for the menu bar.
* **Energy Savings**: Throttled mouse events and debounced notifications to minimize system wakeups and improve battery life.
* **Instant Ice Bar**: The Ice Bar now reveals instantly using cached data. Additionally, animated icons (like sync spinners) now stay live while the panel is open.

### Improvements & Fixes
* **Reliability**: Fixed a potential hang or crash in event handling related to `CheckedContinuation` double-resumes.
* **Tooltips**: Improved positioning accuracy by re-reading window bounds after the display delay to ensure they appear in the correct spot.
* **UX**: The main icon is now excluded from triggering secondary context menus to prevent accidental activations.
* **Localization**: Updated and expanded German translations.

### New Contributors
* @CamilleGuillory made their first contribution in https://github.com/stonerl/Thaw/pull/168

**Full Changelog**: https://github.com/stonerl/Thaw/compare/1.1.99-beta.2...1.1.99-beta.3

### Donations

If you find Thaw useful and want to support its further development, consider throwing a coin in my hat.

* GitHub Sponsor: https://github.com/sponsors/stonerl
* Patreon: https://www.patreon.com/c/stonerl

## [1.1.99-beta.2] - 2026-02-20

Hello everyone,

This beta focuses on performance optimizations for users with many menu bar items and adds a positioning feature for hotkey users.

### New

* **IceBar at Mouse Pointer:** Added the `iceBarLocationOnHotkey` setting to allow users to override the IceBar's position when triggered via hotkey.
* **Dynamic Positioning:** Updated `IceBarPanel` to center at the mouse pointer (X and Y) when the hotkey override is active, while maintaining standard positioning for other activation methods.

### Performance Improvements
* **Batch Resolution:** Implement batch creation of `WindowInfo` objects in `MenuBarItem` to reduce expensive WindowServer round-trips.
* **Optimized PID Caching:** Refactor `SourcePIDCache` to perform a single batch AX traversal when a cache miss occurs, instead of redundant per-window scans.
* **Concurrency Control:** Add `scanLock` to `SourcePIDCache` to prevent concurrent AX traversals when resolving multiple windows.
* **Image Cache:** Improved LRU tracking efficiency within the image cache.

### Fixed

* **Sticky Tooltips:** Fix a bug where tooltips remained on screen after hiding the IceBar.

**Full Changelog**: https://github.com/stonerl/Thaw/compare/1.1.99-beta.1...1.1.99-beta.2

### Donations

If you find Thaw useful and want to support its further development, consider throwing a coin in my hat.

* GitHub Sponsor: https://github.com/sponsors/stonerl
* Patreon: https://www.patreon.com/c/stonerl

## [1.1.99-beta.1] - 2026-02-19

Hello everyone,

This beta introduces features for managing complex menu bars, including custom naming for items, better handling of duplicate icons (like multiple OneDrive accounts), and a new custom tooltip system.

### New

* **Custom Item Naming**: You can now rename any menu bar item via **Cmd+E** in the search panel.
* **Persistent Custom Names**: Custom names are stored in `UserDefaults` so they survive app restarts.
* **Multi-Instance Support**: Added an `instanceIndex` to uniquely identify and track multiple icons from the same application, such as multiple accounts for the same service.
* **Advanced Tooltip System**:
    * Replaced the system tooltip mechanism with a custom `NSPanel`-based tooltip for full control over timing and style.
    * Added a "Tooltip delay" slider (0–1s) in Advanced Settings.
    * Added an option to show tooltips for items directly in the system menu bar.

### Improvements & Fixes

* **Smart Rehide Logic**:
    * Sections will no longer auto-hide if the mouse is hovering inside the menu bar or the IceBar.
    * The "Thaw" icon is now protected from being moved into hidden sections to ensure it remains accessible.
* **Persistence Fixes**:
    * Removed `windowID` from persistence keys for non-system items, as these IDs change every launch.
    * Added fallbacks for helper processes (like Little Snitch) to ensure they are identified by bundle ID or process name rather than a random UUID.
* **Performance & Reliability**:
    * Optimized image updates with debounce and deduplication.
    * Throttled mouse events to reduce CPU usage.
    * Serialized temporary show operations using `@MainActor` to prevent race conditions.
* **UI Tweaks**:
    * Suppressed AutoFill popovers on search and rename text fields.
    * Improved tooltip behavior to prevent interference between different UI controllers.

### Localization

* Added **Brazilian Portuguese (pt-BR)** localization.
* Added **Russian (ru)** localization.
* Updated **Thai** and **Italian** translations.

### New Contributors
* @MarcoTerzulli made their first contribution in https://github.com/stonerl/Thaw/pull/132
* @dyxushuai made their first contribution in https://github.com/stonerl/Thaw/pull/136
* @afuno made their first contribution in https://github.com/stonerl/Thaw/pull/139
* @mrclrchtr made their first contribution in https://github.com/stonerl/Thaw/pull/156
* @josericardo-fo made their first contribution in https://github.com/stonerl/Thaw/pull/152

**Full Changelog**: https://github.com/stonerl/Thaw/compare/1.1.0...1.1.99-beta.1

### Donations

If you find Thaw useful and want to support its further development, consider throwing a coin in my hat.

* GitHub Sponsor: https://github.com/sponsors/stonerl
* Patreon: https://www.patreon.com/c/stonerl

## [1.1.0] - 2026-02-17

**Breaking the Ice**

Hello everyone,

Thaw's first major update is here! Out of the gate, I have to thank all of you who gave Thaw a shot, reported bugs and feature requests, and helped to test. I'm really overwhelmed by the response.

> [!IMPORTANT]
>Due to essential internal changes in how Thaw manages menu bar items, your current icon positions will be reset to "Always Visible." I sincerely apologize for the inconvenience, but this manual re-adjustment is unavoidable to ensure future stability.

### Localization Support (100% Completion)
Thaw is now fully localized in 12 languages. A massive thank you to our community contributors who made this possible:

* **Chinese (Simplified):** by @picpo
* **Chinese (Traditional):** by @7a6163
* **Dutch:** by @SeBr28
* **French:** by @UYTR5
* **German:** by @Mutzki13
* **Hungarian:** by @johnnybakucz
* **Indonesian:** by @volcbs
* **Italian:** by @zichichi
* **Korean:** by @yurihan
* **Spanish:** by @diazdesandi
* **Thai:** by @priesdelly

### Key Changes & Fixes

#### New Interactions & UI Polish
* **Double-Click Gesture:** You can now double-click directly on the menu bar to reveal the "Always Hidden" section.
* **Instant UI Refresh:** Menubar shapes (split/full) now update immediately when configuration changes, removing the previous 30-second delay.
* **Refined Tooltips:** Updated "Show on click" instructions to explicitly guide users on the new double click interaction.

#### Display & Layout Improvements
* **Ultrawide Monitor Fix:** Resolved a specific issue where items from the primary display were incorrectly included in calculations for external monitors. This previously caused "Always Hidden" items to appear incorrectly on the left side of ultrawide screens.
* **Thaw Bar Scaling Fix:** Resolved rendering issues by capping item height and clamping the menu bar content height to ensure a consistent appearance across different display scales.
* **Intelligent Multi-Monitor Support:** Thaw now detects the active menu bar for each screen and hides the app menu when items would otherwise overflow the screen edge.
* **Advanced Notch Detection:** Improved accuracy using `auxiliaryTopLeftArea` and added a new option to enable the Thaw Bar specifically for displays that feature a hardware notch.

#### Performance & Cleanup
* **CPU Optimizations:** Reduced overhead by debouncing image cache updates, adding polling delays, and skipping background work when panels are hidden.
* **Simplified Settings:** Removed the redundant "temporary item delay" setting as the smart rehide logic now handles these transitions automatically.

### New Contributors
A special thank you to everyone who contributed code, translations, or documentation to this release:

* @UYTR5 made their first contribution in https://github.com/stonerl/Thaw/pull/45
* @7a6163 made their first contribution in https://github.com/stonerl/Thaw/pull/47
* @diazdesandi made their first contribution in https://github.com/stonerl/Thaw/pull/48
* @Mutzki13 made their first contribution in https://github.com/stonerl/Thaw/pull/52
* @picpo made their first contribution in https://github.com/stonerl/Thaw/pull/58
* @yurihan made their first contribution in https://github.com/stonerl/Thaw/pull/68
* @priesdelly made their first contribution in https://github.com/stonerl/Thaw/pull/77
* @volcbs made their first contribution in https://github.com/stonerl/Thaw/pull/80
* @p-linnane made their first contribution in https://github.com/stonerl/Thaw/pull/101
* @zichichi made their first contribution in https://github.com/stonerl/Thaw/pull/111
* @johnnybakucz made their first contribution in https://github.com/stonerl/Thaw/pull/116
* @mittal-gunjit made their first contribution in https://github.com/stonerl/Thaw/pull/123

**Full Changelog**: https://github.com/stonerl/Thaw/compare/1.0.0...1.1.0

### Donations

If you find Thaw useful and want to support its further development, consider throwing a coin in my hat.

* GitHub Sponsor: https://github.com/sponsors/stonerl
* Patreon: https://www.patreon.com/c/stonerl

## [1.0.1-beta.8] - 2026-02-15

Hello everyone,

This will be the final beta before we release version `1.1.0`. This update focuses on optimizing background performance and adding display support for modern MacBook hardware.

### Changes
#### New Features
* **Notched Display Support**: Added a new option to use the Thaw Bar exclusively on notched displays.

#### Improvements & Fixes
* **Performance Optimization**: Reduced CPU overhead by skipping expensive timer work when panels are not visible.
* **Refined Rehide Logic**: Simplified the rehide system by removing the temporary item delay setting, as the smart rehide logic now better handles user activity and open menus.
* **Setup Updates**: Refined the Homebrew installation instructions in the README.

#### Localization
* **Traditional Chinese**: Received further translation updates.
* **German**: Received further translation updates.

### New Contributors
* @p-linnane made their first contribution in https://github.com/stonerl/Thaw/pull/101

**Full Changelog**: https://github.com/stonerl/Thaw/compare/1.0.1-beta.7...1.0.1-beta.8

#### Donations

If you find Thaw useful and want to support its further development, consider throwing a coin in my hat: https://github.com/sponsors/stonerl

## [1.0.1-beta.7] - 2026-02-14

Welcome to **beta.7**! This update focuses heavily on under-the-hood performance improvements, multi-monitor stability, and refining the overall feel of the app to make interactions smoother.

A huge thank you to everyone contributing translations and reporting bugs!

### Changes

#### Performance
* **Faster Restarts:** Added a disk cache for images, meaning Thaw will boot up and restore your layout much faster.
* **Reduced Background Usage:** We've heavily optimized the image cache to debounce and cancel redundant updates, significantly cutting down on background processing.
* **Smoother Dragging:** Refactored the move logic to remove unnecessary "nudges" and simplified item targeting by using the center of the items.

#### UI & Interaction Refinements
* **Menu Bar Interaction:** You can now double-click the "Always-Hidden" section when in "Show on click" mode.
* **Context Menus:** Added SF Symbol icons to all context menus (including the status item and menu bar right-clicks).
* **No More Ghosting:** Replaced SwiftUI shadows with native `NSPanel` shadows to eliminate visual artifacts/ghosting when the Ice Bar is hidden.
* **Flicker Prevention:** Added a 500ms grace period to stop the Ice Bar from flickering right after being shown.
* **Smart Search Panel:** The Menu Bar Search panel now automatically closes when it loses focus.
* **Warning:** Implemented a new warning that notifies you when macOS system settings are hiding your section dividers.

#### Multi-Monitor & Stability Fixes
* **Notch & Space Awareness:** Improved the app menu hiding logic to properly account for screen notches and limited space across different monitors.
* **Layout Race Condition:** Fixed a bug during layout resets by ensuring background tasks finish completely before the cache refreshes.

#### Localization
Our community translators are amazing!
* 🇫🇷 **French**, 🇩🇪 **German** & 🇨🇳 **Simplified Chinese** translations are now 100% complete!
* Added and updated 🇮🇩 **Indonesian**, 🇰🇷 **Korean** and 🇹🇼 **Traditional Chinese**.
* Updated 🇪🇸 **Spanish** localization.

### New Contributors
* @yurihan made their first contribution in https://github.com/stonerl/Thaw/pull/68
* @priesdelly made their first contribution in https://github.com/stonerl/Thaw/pull/77
* @volcbs made their first contribution in https://github.com/stonerl/Thaw/pull/80

**Full Changelog**: https://github.com/stonerl/Thaw/compare/1.0.1-beta.6...1.0.1-beta.7

#### Donations

If you find Thaw useful and want to support its further development, consider throwing a coin in my hat: https://github.com/sponsors/stonerl

## [1.0.1-beta.6] - 2026-02-10

### New

#### Expanded Localization:
- Simplified Chinese (zh-Hans) translation by @picpo
- French localization is now 100% complete.
- Improved translatability for various labels.

#### Enhanced Diagnostics:
- High-priority system messages are now written to both the console and diagnostic log files to assist with troubleshooting.

### Improvements & Fixes
#### System Reliability & Self-Healing:
- Implemented a health check and recovery system for HID events and event taps; the app now automatically detects and resets if system monitors become stuck or invalidated.
- Added a 5-second timeout to internal semaphores to prevent the app from permanently disabling input if a task is delayed or lost.

#### Menu Bar & Multi-Monitor Logic:
- Hot Corner Protection: Adjusted synthesized drag events to stay 5 pixels from the top of the screen, preventing accidental activation of macOS Hot Corners.
- Active Screen Targeting: On multi-monitor setups, the hidden section and Ice Bar now only appear on the monitor with the active menu bar.
- Position Verification: Added a polling loop and post-move verification to ensure items actually reach their destination and stabilize before interaction.
- Improved rehide detection for apps with non-standard popup windows using a 2-second grace interval and window scanning.

#### Ice Bar & Layout Stability:
- Icon Scaling: Icons in the Ice Bar now scale to fill the available height, preventing them from appearing too small on large displays.
- Show Desktop Fix: The Ice Bar now remains stationary and visible during "Show Desktop" gestures.
- Layout Refresh: The layout pane now correctly refreshes new items even if the Settings window was already open.
- Persistence: Added logic to automatically relocate items back to their original sections if an app quits or relaunches unexpectedly.

#### Image Cache:
- Reduced the blacklist cooldown from 5 minutes to 30 seconds for faster recovery of transient items.
- Cached images are now preserved for items with recent capture failures to prevent empty icons.
- Added deduplication to prevent duplicate window reports during move operations.

### New Contributors
* @Mutzki13 made their first contribution in https://github.com/stonerl/Thaw/pull/52
* @picpo made their first contribution in https://github.com/stonerl/Thaw/pull/58

**Full Changelog**: https://github.com/stonerl/Thaw/compare/1.0.1-beta.5...1.0.1-beta.6

### Donations

If you find Thaw useful and want to support its further development, consider throwing a coin in my hat: https://github.com/sponsors/stonerl

## [1.0.1-beta.5] - 2026-02-09

This beta focuses on bringing Thaw to a global audience with extensive localization support and refinements for macOS 26 stability.

### Localization

- French Support by @UYTR5
- German Support by @Mutzki13
- Spanish Support by @diazdesandi
- Traditional Chinese by @7a6163

Project-Wide Localizability: Refactored the codebase to ensure all user-facing strings in AppKit and SwiftUI components are localizable.

### Improvements & Fixes
#### Enhanced Image Caching:

- Raised the maxCacheSize from 50 to 200 to prevent icons from silently disappearing for power users.
- Optimized LRU eviction to skip items in currently displayed sections, preventing capture-then-evict cycles.
- Improved logging to track the full LRU order for better debugging.
- Notched Display Awareness: Added a getMenuBarHeightEstimate() helper with a three-tier fallback (live query, cached value, or notch-aware default) to prevent icon clamping issues on MacBooks.
- Ultra-Wide Monitor Fix: Implemented chained 9,999pt spacers to ensure hidden items are pushed fully offscreen on displays wider than 5,000 points.

#### Watchdog & Stability:

- Increased the watchdog timer to 6 seconds during layout drags to prevent premature cursor restoration.
- Added logic to reset the layout UI automatically after a watchdog timeout.
- Restored millisecond/microsecond cases in timeouts to satisfy linter requirements.
- Temporary Item Logic: Added a grace period to prevent temporary menu items from rehiding instantly when window layer detection fails.

#### Diagnostics

- New Logging Pipeline: Added a user-facing toggle in Advanced settings to enable diagnostic logging for the menu bar item cache pipeline.
- Finder Integration: The "Show Log Files in Finder" button and latest log filenames now remain visible whenever logs exist on disk.

### New Contributors
* @UYTR5 made their first contribution in https://github.com/stonerl/Thaw/pull/45
* @7a6163 made their first contribution in https://github.com/stonerl/Thaw/pull/47
* @diazdesandi made their first contribution in https://github.com/stonerl/Thaw/pull/48

**Full Changelog**: https://github.com/stonerl/Thaw/compare/1.0.1-beta.4...1.0.1-beta.5

### Donations

If you find Thaw useful and want to support its further development, consider throwing a coin in my hat: https://github.com/sponsors/stonerl

## [1.0.1-beta.4] - 2026-02-08

> [!IMPORTANT]
>Due to essential internal changes in how Thaw manages menu bar items, your current icon positions will be reset to "Always Visible." I sincerely apologize for the inconvenience, but this manual re-adjustment is unavoidable to ensure future stability.

**Full Changelog**: https://github.com/stonerl/Thaw/compare/1.0.1-beta.3...1.0.1-beta.4

## [1.0.1-beta.3] - 2026-02-07

**Full Changelog**: https://github.com/stonerl/Thaw/compare/1.0.1-beta.2...1.0.1-beta.3

## [1.0.1-beta.2] - 2026-02-06

**Full Changelog**: https://github.com/stonerl/Thaw/compare/1.0.1-beta.1...1.0.1-beta.2

## [1.0.1-beta.1] - 2026-02-05

**Full Changelog**: https://github.com/stonerl/Thaw/compare/1.0.0...1.0.1-beta.1

## [1.0.0] - 2026-02-05

**The Big Thaw**

Hello everyone,

Earlier than expected, but here is the first stable release of Thaw. I hope that all bugs, that surfaced during the beta releases, are fixed now.

### Overview

### Fixed

- Fixed a soft lock, when the chevron section dividers where enabled and a user would move the chevron for the hidden section into the always-hidden section #11.
- Fixed an issue where menubar clicks would not be recognized by Thaw anymore.

### Known issues
Bug #1 is still not fixed and needs further investigation. If you are on macOS 14/15, continue using Ice for now. If you are satisfied with the default settings in Thaw and don't use the Thaw bar (floating bar) you should be good to go, though.

A big thank you to all who helped to test and wrote me encouraging messages, @BillChirico who convinced me to go forward with the fork, and of course @jordanbaird, for creating Ice in the first place.

**Full Changelog**: https://github.com/stonerl/Thaw/compare/1.0.0-beta.4...1.0.0

### Donations

If you find Thaw useful and want to support its further development, consider throwing a coin in my hat: https://github.com/sponsors/stonerl

## [1.0.0-beta.4] - 2026-02-03

Hello everyone,

It feels like groundhog day 😁, a new release. This is the fourth and most likely final beta release of Thaw. If you have set the update channel to `Development` in Thaw now is a good time to switch back to `Stable`.

This release primarily addresses bug-fixes for macOS 14/15 and should finally resolve #1.

### New

- Double-clicking the Thaw icon now reveals the always hidden section.

### Changed

- The settings importer now only shows up when old Ice settings are detected.

### Fixed

- On macOS 14/15 temporary icons should now show up again when the Thaw icon is enabled.
- Rehiding temporary icons on macOS 14/15 do not trigger the "Apple Menu" anymore.

**Full Changelog**: https://github.com/stonerl/Thaw/compare/1.0.0-beta.3...1.0.0-beta.4

### Donations

If you find Thaw useful and want to support its further development, consider throwing a coin in my hat: https://github.com/sponsors/stonerl

## [1.0.0-beta.3] - 2026-02-02

Hello everyone,

A new day, a new beta :grin:. This is the third beta release of Thaw. The main focus for this was UI polish and minor bug fixes.

### Changed

- The Menubar Appearance Editor is now again a pop-over window and automatically focused.
- Thaw now restarts itself when a new display is connected to refresh its state.
- All remaining Ice UI strings have been removed.
- The "Check for updates automatically" window is now a modal inside the settings app.
- The default Icon for Thaw in the menu bar is now the Ice Cube.

### Fixed

- The importer now correctly imports the Hotkey bindings from Ice.
- New icons now always show up in the visible section (see #4)
- Possibly fixes #1, but that needs to be tested since I cannot reproduce the issue.

**Full Changelog**: https://github.com/stonerl/Thaw/compare/1.0.0-beta.2...1.0.0-beta.3

### Revamped Menubar Appearance Editor
For some reason, in Ice, this was reverted to a normal window. Here is the restored pop-over.

<img width="50%" height="50%" alt="Menubar Appearance Editor" src="https://github.com/user-attachments/assets/a0fa9b52-336a-4684-acbb-274ca0398251" />

### New Auto-Update Request
In Ice, the update request window did not show up correctly in certain cases. The request is now part of the settings window and shows up on the first start of the settings window.

<img width="50%" height="50%" alt="Update Request" src="https://github.com/user-attachments/assets/d3e2f5da-21d6-47a7-9c96-a9903e6c76c9" />

### Donations

If you find Thaw useful and want to support its further development, consider throwing a coin in my hat: https://github.com/sponsors/stonerl

## [1.0.0-beta.2] - 2026-02-01

Hi everyone,

This is the second beta release of Thaw. It mainly includes some cleanups since I forked but also some bug fixes and enhancements.

### New

- New Icon based on the original.
- Added `Command + ,` to quickly open settings directly from the search window.
- Added an Importer for Ice settings.

### Fixed

- Fixed some issues with the timed and smart rehide strategy.
- Fixed an issue where auto-hiding the menubar on external monitors would not show the hidden section or floating bar.
- Fixed an issue where the cursor would suddenly disappear.

### Known issues
- There are still some issues left with the timed and smart rehide in multi-monitor setups.

**Full Changelog**: https://github.com/stonerl/Thaw/compare/1.0.0-beta.1...1.0.0-beta.2

### Settings Import
You can now import your old settings from Ice on first start. If you currently use beta 1 you should also see the permissions window to import the settings. But you might need to restart Thaw since there are already exiting settings in place. Only tested with Ice settings from version `0.11.13-dev.2`.

<img width=50% height=50% alt="Import Settings" src="https://github.com/user-attachments/assets/69b0748d-c5d4-44d6-acbf-26dfe4384893" />

### Donations

If you find Thaw useful and want to support its further development, consider throwing a coin in my hat: https://github.com/sponsors/stonerl

## [1.0.0-beta.1] - 2026-01-30

Hi everyone,

This is the initial release to get things going. There will be more beta release in the future to fix some of the bugs that where present in Ice and are therefore present in Thaw.

I currently don't have an ETA for a stable release. Furthermore, I won't work on new features as of now, since my primary focus is on fixing bugs. If you find any, please do not hesitate to report them.

### Fixed

#### This release mainly addresses the following issues:

- Fix menu bar items not displaying when "Displays have separate spaces" is disabled on macOS 26 (Tahoe).
- Fix crashes on macOS 26 (Tahoe).
- Reduce high memory usage and memory leaks, especially in multi-monitor setups.
- Reduce UI flicker on about page when interacting with control elements.

### Known issues

**Full Changelog**: https://github.com/stonerl/Thaw/compare/ed5c972...690f6c3
- Smart and timed menu bar re-hiding does not function properly, especially in multi-monitor setups.
- Still uses the old Ice icon.

### Updates
If you want to get future development updates, set the Update channel to `Development` in the about section.

<img width=75% height=75% alt="Updates" src="https://github.com/user-attachments/assets/890e0020-3707-482b-9201-23df9694f658" />

### Donations

If you find Thaw useful and want to support its further development, consider throwing a coin in my hat: https://github.com/sponsors/stonerl
