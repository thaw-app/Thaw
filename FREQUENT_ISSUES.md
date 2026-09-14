# Frequent Issues <!-- omit in toc -->

Check here before [filing a bug](https://github.com/thaw-app/Thaw/issues/new/choose). Your problem may already be known with a workaround available.

- [Items end up in the wrong section](#items-end-up-in-the-wrong-section)
- [Thaw removed an item](#thaw-removed-an-item)
- [Layout changes on its own](#layout-changes-on-its-own)
- [How do I solve the `Thaw cannot arrange menu bar items in automatically hidden menu bars` error?](#how-do-i-solve-the-thaw-cannot-arrange-menu-bar-items-in-automatically-hidden-menu-bars-error)
- [An item is visible in the menu bar but missing from Layout settings](#an-item-is-visible-in-the-menu-bar-but-missing-from-layout-settings)
- [Little Snitch](#little-snitch)
- [CodexBar](#codexbar)
- [Multi-monitor / plugging in a display](#multi-monitor--plugging-in-a-display)
- [Menu bar spacing (beta) hides or clips items](#menu-bar-spacing-beta-hides-or-clips-items)
- [Screen Recording and permission prompts](#screen-recording-and-permission-prompts)
- [Hidden items still visible when the Thaw bar is off](#hidden-items-still-visible-when-the-thaw-bar-is-off)
- [Flickering, refreshing, or "dancing" icons](#flickering-refreshing-or-dancing-icons)
- [Live Activities and iPhone mirroring](#live-activities-and-iphone-mirroring)
- [High CPU or memory usage](#high-cpu-or-memory-usage)
- [Known issues](#known-issues)
- [Before you file a bug](#before-you-file-a-bug)

## Items end up in the wrong section

macOS inserts new status items at the far left, which Thaw treats as the Hidden section (or Always Hidden when enabled). Some apps don't persist their position across relaunch, so Thaw may treat them as new even after you moved them.

Fix:

1. Open **Settings → Menu Bar Layout** and drag the item into the correct section.
2. **⌘ Command + drag** the item in the menu bar.
3. Move the **New Items** badge to your preferred default section (Thaw 2.0 remembers layout through profiles and that badge).
4. Use **Reset layout** only to start over; it can move every item back to Visible.

If an item keeps returning to Hidden or Always Hidden after reboot, the host app likely isn't saving its position. For [Little Snitch](#little-snitch) and [CodexBar](#codexbar), see their sections; both have known upstream causes.

Related: [#607](https://github.com/thaw-app/Thaw/issues/607), [#707](https://github.com/thaw-app/Thaw/issues/707), [#675](https://github.com/thaw-app/Thaw/issues/675), [#605](https://github.com/thaw-app/Thaw/issues/605).

## Thaw removed an item

Thaw cannot delete menu bar items. A vanished item was usually moved into the Hidden or Always Hidden section by macOS or by your layout.

Fix:

1. **Option + click** the Thaw icon to reveal the always-hidden section (or double-click an empty area of the menu bar if you enabled that in **Settings → Advanced**).
2. **⌘ Command + drag** the item into a different section.

## Layout changes on its own

Thaw persists item order per profile. Drift usually comes from one of:

- macOS or a host app relaunching its status item with a new identity.
- A display topology change (plugging in a monitor, waking from sleep, Sidecar, KVM switch).
- A spacing change that requires Thaw to relaunch apps with menu bar items.

When spacing must be applied across a transition, Thaw may relaunch affected apps, which can look like icons jumping or duplicating briefly. Enable **Confirm before relaunching apps** in **Settings → Displays** to get a prompt first.

If order keeps changing without any display or app changes, it may be a bug. See [Before you file a bug](#before-you-file-a-bug).

Related: [#702](https://github.com/thaw-app/Thaw/issues/702), [#717](https://github.com/thaw-app/Thaw/issues/717), [#718](https://github.com/thaw-app/Thaw/issues/718).

## How do I solve the `Thaw cannot arrange menu bar items in automatically hidden menu bars` error?

macOS doesn't expose enough of the menu bar for Thaw to rearrange items while **Automatically hide and show the menu bar** is active.

Fix:

1. Open **System Settings → Control Center**.
2. Set **Automatically hide and show the menu bar** to **Never** (below).
3. Update your layout in **Settings → Menu Bar Layout**.
4. Return **Automatically hide and show the menu bar** to your preferred setting.

![Disable Menu Bar Hiding](https://github.com/user-attachments/assets/74c1fde6-d310-4fe3-9f2b-703d8ccb636a)

## An item is visible in the menu bar but missing from Layout settings

Some apps draw icons outside the status-item APIs Thaw enumerates, or host their icon under `com.apple.controlcenter` without a stable identifier. Thaw may show the icon in the bar but not list it by name in **Settings → Menu Bar Layout**.

macOS also prevents certain system items from being repositioned with **⌘ Command + drag**: they follow the cursor during the drag but snap back on release.

For known problematic apps, see [Little Snitch](#little-snitch) and [CodexBar](#codexbar).

## Little Snitch

Little Snitch's agent (`at.obdev.littlesnitch.agent`) often appears at the Accessibility layer as `com.apple.controlcenter:Item-0` without a stable source PID, so Thaw must identify it indirectly (marker-pair resolution) rather than by bundle ID. Symptoms that look like Thaw bugs but stem from how Little Snitch hosts its status item on macOS 26:

| Symptom | Example issues |
|---------|----------------|
| Icon not listed by name in Layout settings | [#709](https://github.com/thaw-app/Thaw/issues/709) |
| Icon moves back to Hidden / Always Hidden after a few minutes | [#651](https://github.com/thaw-app/Thaw/issues/651), [#575](https://github.com/thaw-app/Thaw/issues/575) |
| Icon won't stay where you place it (regression in 2.0.0-beta.13) | [#643](https://github.com/thaw-app/Thaw/issues/643) |
| Dragging in Layout settings has no lasting effect | [#372](https://github.com/thaw-app/Thaw/issues/372), [#709](https://github.com/thaw-app/Thaw/issues/709) |
| Clicking the icon while hidden makes the Thaw icon follow the cursor | [#332](https://github.com/thaw-app/Thaw/issues/332) |
| Duplicate Little Snitch Agent after wake from sleep | [#641](https://github.com/thaw-app/Thaw/issues/641) |

Fix:

1. **Update Thaw** to the latest 2.0 beta (or stable, whichever is newer). 2.0.0-beta.14+ has improved matching for Control Center-hosted items ([#643](https://github.com/thaw-app/Thaw/issues/643)); the beta 13 "will not stick" regression should not recur.
2. If the icon vanishes when Thaw launches, quit Thaw, **⌘ Command + drag** the Little Snitch icon to the far right of the menu bar, then relaunch Thaw ([#709](https://github.com/thaw-app/Thaw/issues/709)).
3. Clear Thaw's cache and reset Accessibility, then re-grant when prompted ([#643](https://github.com/thaw-app/Thaw/issues/643)):

   ```sh
   rm -rf ~/Library/Caches/com.stonerl.Thaw
   tccutil reset Accessibility com.stonerl.Thaw
   ```

4. If Little Snitch **Network Monitor meters** keep returning to Always Hidden, place them from Little Snitch's own preferences rather than only through Thaw ([#575](https://github.com/thaw-app/Thaw/issues/575)).
5. If layout problems started after installing **CodexBar 0.29.x**, see [CodexBar](#codexbar). Corrupted Control Center state can affect Little Snitch and other Control Center-hosted items.

Still broken: the icon may never appear under the name "Little Snitch" in Layout settings even when visible in the bar ([#709](https://github.com/thaw-app/Thaw/issues/709)), and moving it only inside Thaw's Layout panel may not stick. Menu-bar **⌘ Command + drag** (with Thaw quit, if needed) is more reliable.

If none of this helps, file a bug with diagnostic logs. Search the log for `obdev`, `littlesnitch`, and `marker-pair`. Absence of `at.obdev.littlesnitch.agent` usually means Thaw hasn't identified the item yet.

## CodexBar

CodexBar issues are upstream: certain versions wrote state into macOS Control Center preferences that caused Thaw (and other menu bar managers) to misplace the icon into Hidden or Always Hidden ([#605](https://github.com/thaw-app/Thaw/issues/605)).

Affected versions:

| Version | Status |
|---------|--------|
| 0.27.0 | Reported broken ([#605](https://github.com/thaw-app/Thaw/issues/605) comment) |
| 0.28.0 | Worked in maintainer testing |
| 0.29.0 | Known bad: corrupts Control Center files ([#605](https://github.com/thaw-app/Thaw/issues/605)) |
| 0.29.1 | Fixed for some users |
| 0.30.1+ | Upstream fix shipped ([#605](https://github.com/thaw-app/Thaw/issues/605), [CodexBar v0.30.1](https://github.com/steipete/CodexBar/releases/tag/v0.30.1), [steipete/CodexBar#1122](https://github.com/steipete/CodexBar/pull/1122)) |

Fix:

1. Update CodexBar to **[v0.30.1](https://github.com/steipete/CodexBar/releases/tag/v0.30.1) or newer**.
2. If the menu bar still behaves oddly after upgrading, reset Control Center preferences ([#605](https://github.com/thaw-app/Thaw/issues/605)):

   ```sh
   killall ControlCenter

   rm ~/Library/Preferences/com.apple.controlcenter.plist
   rm ~/Library/Preferences/ByHost/com.apple.controlcenter*.plist
   ```

3. Re-pin CodexBar to the Visible section in **Settings → Menu Bar Layout**.

Corrupted Control Center state from 0.29.x can also cause **Little Snitch**, **Timemator**, and other Control Center-hosted items to drift ([#643](https://github.com/thaw-app/Thaw/issues/643) comments). If multiple apps misbehave at once, fix CodexBar first.

## Multi-monitor / plugging in a display

Connecting, disconnecting, or switching displays can cause brief visual glitches (resolution flicker, extra spacing), often transient. Thaw may relaunch apps with menu bar items when a display transition requires applying different spacing, which can produce duplicate icons if the host app also relaunches its agent. The duplicate usually belongs to the app, not Thaw.

Thaw may relaunch apps with menu bar items when a display transition requires applying different menu bar spacing. That can produce duplicate icons if the host app also relaunches its agent. The duplicate usually belongs to the app, not Thaw. Thaw does not quit macOS system services during this; see [What Thaw will and won't quit](#what-thaw-will-and-wont-quit).

Fix:

1. Enable **Confirm before relaunching apps** in **Settings → Displays**.
2. Wait a few seconds after a display change before editing layout.
3. After wake from sleep, quit and reopen Thaw if layout looks stale.

Related: [#591](https://github.com/thaw-app/Thaw/issues/591), [#685](https://github.com/thaw-app/Thaw/issues/685), [#641](https://github.com/thaw-app/Thaw/issues/641), [#708](https://github.com/thaw-app/Thaw/issues/708).

## Menu bar spacing (beta) hides or clips items

Spacing is a beta feature. Values far from the default (especially negative spacing) change how many items fit; items can end up under the notch or off-screen while still appearing in Layout settings.

Fix:

1. Return spacing to the default and confirm all items are reachable.
2. Re-apply spacing in small steps.
3. If a system app is missing after a spacing change (for example Spotlight), restart it with `launchctl kickstart -k gui/$(id -u)/com.apple.Spotlight`, or log out and back in.

Related: [#664](https://github.com/thaw-app/Thaw/issues/664).

## What Thaw will and won't quit

Menu bar spacing lives in a single system-wide preference, and a status item only picks up a new value when its owning process starts. To apply spacing right away, Thaw restarts the apps that own menu bar items. It sorts them into three groups first:

- **Apps macOS launches for you** (Spotlight, the input menu, Dock, Time Machine) are restarted through `launchctl kickstart`, so launchd stays their launching parent. Quitting one and relaunching it directly is rejected by macOS at exec, and the item would stay gone until you rebooted ([#720](https://github.com/thaw-app/Thaw/issues/720)).
- **System binaries no LaunchAgent claims** are left alone entirely. Thaw has no way to bring them back, so it never takes them down ([#1070](https://github.com/thaw-app/Thaw/issues/1070)).
- **Your own apps** are asked to quit and launched again. Thaw asks; it never force-quits. An app that declines (a save sheet, a long operation) keeps running and keeps the previous spacing.

The trade-off is that anything Thaw skips keeps its old spacing until it next starts on its own. Spacing changes are rare; a permanently dead Spotlight is not worth an evenly spaced menu bar.

If you would rather Thaw never restart apps, set **When applying spacing** to **Wait until next restart** in **Settings → Displays**. Thaw still writes the new spacing to the system preference, but leaves every app running; the new spacing appears the next time each app starts on its own (after a restart, or when you reopen it). This avoids the restart disruption when plugging in or unplugging monitors, at the cost of spacing not taking effect immediately.

## Screen Recording and permission prompts

Thaw uses **Screen Recording** for live previews and wallpaper-derived tints. Hiding, revealing, and rearranging items don't need it. Without the permission, Thaw draws each item as its owning app's icon in the Thaw Bar, the layout bars, and the search panel (older builds showed an error on those surfaces instead; see [#628](https://github.com/thaw-app/Thaw/issues/628)).

Fix:

1. Grant permissions under **Settings → Advanced → Permissions**.
2. If macOS keeps re-prompting after reboot despite approval ([#683](https://github.com/thaw-app/Thaw/issues/683)), remove Thaw from **System Settings → Privacy & Security → Screen Recording**, then add it again.

## Hidden items still visible when the Thaw bar is off

Disabling **Use Thaw Bar** stops Thaw from actively concealing items. Icons hidden while the bar was enabled may stay visible until Thaw manages the layout again.

Fix: turn **Use Thaw Bar** back on, or open **Settings → Menu Bar Layout** and re-apply your sections.

Related: [#610](https://github.com/thaw-app/Thaw/issues/610).

## Flickering, refreshing, or "dancing" icons

Frequent redraws are often caused by the host app updating its status item (for example Shazam or Amphetamine), not by Thaw. Mission Control and space switches can also trigger full layout storms ([#718](https://github.com/thaw-app/Thaw/issues/718)).

Fix:

1. Update Thaw to the latest release.
2. Check whether the affected app has a menu-bar redraw setting.
3. If flicker started after a Thaw update, file a bug with logs; it may be a regression.

Related: [#678](https://github.com/thaw-app/Thaw/issues/678), [#649](https://github.com/thaw-app/Thaw/issues/649).

## Live Activities and iPhone mirroring

Live Activities mirrored from an iPhone (Screen Continuity) can interfere with layout operations ([#722](https://github.com/thaw-app/Thaw/issues/722), [#556](https://github.com/thaw-app/Thaw/issues/556)). Gaps or empty spaces in the menu bar during mirroring are a known limitation.

Fix: pause iPhone mirroring, or wait until the Live Activity ends before editing layout.

## High CPU or memory usage

Sustained high CPU or RAM after long uptime is not expected ([#680](https://github.com/thaw-app/Thaw/issues/680), [#599](https://github.com/thaw-app/Thaw/issues/599)).

Fix:

1. Quit and reopen Thaw.
2. Disable **Enable diagnostic logging** when you're not actively debugging.
3. If usage stays high, file a bug with logs (see below).

## Known issues

Things Thaw does not handle, or handles badly. No need to report these.

- iStats items may be hidden when another item gets hidden. → Working with the iStats developers; no fix yet.
- Live-text items (a temperature, clock, or transfer rate) can land next to where you put them, not exactly there. → macOS places them from memory, not the layout table.
- Flux cannot be seen or handled by Thaw. → No fix; Flux does not expose itself to menu bar managers.

## Before you file a bug

1. Confirm you are on the **latest Thaw release** and **macOS 26+** (the active target for current development).
2. Search [open and closed issues](https://github.com/thaw-app/Thaw/issues?q=is%3Aissue) for duplicates.
3. Note your **display setup** (single vs multiple monitors).
4. Enable **Settings → Advanced → Diagnostics → Enable diagnostic logging**, reproduce the issue, and attach the log from **Reveal Logs in Finder**.
5. Use the [bug report template](https://github.com/thaw-app/Thaw/issues/new/choose). Reports without enough detail to reproduce may be closed until more information is provided.

**Support policy:** Thaw versions below **1.2.0** on macOS versions below **15.7.7** are no longer supported. macOS 26 and later are actively supported.
