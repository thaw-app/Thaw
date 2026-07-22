# Frequent Issues <!-- omit in toc -->

Check here before [filing a bug](https://github.com/stonerl/Thaw/issues/new/choose). Your problem may already be known with a workaround available.

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
- [Before you file a bug](#before-you-file-a-bug)

## Items end up in the wrong section

macOS inserts new status items at the **far left** of the menu bar. Thaw treats that region as the **Hidden** section (or **Always Hidden** when that section is enabled). Some apps do not persist their menu bar position across relaunch, so Thaw may treat them as newly detected items even after you have moved them before.

Thaw 2.0 remembers layout through **profiles** and the **New Items** badge in **Settings → Menu Bar Layout**. Move that badge to choose where newly detected items should appear.

**Workarounds:**

1. Open **Settings → Menu Bar Layout** and drag the item into the correct section.
2. **⌘ Command + drag** the item in the menu bar.
3. Move the **New Items** badge to your preferred default section.
4. Use **Reset layout** only when you intend to start over — it can move every item back to Visible.

If an item keeps returning to Hidden or Always Hidden after reboot, the host app is likely not saving its position. For [Little Snitch](#little-snitch) and [CodexBar](#codexbar), see the dedicated sections — both have known upstream causes.

Related reports: [#607](https://github.com/stonerl/Thaw/issues/607), [#707](https://github.com/stonerl/Thaw/issues/707), [#675](https://github.com/stonerl/Thaw/issues/675), [#605](https://github.com/stonerl/Thaw/issues/605).

## Thaw removed an item

Thaw cannot delete menu bar items. An item that seems to have vanished was usually moved into the **Hidden** or **Always Hidden** section by macOS or by your layout.

**Workaround:**

1. **Option + click** the Thaw icon to reveal the always-hidden section (or double-click an empty area of the menu bar if you enabled that in **Settings → Advanced**).
2. **⌘ Command + drag** the item into a different section.

## Layout changes on its own

Thaw **does** persist item order per profile. Layout drift usually comes from one of these causes:

- macOS or a host app **relaunches its status item** with a new identity.
- A **display topology change** (plugging in a monitor, waking from sleep, Sidecar, KVM switch).
- A **spacing change** that requires Thaw to relaunch apps with menu bar items.

When display spacing must be applied across a transition, Thaw may relaunch affected apps. That can look like icons jumping or duplicating briefly. Enable **Confirm before relaunching apps** in **Settings → Displays** if you want a prompt first.

If order keeps changing without any display or app changes, it may be a bug — see [Before you file a bug](#before-you-file-a-bug).

Related reports: [#702](https://github.com/stonerl/Thaw/issues/702), [#717](https://github.com/stonerl/Thaw/issues/717), [#718](https://github.com/stonerl/Thaw/issues/718).

## How do I solve the `Thaw cannot arrange menu bar items in automatically hidden menu bars` error?

macOS does not expose enough of the menu bar for Thaw to rearrange items while **Automatically hide and show the menu bar** is active.

1. Open **System Settings** on your Mac.
2. Go to **Control Center**.
3. Set **Automatically hide and show the menu bar** to **Never**, as shown below.
4. Update your layout in **Settings → Menu Bar Layout**.
5. Return **Automatically hide and show the menu bar** to your preferred setting.

![Disable Menu Bar Hiding](https://github.com/user-attachments/assets/74c1fde6-d310-4fe3-9f2b-703d8ccb636a)

## An item is visible in the menu bar but missing from Layout settings

Some apps draw menu bar icons outside the normal status-item APIs Thaw enumerates, or host their icon under the `com.apple.controlcenter` namespace without a stable identifier. Thaw may show the icon in the menu bar but not list it by name in **Settings → Menu Bar Layout**.

macOS also prevents certain **system items** from being repositioned with **⌘ Command + drag** — they follow the cursor during the drag but snap back on release.

For known problematic apps, see the dedicated sections below:

- [Little Snitch](#little-snitch)
- [CodexBar](#codexbar)

## Little Snitch

Little Snitch is the most frequently reported third-party menu bar app in Thaw issues. Its agent (`at.obdev.littlesnitch.agent`) often appears at the Accessibility layer as `com.apple.controlcenter:Item-0` **without a stable source PID**, so Thaw must identify it indirectly (marker-pair resolution) rather than by bundle ID alone.

This causes several confusing symptoms that look like Thaw bugs but stem from how Little Snitch hosts its status item on macOS 26:

| Symptom | Example issues |
|---------|----------------|
| Icon not listed by name in Layout settings | [#709](https://github.com/stonerl/Thaw/issues/709) |
| Icon moves back to Hidden / Always Hidden after a few minutes | [#651](https://github.com/stonerl/Thaw/issues/651), [#575](https://github.com/stonerl/Thaw/issues/575) |
| Icon won't stay where you place it (regression in 2.0.0-beta.13) | [#643](https://github.com/stonerl/Thaw/issues/643) |
| Dragging in Layout settings has no lasting effect | [#372](https://github.com/stonerl/Thaw/issues/372), [#709](https://github.com/stonerl/Thaw/issues/709) |
| Clicking the icon while hidden makes the Thaw icon follow the cursor | [#332](https://github.com/stonerl/Thaw/issues/332) |
| Duplicate Little Snitch Agent after wake from sleep | [#641](https://github.com/stonerl/Thaw/issues/641) |

**What works today**

- **2.0.0-beta.14+** includes improved matching for Control Center–hosted items ([#643](https://github.com/stonerl/Thaw/issues/643)). The beta 13 regression ("will not stick") should not recur on current builds.
- Thaw maintainers are in contact with the Little Snitch developers about the underlying identification problem.

**Workarounds to try**

1. **Update Thaw** to the latest 2.0 beta (or stable, whichever is newer).
2. If the icon vanishes when Thaw launches, **quit Thaw**, **⌘ Command + drag** the Little Snitch icon to the far right of the menu bar, then relaunch Thaw ([#709](https://github.com/stonerl/Thaw/issues/709)).
3. Clear Thaw's cache and reset Accessibility permission, then re-grant when prompted ([#643](https://github.com/stonerl/Thaw/issues/643)):

   ```sh
   rm -rf ~/Library/Caches/com.stonerl.Thaw
   tccutil reset Accessibility com.stonerl.Thaw
   ```

4. If Little Snitch **Network Monitor meters** keep returning to Always Hidden, try placing them from Little Snitch's own preferences rather than only through Thaw ([#575](https://github.com/stonerl/Thaw/issues/575)).
5. If layout problems started after installing **CodexBar 0.29.x**, see [CodexBar](#codexbar) — corrupted Control Center state can affect Little Snitch and other Control Center–hosted items.

**What may still not work**

- The icon may never appear under the name "Little Snitch" in Layout settings even when visible in the bar ([#709](https://github.com/stonerl/Thaw/issues/709)).
- Moving Little Snitch **only** inside Thaw's Layout panel may not stick; menu-bar **⌘ Command + drag** (with Thaw quit, if needed) is more reliable for some users.

If none of the above helps, file a bug with diagnostic logs. Search the log for `obdev`, `littlesnitch`, and `marker-pair` — absence of `at.obdev.littlesnitch.agent` usually means Thaw has not identified the item yet.

## CodexBar

CodexBar issues are **upstream**: certain CodexBar versions wrote state into macOS Control Center preferences that caused Thaw (and other menu bar managers) to misplace the icon into Hidden or Always Hidden ([#605](https://github.com/stonerl/Thaw/issues/605)).

**Affected CodexBar versions (from issue reports)**

| Version | Status |
|---------|--------|
| **0.27.0** | Reported broken ([#605](https://github.com/stonerl/Thaw/issues/605) comment) |
| **0.28.0** | Worked in maintainer testing |
| **0.29.0** | Known bad — corrupts Control Center files ([#605](https://github.com/stonerl/Thaw/issues/605)) |
| **0.29.1** | Fixed for some users |
| **0.30.1+** | Upstream fix shipped ([#605](https://github.com/stonerl/Thaw/issues/605), [CodexBar v0.30.1](https://github.com/steipete/CodexBar/releases/tag/v0.30.1), [steipete/CodexBar#1122](https://github.com/steipete/CodexBar/pull/1122)) |

Thaw versions seen in reports: **1.2.0** (original report), **2.0.0-beta.13+** (follow-up testing). The fix is on the CodexBar side; use a current Thaw build together with CodexBar **0.30.1 or later**.

**Workarounds**

1. Update CodexBar to **[v0.30.1](https://github.com/steipete/CodexBar/releases/tag/v0.30.1) or newer**.
2. If the menu bar still behaves oddly after upgrading, reset Control Center preferences ([#605](https://github.com/stonerl/Thaw/issues/605)):

   ```sh
   killall ControlCenter

   rm ~/Library/Preferences/com.apple.controlcenter.plist
   rm ~/Library/Preferences/ByHost/com.apple.controlcenter*.plist
   ```

3. Re-pin CodexBar to the Visible section in **Settings → Menu Bar Layout**.

Corrupted Control Center state from CodexBar 0.29.x can also cause **Little Snitch**, **Timemator**, and other Control Center–hosted items to drift ([#643](https://github.com/stonerl/Thaw/issues/643) comments). If multiple apps misbehave at once, fix CodexBar first.

## Multi-monitor / plugging in a display

Connecting, disconnecting, or switching displays can cause brief visual glitches: resolution flicker, extra spacing, or a short virtual-display handshake. These are often transient.

Thaw may **relaunch apps with menu bar items** when a display transition requires applying different menu bar spacing. That can produce duplicate icons if the host app also relaunches its agent — the duplicate usually belongs to the app, not Thaw.

**Workarounds:**

1. Enable **Confirm before relaunching apps** in **Settings → Displays**.
2. Wait a few seconds after a display change before editing layout.
3. After wake from sleep, quit and reopen Thaw if layout looks stale.

Related reports: [#591](https://github.com/stonerl/Thaw/issues/591), [#685](https://github.com/stonerl/Thaw/issues/685), [#641](https://github.com/stonerl/Thaw/issues/641), [#708](https://github.com/stonerl/Thaw/issues/708).

## Menu bar spacing (beta) hides or clips items

Menu bar spacing is a **beta** feature. Values far from the default (especially negative spacing) change how many items fit. Items can end up under the notch or off-screen even though they still appear in Layout settings.

**Workarounds:**

1. Return spacing to the default and confirm all items are reachable.
2. Re-apply spacing in small steps.
3. If a system app crashes when spacing changes (for example Spotlight), treat it as an upstream macOS issue ([#720](https://github.com/stonerl/Thaw/issues/720)).

Related reports: [#664](https://github.com/stonerl/Thaw/issues/664).

## Screen Recording and permission prompts

Thaw uses **Screen Recording** for layout thumbnails, tooltips, and some overlay features. Without it, **Settings → Menu Bar Layout** may fail to load items, and revealing only the always-hidden section can be limited ([#628](https://github.com/stonerl/Thaw/issues/628)).

Grant permissions under **Settings → Advanced → Permissions**. If macOS keeps re-prompting after reboot despite approval ([#683](https://github.com/stonerl/Thaw/issues/683)), remove Thaw from **System Settings → Privacy & Security → Screen Recording**, then add it again.

## Hidden items still visible when the Thaw bar is off

Disabling **Use Thaw Bar** stops Thaw from actively concealing items. Icons that were hidden while the bar was enabled may remain visible until Thaw manages the layout again.

**Workaround:** Turn **Use Thaw Bar** back on, or open **Settings → Menu Bar Layout** and re-apply your sections.

Related report: [#610](https://github.com/stonerl/Thaw/issues/610).

## Flickering, refreshing, or "dancing" icons

Frequent redraws are often caused by the **host app** updating its status item (for example Shazam or Amphetamine) rather than by Thaw. Mission Control and space switches can also trigger full layout storms ([#718](https://github.com/stonerl/Thaw/issues/718)).

**Workarounds:**

1. Update Thaw to the latest release.
2. Check whether the affected app has a menu-bar redraw setting.
3. If flicker started after a Thaw update, file a bug with logs — it may be a regression.

Related reports: [#678](https://github.com/stonerl/Thaw/issues/678), [#649](https://github.com/stonerl/Thaw/issues/649).

## Live Activities and iPhone mirroring

Live Activities mirrored from an iPhone (Screen Continuity) can interfere with layout operations ([#722](https://github.com/stonerl/Thaw/issues/722), [#556](https://github.com/stonerl/Thaw/issues/556)). Gaps or empty spaces in the menu bar during mirroring are a known limitation.

**Workaround:** Pause iPhone mirroring or wait until the Live Activity ends before editing layout.

## High CPU or memory usage

Sustained high CPU or RAM after long uptime is not expected ([#680](https://github.com/stonerl/Thaw/issues/680), [#599](https://github.com/stonerl/Thaw/issues/599)).

**Workarounds:**

1. Quit and reopen Thaw.
2. Disable **Enable diagnostic logging** when you are not actively debugging.
3. If usage stays high, file a bug with logs (see below).

## Before you file a bug

1. Confirm you are on the **latest Thaw release** and **macOS 26+** (the active target for current development).
2. Search [open and closed issues](https://github.com/stonerl/Thaw/issues?q=is%3Aissue) for duplicates.
3. Note your **display setup** (single vs multiple monitors).
4. Enable **Settings → Advanced → Diagnostics → Enable diagnostic logging**, reproduce the issue, and attach the log from **Reveal Logs in Finder**.
5. Use the [bug report template](https://github.com/stonerl/Thaw/issues/new/choose) — reports without enough detail to reproduce may be closed until more information is provided.

**Support policy:** Thaw versions below **1.2.0** on macOS versions below **15.7.7** are no longer supported. macOS 26 and later are actively supported.
