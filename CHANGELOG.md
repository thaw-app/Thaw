# Changelog

All notable changes to Thaw are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

The `release.yml` workflow reads the section matching the release tag
(`## [tag]`) and uses it as the release notes for both the GitHub Release
and the Sparkle appcast, unless overridden with the `release_notes` input.

## [3.0.0-alpha.1] - 2026-09-03

Thaw 3 is Thaw rebuilt and redesigned for macOS 27. A new engine on the platform's own model, a new settings window, new glass everywhere, and Swift 6.4 underneath. It is de-iced: the code and names inherited from Ice are gone, and what is left is more Thaw than anything before it.

Hey, we have a Discord! Come say hi: [discord.gg/KDfWjWDnR4](https://discord.gg/KDfWjWDnR4).

<a href="https://www.producthunt.com/products/thaw-2?embed=true&amp;utm_source=badge-featured&amp;utm_medium=badge&amp;utm_campaign=badge-thaw-3" target="_blank" rel="noopener noreferrer"><img alt="Thaw - The only app that owns your whole menu bar, in and out | Product Hunt" width="250" height="54" src="https://api.producthunt.com/widgets/embed-image/v1/featured.svg?post_id=1239794&amp;theme=light&amp;t=1788423441056"></a>

Thank you to the more than 80 people who ran the preview builds, sent logs, and told us what broke. Every one of the areas below was shaped by those reports.

---

### Upgrade from 2.x

1. macOS 27 is required. There is no 2.x compatibility layer.
2. Update channel is Nightly for now.
3. The Ice-era settings migrations have been removed. They could never run against the new defaults domain, so nothing is lost by dropping them.

---

### Not here yet

Three things from the 2.1 preview line are still on their way to macOS 27.

- **Scripts.** Script-driven bar modules are being tested by macOS 26 users on the 2.1.0 beta and will be added in a later 3.0 build. The Scripts pane is here as a preview of where they will live.
- **Item triggers.** The full condition engine from 2.1, where an item moves on battery level, the frontmost app, a network, a Focus, and the rest, is not ported yet. What is here is the reveal-on-icon-change rule.
- **Rotating diagnostic logs.**

---

### Menu bar

- **Zen mode** seals the whole bar with one hotkey. Reveals and hover tricks stand down until you toggle it back.
- **Item groups** bundle items so they move as one, including across sections. Same-app clusters group on their own and dissolve on request.
- **Spacer items** create gaps on purpose: pick a width and drag them like any item.
- **Items that ask for attention can surface themselves.** A blinking icon briefly shows the section holding it, with a cooldown so a chatty icon cannot keep the bar open. Off by default.
- **App icons where captures cannot go.** Items nobody can capture draw their owning app's icon, so the Thaw Bar, the layout pane, and search work with Accessibility alone.
- **Presenter mode.** With the camera and microphone watch on, the bar collapses to zen mode while either is in use and restores after. It works alongside zen mode while presenting.
- **Confirmations.** A small capsule under the bar confirms the verbs that otherwise succeed invisibly: zen on, hidden items shown, profile applied.

### Thaw Bar and appearance

- **A Thaw Bar of its own.** Shape, tint, and border for the bar, independent of the menu bar it mirrors, and one per-display section instead of repeated blocks.
- **Adaptive Gradient tint.** A gradient from the wallpaper's two dominant colours instead of one average. Wallpaper changes re-tint the bar at once; the poll stays only for dynamic and aerial wallpapers.
- **Per-Space appearance overrides**, so the bar can dress differently on each Space.

### Layout

- **A standalone layout editor** opens on its own from a hotkey or a `thaw://` action, with glass chrome and last-pane restore. Items can be activated straight from it.
- **Hover spotlighting.** Resting on a tile in the layout pane lights the matching item in the real bar. Clicking it opens the inspector.
- **Displays as a spatial picker**, arranged the way they sit on your desk, with per-display spacing applied inline.

### Search and launchers

- **Search remembers.** Recently activated items sit at the top of an empty query, and selecting a result spotlights the item in the real bar.
- **Item palette (Lab).** A centred launcher for your menu bar items, hidden ones included. Type part of a name or the owning app and press Return.
- **Assisted item palette (Lab).** A large list of every item right where the pointer is, with big rows to read and click.
- **Menu bar magnifier (Lab).** Rest the pointer on the bar and a blown-up slice appears below it. Each icon gets a large outline you can click, and the one you point at is named. Works without Screen Recording; the pixels need it.

### Settings

- **Simple Mode** collapses Settings to one page, ordered by what you touch. Everything it hides is still there when you switch it off.
- **Sidebar by topic.** Menu Bar, App, Automation, and More. Rows carry a plain glyph, groups fold, arrow keys move through rows and Return selects, and a profile strip pinned to the foot switches profiles without opening the Profiles pane.
- **Search in the toolbar.** Results take over the detail column with a result count and an empty state that names the query.
- **What's New and Acknowledgements as reading pages.** A path of releases along the top, one large title with the release date under it, and the notes at reading size on the app's own glass.
- **Tools pane** gathers the troubleshooting helpers in one place, with the destructive ones last.
- **Onboarding** restyled in the same language as the rest of the app.

### Privacy

- **A Privacy pane.** Permissions, the capture inspector that shows exactly what the app reads from the screen, and every network call the app makes, each with a switch and one button to turn them all off. A test fails the build if a network client appears anywhere the list does not account for.
- **Camera and microphone watch (Lab).** A banner names the app that took the microphone, and another says when a camera turns on. While either is in use, Thaw's menu lists what is using it. Banners can be pinned to a display, or follow the pointer, and placed left, centre, or right.
- **Menu bar history (Lab).** When items appeared in and disappeared from the bar, stored in Thaw's own settings and cleared when the experiment is turned off.

### Profiles and Spaces

- **Per-Space profiles.** Bind a profile to a Space the way it binds to a display. Precedence is Focus Filter, then Space, then display.
- **Per-Space presentation.** Show or hide the bar per Space, and see which Space each rule belongs to.

### Automation, Shortcuts, and the command line

- **Rules.** Reveal on icon change with a cooldown, global and per-profile hooks that run a script when a profile applies, a script environment with its own variables and timeout, and a whitelist of apps allowed to change settings over `thaw://`.
- **Shortcuts and Spotlight.** An action opens a chosen item's menu, revealing it first if hidden, alongside actions to reveal hidden items, toggle zen mode, and apply a profile.
- **Control Center widgets** toggle hidden items and zen mode from Control Center.
- **A command-line client.** `thawctl` drives the `thaw://` control plane from a terminal.

### The Lab

- **A home for experiments** you can opt into early. Turning any experiment off returns the app to normal, and each one says exactly what it does.
- **Menu bar overlay.** Your items drawn in a Thaw strip that appears when you point at the space they left, while the system bar keeps its app menus, clock, and modules.
- **Show item details on hover (beta).** A small readout under an item while the pointer rests on it, showing what the item already reports.
- **Hide Finder menus on the desktop.** Clicking the desktop puts Finder's menus in the bar; this covers them until you switch away.
- **Transport bar.** A floating capsule at the bottom of the display your pointer is on, with the active profile, the hidden and always-hidden toggles, zen mode, and a close button. It never takes focus.

### Under the hood

- **Rebuilt from the ground up on a new architecture.** Thaw 3 is a new codebase, not a patched fork. The item manager cluster, AppState, MenuBarManager, the image cache, the layout bar, ControlItem, appearance, and search were written anew; the Ice-branded identifier vocabulary is Thaw's own, with persisted keys pinned so nothing you saved is lost; and the migrations that could never run are gone. The rewrite paid down years of technical debt at the same time: dead machinery and one-case abstractions are deleted, the engine sits behind explicit seams that can be tested in isolation, and the hot paths were rebuilt with performance in mind.
- **Swift 6.4 and strict concurrency.** The `@Observable` migration is complete, with zero `ObservableObject` conformances left. Detached tasks moved onto `@concurrent` callees, workspace notifications are debounced through swift-async-algorithms, and the engine reads its settings through a configuration protocol instead of reaching into AppState.
- **Every ScreenCaptureKit call has a watchdog**, so a capture that never answers cannot hang the refresh loop. An XPC capture helper is built in and off by default until it has been verified on macOS 27.
- **Less idle work.** The polls that used to ask the window server questions whose answers had not changed now latch, memoize, or rate-limit, and the glyph cache publishes only when a glyph actually changed.

## [2.1.0-unreleased]

Hey, we have a Discord! Come say hi: [discord.gg/KDfWjWDnR4](https://discord.gg/KDfWjWDnR4).

Please report issues at [github.com/thaw-app/Thaw/issues](https://github.com/thaw-app/Thaw/issues).

### New

- **Image-change triggers gain comparison modes and a preview (#1006).** An image-change condition can now compare the current icon to its captured reference Fuzzy — ignoring small rendering noise — or Exact, which reacts to any normalized pixel-content difference. The trigger editor shows the captured reference icon and asks for a recapture when an older reference is switched to Exact. Existing saved conditions keep working and read as Fuzzy.
- **Failed automatic moves save a redacted diagnostic report (#994, #1004).** When an automatic move — section placement, new-item relocation, control-divider ordering, saved-layout or profile application, notch-overflow rebalancing — reaches a definitive failure, Thaw persists a redacted report, keeps the newest 20, and offers it through the Settings sheet or a notification that opens the file in Finder. Cancelled, superseded, stale, transient, and input-busy outcomes stay silent; presentation cooldowns prevent alert storms without discarding evidence.

### Menu bar stability

A five-part rework of how Thaw moves items on its own (#999–#1003, #1041):

- Move gestures stay on the menu bar: the press-release guard lives inside the event sequence, so a stalled drag is always released and never leaves the cursor captive.
- Every automatic move runs under a transaction budget with a hard deadline, and a move policy decides per attempt whether to retry or stop — so a stuck move can no longer walk the bar or spin without end.
- Layout editor cache refreshes are transactional, so a dropped refresh can no longer strand a frozen editor.
- Automatic multi-move batches are coordinated: each move re-validates its preconditions while holding the move gate, so user moves invalidate stale batch moves instead of racing them.
- Editor transitions are stabilized: generation-based drag stabilization, stale-thumbnail rejection while a container is frozen, and window-based drag identity that survives Control Center identity resolution.
- Earlier in the series (#993–#998): move outcomes are explicit and attributable, hosted item identities are reconciled safely, persisted identity seeds are bounded, moves are serialized and preflighted, and diagnostic reports redact sensitive values.

### Fixes

- The Thaw Bar preserves its cached glyphs across window ID changes (#1046), so icons no longer blank out when items are recycled behind the scenes.
- No blank slot for the Thaw icon at launch (#1043). The icon's hidden preference was applied only after the first asynchronous settings pass, leaving a blank space in the menu bar until it landed; the preference is now applied synchronously during control item setup.
- The Displays pane says what it does (#1045, #961). Displays with their own settings are now marked "Custom", with a note that they take precedence over the global template — which explains why toggling the template seemed to do nothing. The per-display item spacing control is likewise honest about macOS: spacing is one system-wide value that follows the display hosting the menu bar, so editing is enabled only for that display and the others show their saved value with an explanation.

### Dependencies & localization

- Crowdin sync for `Localizable.xcstrings` (#1040): new Russian and Japanese translations, improved Thai plural formatting, and Russian plural forms for several messages.

## [2.1.0-beta.2]

Hey, we have a Discord! Come say hi: [discord.gg/KDfWjWDnR4](https://discord.gg/KDfWjWDnR4).

Please report issues at [github.com/thaw-app/Thaw/issues](https://github.com/thaw-app/Thaw/issues).

Four fixes, nothing new. The worst of them is not a beta bug at all: changing menu bar spacing could kill Spotlight outright, and it stayed gone until the machine was rebooted (#720, found and fixed by @commanderk33n). Because spacing is re-applied whenever a display connects or disconnects, it fired again on every dock and undock. From the beta.1 reports: revealing a hidden item could drop it on the wrong side of the chevron, so the reveal failed and the item stayed put (#1035); the "Thaw took too long to respond" report turned out to be a Control Center window left behind by an exited Thaw process, freezing the item cache for as long as it stuck around (#1032); and the Capture Inspector was showing people the bottom of their screen instead of their menu bar (#1033).

---

### Upgrade from 2.1.0-beta.1

1. Update in place through Sparkle on the beta channel. Stable stays on 2.0.1 until 2.1.0 leaves beta.
2. No schema or `defaults` changes. Profiles, saved layouts, and hotkeys carry over untouched.
3. If you have been clearing a stuck menu bar with `killall ControlCenter`, you should not need to after this update.
4. Menu bar items that launchd owns, Spotlight and Dock and WindowManager among them, are now restarted through `launchctl` when a spacing change is applied. That is a hard restart rather than the graceful quit they used to get, which is the operation launchd is built for but is still a change in behavior.

---

### Main fixes

1. Changing menu bar spacing no longer kills Spotlight until the next reboot (#720, thanks @commanderk33n). Thaw terminated each menu bar item and relaunched it with `NSWorkspace.openApplication(at:)`, which makes Thaw the launching parent. A system LaunchAgent can carry a launch constraint that permits launchd as its only launching parent, so the kernel killed the new process at exec: every `Spotlight-*.ips` report ends in a CODESIGNING termination, "Launch Constraint Violation", with no frames on the faulting thread and a process that lived about ten milliseconds. Two things then made it permanent. The fallback relaunch retried the same illegal launch and produced a second crash report about eight seconds later, and `com.apple.Spotlight` sets `KeepAlive.SuccessfulExit=false`, so launchd would not respawn it either: `terminate()` is a successful exit. Spacing is re-applied on display connect and disconnect, which is why this landed on every dock and undock. Items owned by a system LaunchAgent are now restarted with `launchctl kickstart -k gui/<uid>/<label>` at both relaunch sites. The label comes from the agent's own plist rather than from the bundle identifier, because the two diverge on exactly the items that matter: `com.apple.dock` is labelled `com.apple.Dock.agent`, `com.apple.systemuiserver` is `com.apple.SystemUIServer.agent`, and nine of the twenty-six LaunchAgent-backed processes on a stock system differ this way, so a bundle-identifier rule would have rescued Spotlight and quietly missed the rest. `launchctl` is declared in `Info.plist` the way the existing `defaults` path is, so it is never resolved through `PATH`.
2. A Control Center window left behind by an exited Thaw no longer freezes the item cache (#1032). Control Center can outlive the Thaw process whose status item it hosted and go on serving the window. The reporter carried one across three relaunches until `killall ControlCenter` cleared it: window 639, tagged under Thaw's own bundle identifier, capturing no image and answering to no owner. Thaw took it for one of its own twice over. It was planned against as an unmanaged item, so live items were moved relative to a window with nothing behind it, and the log has Battery moved to the right of it. It is also self-titled under Thaw's own namespace, which makes it the first signal read as a bar-wide window-name degradation, so every reading that contained it was thrown away as a failed observation: 436 of them across the reporter's three logs, each one holding a cache that had been stale since the orphan appeared. A reorder planned against a frozen cache is the "took too long to respond" the report is titled after. These windows are now dropped alongside the duplicate control items, before the degradation check, which already expects ghost windows to be gone by the time it runs. Ownership is decided by window number rather than by title, so a control item of Thaw's own whose title really has degraded stays in the reading and still reaches that check.
3. Revealing a hidden item lands it on the side of the chevron it was aimed at (#1035). A temporary show drops the item left of the chevron at exactly the chevron's own minX. That coordinate is the boundary itself, so AppKit is free to place the item on either side of it, and here it picked the wrong side: attempt 2 in the reporter's log planned a target of 837.0 and then measured the item at 863.0, past the trailing edge of a 26pt chevron. The ordinal check rejected that landing, correctly. The one-point bias added for #923 already solves this, but it skipped the chevron on the grounds that the chevron divides no sections and so resolves no ambiguity. What makes a drop point ambiguous is that it is an item's own edge; whether the item divides two sections has nothing to do with it. The chevron is biased now too. The retry budget behind that move is also restored: the fast path cut it to 2 in 2.0.0-beta.2 so that a failing retry loop would not show as jitter, which left a reveal one wrong guess away from giving up, and that is where the reporter's bisect lands, since 1.2.0 gave the move all 8 attempts. The second half of the report stays open. A move that exhausts its attempts still delivers a real click to whatever sits under the cursor.
4. The Capture Inspector shows the menu bar rather than the bottom of the screen (#1033). It built its band from `NSScreen.frame`, which puts the origin at the bottom left, and then handed that band to a capture path that assigns it to `SCStreamConfiguration.sourceRect`, where the origin is at the top left and y increases downward. Read the second way, `frame.maxY - menuBarHeight` is a distance measured down from the top of the display, so on a display of height H the inspector selected the strip at H minus the menu bar height: the bottom edge of the screen, and whatever window happened to be sitting there. Nothing downstream could catch it. Both readings produce a band of identical size, so the pixel dimensions in the log looked right, and the rect stayed inside the display so the bounds guard passed. The band now comes from `CGDisplayBounds`, which is already in the coordinate space the capture expects, and the screen bounds, display frame, and computed source rect are all logged, so a future misplacement is legible from a log instead of only from a screenshot.

---

### Dependencies & localization

- Source strings repaired, including the automatic grammar agreement that two of them had lost (#1036).
- Crowdin sync for `Localizable.xcstrings` (#1030, #1037). Russian is the big mover, from 69.3% of the catalogue to 82.6%.
- The build and release workflows run on macOS 27 runners (#1034).
- Copyright headers updated across the project (#1026).
- Two triple-nested closures unnested, which clears both open SonarCloud maintainability issues.

## [2.1.0-beta.1]

Hey, we have a Discord! Come say hi: [discord.gg/KDfWjWDnR4](https://discord.gg/KDfWjWDnR4).

First beta of the 2.1.0 line. This is the wave the 2.0.0 notes pointed at: triggers, groups, zen mode, Simple Mode, spacers, and a Thaw Bar that dresses itself. Anything that changes behavior ships switched off; flip it on when you want it.

---

### Upgrade from 2.0.1

1. Pick the beta channel in Settings → Updates. Stable stays on 2.0.1 until 2.1.0 leaves beta.
2. No schema or `defaults` changes. Profiles, saved layouts, and hotkeys carry over untouched.
3. Trigger conditions are gated per feature under Settings → Developer. Battery and power work out of the box; everything else is a switch you flip deliberately.

---

### Added

- **Item triggers** move a menu bar item when something happens: battery level, power source, frontmost or running app, network, VPN, Wi-Fi, Bluetooth, audio device, displays, a time window, a Focus, a place, Energy Mode, thermal pressure, camera or mic use, a script's exit, or another icon changing. Conditions combine with all/any/none, actions invert, and a wrong verdict costs a brief reveal instead of a rearranged bar. Designed and implemented by @alvst (#735, #965).
- **Item groups** bundle items so they move as one, including across sections, matching the macOS 27 semantics. Same-bundle clusters group automatically and dissolve on request.
- **Zen mode** seals the whole bar with one hotkey. Auto-reveals and hover tricks stand down, and a blinking icon does not get to reopen what you closed. Toggle it again to hand the bar back.
- **Simple Mode** collapses Settings to one page, ordered by what you actually touch. Everything it hides is still there when you switch it off.
- **Tools pane** gathers the destructive troubleshooting helpers in one place, plus announcements and Sparkle feed pinning.
- **Spacer items** create gaps on purpose: pick a width and an optional fill, then drag them like any item.
- **Per-Space profiles** bind a profile to a Space the way it already binds to a display. Bindings use the window server's per-Space `uuid`, since the ID is renumbered at logout. Precedence is Focus Filter, then Space, then display.
- **Wallpaper changes re-tint the bar immediately.** Thaw now watches the wallpaper store instead of polling for it. The poll stays for dynamic wallpapers, which change their pixels without ever rewriting that file.
- **Adaptive Gradient tint** builds the gradient from the wallpaper's dominant colours instead of one averaged brown. Colours are bucketed and taken most-covering first, skipping any too close to one already taken.
- **Items that ask for attention can surface themselves.** A blinking status icon briefly shows the section holding it. A blink is told apart from a clock or a battery percentage by whether the icon keeps returning to a state it already showed. Off by default under Advanced.
- **A Thaw Bar of its own**: shape, tint, and border for the bar, independent of the menu bar it mirrors (#248, thanks @kn666).
- **Hidden icons that refresh at the slider rate.** Captures run through a recyclable XPC helper, so the per-call dictionary leak stays out of the app (#942, thanks @CamilleGuillory).
- **One Per display section**: the repeated per-display blocks collapse into a single picker-driven section.
- **A standalone layout editor** opens on its own, with per-Space appearance overrides and last-pane restore; items can be activated straight from the editor (#985, thanks @alvst).
- **App icons where captures can't go.** Items nobody can capture draw their owning app's icon, so the Thaw Bar, the layout pane, and Search work with Accessibility alone.
- **A hotkey for automatic rehiding** (#665, thanks @nightah).
- **Diagnostic logs that rotate** by size and time (#974) and diagnostics rows you can edit (#976), both by @nk-tedo-001.

---

### Fixed

- **A profile apply no longer walks the visible section into the hidden one** (#1027, thanks @nk-tedo-001). On a three-display Mac after a restart, the reporter's bar went from twelve visible items to one in six seconds. The hidden divider was parked off-screen with two visible-bound items already stranded behind it, and Phase 1 had just declined to rescue them — a parked divider cannot be dragged onto (#899), so it hands off to the per-item pass. That pass then anchored its moves on the stranded items. A drop point derives from its anchor's leading edge, so each move pressed at a point off the display, AppKit dropped the item beside the parked anchor, and the next move anchored on the item just stranded: six desired-visible items followed each other out of the bar. Moves bound for the visible section now require an anchor that is actually on screen, and skip when it is not. Moves into the hidden and always-hidden sections are untouched — parking is how concealment works, and gating those would refuse every move into a collapsed section. A skipped move counts as unenacted, so the arrangement is not written back to the saved order as though it had been achieved.
- **Control Center modules no longer persist under another app's name, and profiles that already carry one heal on load** (#1027). The reporter's `main.json` held `com.techsmith.snagit.capturehelper:Battery`. On a three-display setup, the source-PID resolution matched Control Center's Battery window to Snagit's helper process, the resolved PID became the identifier's namespace, and the wrong spelling persisted. The live item reads `com.apple.controlcenter:Battery`, so it never matched the saved entry again: every apply planned Battery as an unmanaged arrival into the hidden section, and the reporter could not reorder it. No existing guard catches this. The PID did resolve, so the identity is not provisional. The title is not a generic slot, so the item is not transient. And one wrong PID is not a majority, so the #784 gate stayed quiet as designed. What does identify the item is the title: only Control Center names an item "Battery", "WiFi", or "FocusModes". Those titles under any other namespace are now treated as misattributed. The persistence path excludes them the way it excludes an unresolved item, and the load-time prune drops the ghost from saved orders and profiles outright, since the title alone is proof enough and no live twin is needed to confirm it; the module then re-persists under its real name on the next cycle that resolves it properly. The cost of a wrong verdict is small: an app that genuinely titles its item "Battery" or "Clock" keeps its movability and only loses its persisted position. Generic `Item-N` slots are never touched, since a third-party app's own slot is indistinguishable from a misattributed one by title alone.
- **A bulk apply no longer dispatches while the section dividers sit out of order** (#1027). In the same log, both of the reporter's other control items were classified into the hidden section before any apply ran. The dividers were scattered rather than collapsed onto one coordinate, so the zero-width gate from #868 passed while every section assignment derived from that reading was wrong. Both apply paths, the saved-order dispatch and the profile pass's fresh re-read, now refuse a reading that places the visible control item or the always-hidden divider outside its own section. The refusal also attempts recovery: it un-parks a stranded hidden divider and re-seats the visible chevron, so a scrambled bar returns to a state the gate accepts instead of staying stuck. A divider that is absent still passes. A disabled always-hidden section has no divider by design, and a missing divider is what the #849 gate already handles.

---

### Dependencies

- `swift-system` is declared directly; Collections and AsyncChannel joined the lockfile. The last XCTest suites moved to Swift Testing.

## [2.0.1]

Help us translate Thaw at [crowdin.com/project/thaw](https://crowdin.com/project/thaw).

Please report issues at [github.com/thaw-app/Thaw/issues](https://github.com/thaw-app/Thaw/issues).

Five fixes from field reports against 2.0.0, nothing new. The one most people will notice: option-click and double-click on the menu bar toggled the always-hidden section in every 1.x build, and both went dead the moment you upgraded to 2.x (#1012). The largest under the hood: after a restart, the menu bar could sit wherever macOS had dropped the items, and re-applying the profile in Settings refused to run at all (#991). The rest: item previews work again in the layout editor on mixed Retina and non-Retina setups (#990), a drag into an empty collapsed section completes instead of deadlocking or timing out (#988, #1010), and the menu bar appearance follows space switches on multi-display systems, including the macOS 26 setups where the per-display space query stops answering (#794). Two release candidates carried the work; their entries below keep the per-fix detail.

---

### Upgrade from 2.0.0

1. Update in place through Sparkle.
2. If you came from 1.x and never touched the two click-gesture toggles in Settings, General, both come up on after this update, the way they behaved in 1.x. Turn either one off there and Thaw keeps that choice. Anyone who already set them explicitly, on or off, is left alone.
3. No schema or `defaults` changes. Profiles and saved layouts carry over untouched.

---

### Main fixes

1. The 1.x click gestures survive the upgrade to 2.x (#1012). Option- click and double-click on the menu bar toggled the always-hidden section unconditionally in 1.x. 2.0 turned both into opt-in settings that default to off, and the keys behind them did not exist for anyone upgrading, so both gestures silently stopped working with no setting visibly changed. Both now come up on when they have never been explicitly set, and an explicit choice, including off, is never overwritten. Separately, the control items' phantom-click suppression sat in front of the whole event switch and swallowed right-click along with it, so the context menu was unreachable whenever the menu bar transiently had no item windows on the active space. That guard is now scoped to the left mouse-down it was written for.
2. Profile applies survive a missing always-hidden divider (#991). After a restart the divider rests parked offscreen, and on macOS 26 that parked window intermittently drops out of the item list Thaw enumerates. Lookup then returned nil for the divider while downstream steps still treated the pair as fully resolved: applies skipped wholesale ("always-hidden divider unresolved while its section is enabled") or abandoned after the hidden-boundary moves had already run ("control items degraded before moving AH_ctrl" in the attached log, four milliseconds after a clean tag resolution). The reporter's bar never matched the saved profile, and manual re-applies failed the same way. The control-item pair now recovers the divider from its own window record, the authoritative channel the hidden divider has had since #754, and refuses to adopt a lookalike window from a duplicate Thaw instance. A divider the window server no longer knows is still refused, now under an accurate message instead of "control items degraded".
3. Layout editor previews render on mixed-scale display setups (#990). Composite captures compared pixel width against bounds times the display scale and rejected any mismatch, but on a 1.0x external beside a Retina display the capture backend picks its own scale: the log recorded 70 rejections, an empty image cache, and gray placeholders for every item. Both composite paths now derive the scale from the capture itself, the same check single-item captures have used since #851, and degenerate zero-width windows are filtered from the bounds union so one orphaned window cannot reject a whole batch.
4. A drag into an empty collapsed section completes instead of refusing forever (#988, #1010). The #923 guard refuses an editor drag whose destination divider is parked offscreen and suggests opening the section first; with every item in always-hidden there was nothing to open and nowhere to drop, which is exactly the reporter's bar. Thaw now reveals the empty destination, retargets the drag onto the freshly revealed divider, and re-conceals the section once the item settles. The first cut of that reveal expanded only the destination section, and the always-hidden divider parks to the left of the hidden section's content: with the hidden section collapsed behind its 10000-point spacer, the revealed divider was re-placed just left of that still-parked content and never came onscreen, so the drag still timed out into the same refusal. The reveal now expands the hidden section alongside the always-hidden section and restores both once the item settles. If the divider does not return within two seconds the old refusal stands. A drag cancelled mid-reveal, or one the move watchdog gives up on, restores the sections' previous state instead of leaving them showing. Disabled sections never reveal.
5. Overlay panels stay on the space you are looking at (#794). A panel kept whatever space was current when it was last shown; with "displays have separate spaces" enabled, every ctrl-arrow switch revealed a vanilla menu bar on both displays, and the tint, shape, and background appeared only on the space that was current at launch. Panels now check per display whether they sit on that display's current space and re-home only when actually stranded. Because the check compares each panel against its own display, the fullscreen drift that forced the old flag's removal cannot return. A re-check shortly after each switch re-shows a panel that a raced space read leaves behind, so the old 60-second housekeeping timer stays a backstop rather than the recovery path. On the macOS 26 setups behind the reports that stayed open after that first cut, the per-display space query stops answering, and the code read the silence as "the overlay panel is already in place", so the tint, shape, and background stayed stuck on the launch space for every recovery path. The panel on the display that owns the active menu bar now falls back to the global active space, which coincides with that display's current space by definition. The decision logs its inputs, so any report that survives this can be pinned to a branch.

---

### Dependencies & localization

- Crowdin sync for `Localizable.xcstrings` (#992, #1019, #1021).
- github-actions group bumped with four updates (#1011), and `softprops/action-gh-release` bumped on its own (#1018).

## [2.0.1-rc.2]

Please report issues at [github.com/thaw-app/Thaw/issues](https://github.com/thaw-app/Thaw/issues).

Three fixes from rc.1 field reports, nothing new. The one most people will notice: option-click and double-click on the menu bar toggled the always-hidden section in every 1.x build, and both went dead the moment you upgraded to 2.x. The other two are narrower. A drag into an empty always-hidden section still timed out when the hidden section happened to be collapsed as well, and the space-switch re-homing that landed in rc.1 did nothing at all on the macOS 26 setups where the per-display space query stops answering.

---

### Upgrade from 2.0.1-rc.1

1. Update in place through Sparkle.
2. If you came from 1.x and never touched the two click-gesture toggles in Settings, General, both come up on after this update, the way they behaved in 1.x. Turn either one off there and Thaw keeps that choice. Anyone who already set them explicitly, on or off, is left alone.
3. No schema or `defaults` changes. Profiles and saved layouts carry over untouched.

---

### Main fixes

1. The 1.x click gestures survive the upgrade to 2.x (#1012). Option-click and double-click on the menu bar toggled the always-hidden section unconditionally in 1.x. 2.0 turned both into opt-in settings that default to off, and the keys behind them did not exist for anyone upgrading, so both gestures silently stopped working with no setting visibly changed. Both now come up on when they have never been explicitly set, and an explicit choice, including off, is never overwritten. Separately, the control items' phantom-click suppression sat in front of the whole event switch and swallowed right-click along with it, so the context menu was unreachable whenever the menu bar transiently had no item windows on the active space. That guard is now scoped to the left mouse-down it was written for.
2. A drag into an empty, collapsed always-hidden section completes even when the hidden section is collapsed too (#1010). The reveal added in #988 expanded only the destination section, but the always-hidden divider parks to the left of the hidden section's content: with the hidden section collapsed behind its 10000-point spacer, the revealed divider was re-placed just left of that still-parked content and never came onscreen. Every such drag timed out into the "open the section first" refusal, advice that could not help, since only expanding the hidden section puts the always-hidden boundary onscreen. The reveal now expands the hidden section alongside the always-hidden section and restores both once the item settles.
3. Menu bar appearance re-homes after a space switch even where the per-display space query goes quiet (#794). On the macOS 26 setups behind the reports still open against rc.1, that query stops answering, and the old code read the silence as "the overlay panel is already in place", so the tint, shape, and background stayed stuck on the launch space for every recovery path. The panel on the display that owns the active menu bar now falls back to the global active space, which coincides with that display's current space by definition. The decision logs its inputs, so any report that survives this can be pinned to a branch.

---

### Dependencies & localization

- Crowdin sync for `Localizable.xcstrings` (#992).
- github-actions group bumped with four updates (#1011).

## [2.0.1-rc.1]

Please report issues at [github.com/thaw-app/Thaw/issues](https://github.com/thaw-app/Thaw/issues).

Four fixes from field reports, nothing new. The largest: after a restart, the menu bar could sit wherever macOS had dropped the items, and re-applying the profile in Settings refused to run at all (#991). The always-hidden divider's window had dropped out of the item list while parked offscreen, so every layout apply that needed it either skipped itself or quit partway through. Thaw now recovers that divider from its own window record instead of searching the list. The rest: item previews work again in the layout editor on mixed Retina and non-Retina setups (#990), a drag into an empty collapsed section completes instead of deadlocking (#988), and overlay panels follow space switches on multi-display systems (#794).

---

### Upgrade from 2.0.0

1. Update in place through Sparkle.
2. No settings, schema, or `defaults` changes in this release. Profiles and saved layouts carry over untouched.

---

### Main fixes

1. Profile applies survive a missing always-hidden divider (#991). After a restart the divider rests parked offscreen, and on macOS 26 that parked window intermittently drops out of the item list Thaw enumerates. Lookup then returned nil for the divider while downstream steps still treated the pair as fully resolved: applies skipped wholesale ("always-hidden divider unresolved while its section is enabled") or abandoned after the hidden-boundary moves had already run ("control items degraded before moving AH_ctrl" in the attached log, four milliseconds after a clean tag resolution). The reporter's bar never matched the saved profile, and manual re-applies failed the same way. The control-item pair now recovers the divider from its own window record, the authoritative channel the hidden divider has had since #754, and refuses to adopt a lookalike window from a duplicate Thaw instance. A divider the window server no longer knows is still refused, now under an accurate message instead of "control items degraded".
2. Layout editor previews render on mixed-scale display setups (#990). Composite captures compared pixel width against bounds times the display scale and rejected any mismatch, but on a 1.0x external beside a Retina display the capture backend picks its own scale: the log recorded 70 rejections, an empty image cache, and gray placeholders for every item. Both composite paths now derive the scale from the capture itself, the same check single-item captures have used since #851, and degenerate zero-width windows are filtered from the bounds union so one orphaned window cannot reject a whole batch.
3. A drag into an empty collapsed section completes instead of refusing forever (#988). The #923 guard refuses an editor drag whose destination divider is parked offscreen and suggests opening the section first; with every item in always-hidden there was nothing to open and nowhere to drop, which is exactly the reporter's bar. Thaw now reveals the empty destination, retargets the drag onto the freshly revealed divider, and re-conceals the section once the item settles. If the divider does not return within two seconds the old refusal stands. A drag cancelled mid-reveal, or one the move watchdog gives up on, restores the section's previous state instead of leaving it showing. Disabled sections never reveal.
4. Overlay panels stay on the space you are looking at (#794). A panel kept whatever space was current when it was last shown; with "displays have separate spaces" enabled, every ctrl-arrow switch revealed a vanilla menu bar on both displays, and the tint, shape, and background appeared only on the space that was current at launch. Panels now check per display whether they sit on that display's current space and re-home only when actually stranded. Because the check compares each panel against its own display, the fullscreen drift that forced the old flag's removal cannot return. A re-check shortly after each switch re-shows a panel that a raced space read leaves behind, so the old 60-second housekeeping timer stays a backstop rather than the recovery path.

## [2.0.0]

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

### Features

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

## [2.0.0-rc.5]

Please report issues at
[github.com/thaw-app/Thaw/issues](https://github.com/thaw-app/Thaw/issues).

Planned as the last release candidate before 2.0 stable. Almost all of it comes from field logs, and the reports fall into two clusters: layout repair that damaged the arrangement it was trying to fix (#958, #863), and scans that re-probed every running application until the machine stuttered and every item answered to "Menu Bar Item" (#956).

---

### Upgrade from 2.0.0-rc.4

1. Update in place through Sparkle.
2. Move budgets now default to 250 ms, or 350 for Bento Boxes. An explicit
   `defaults write` override still takes precedence over either value.

---

### Main fixes

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

## [2.0.0-rc.4]

Please report issues at
[github.com/thaw-app/Thaw/issues](https://github.com/thaw-app/Thaw/issues).

This release closes the field reports against rc.3, hidden items dead
for the first minute after launch, and a cache stall with no deadline at
all, and pays down the debt that made them possible: the item manager's 11,500-line file, the hand-rolled identity
matching that drifted, and a test suite that wrote into the real settings
of whoever ran it.

---

### Highlights

- **Hidden items work from launch, and the cache can no longer stall for good**: on a cold start the item cache froze for a full minute on unresolved identities: every Thaw Bar tooltip read "Menu Bar Item" and every click silently did nothing until the settling deadline expired (#943). In the worse interleaving the settling task deadlocked awaiting itself, past every deadline. One report had the cache rejecting every refresh for 20+ hours, with the Visible row in Settings → Layout permanently empty (#945).
- **The Thaw icon stops drifting left across restarts**: the stalled early apply executed a minute late with the desired order it had narrowed at launch, when only a handful of identities had resolved. Everything that resolved during the stall was re-inserted as "unmanaged" at saved indices, which changed the chevron's planned neighbors and moved it left of the leftmost item; macOS remembers the new position, so each restart ratcheted it further (#947).
- **Items stop shuffling mid-session on localized systems**: saved-order ghosts namespaced by a localized app name (`Control Centre:WiFi`, minted while a bundle ID transiently read nil) counted as "real owners" and deleted their genuine `com.apple.controlcenter` twins from the saved order on every load. The live items then planned as unmanaged and were repositioned by every apply, with the cursor contested for each synthetic drag (#949).
- **Spanish onboarding restored**: two strings shipped as translated-but-empty, so Spanish systems rendered a blank tour slide description and a blank New Items badge hint.
- **XPC session race closed**: a stale cancellation handler could tear down a healthy, newer session and race the lock every other access went through.

---

### Menu bar & layout

- The settling-period early apply no longer waits for settling to end while holding the serial cache gate. The wait deadlocked the pair both ways: when the launch cache cycle owned the gate, settling's early exit needed a cache cycle the held gate rejects, so it ran the full 60 s deadline with the item cache frozen on fallback tags: generic names in Thaw Bar and Search, and every click aborted with no return destination (#943). When the settling task's own poll owned the gate, the apply awaited the very task it was running on, and the deadline check inside that blocked loop could never fire, so the gate stayed held indefinitely and every later recache was rejected (#945).
- Clicking an item whose cached tag predates source-PID resolution re-maps it onto its freshly fetched counterpart by windowID, so the click survives a stale cache snapshot instead of dying in the return-destination lookup (#943).
- Because the early apply now runs the moment it is dispatched, it plans against the bar it narrowed itself to. Executed at the deadline instead, its restriction inverted: identities that resolved during the stall were no longer provisional (which excludes them) but "unmanaged" (which re-inserts them at saved indices), and the re-insertion handed the chevron a move to the far left of the bar (#947).
- Saved-order pruning no longer counts a localized display-name namespace as a real owner, and drops such a ghost when its canonical twin exists: the Control Center entry sharing its title, Thaw's own control items by their reserved titles, or a real owner claiming the same non-generic title. A display-name entry with no twin survives, since it may be the only identity a bundle-ID-less app ever got (#949).
- The namespace fallback recovers a transiently nil bundle ID through the app's bundle URL before reaching for the window's owner name, so localized ghosts stop being minted in the first place (#949).

### XPC service

- The session cancellation handler cleared the stored session outside the lock that guarded every other access, and a handler outliving its session could clear a newer one created after it. Storage now synchronizes internally, and invalidation is identity-guarded so only the cancelled session is dropped.
- The single-window `sourcePID` request was dead wire protocol, since the batch request replaced it in production, yet its round-trip tests were the only wire-format coverage at all. The request is gone and the tests now exercise the batch case both sides actually use.

### Localization

- The Spanish descriptions for the Hotkeys & Automation tour slide and the New Items badge hint were empty strings marked translated. A catalog sweep found exactly these two; both are filled in the register the catalog already uses.

### Internal

- `MenuBarItemManager.swift` (11,526 lines) is now a folder of per-concern files cut along its existing MARK seams, each importing only what it uses; sonar and the SwiftLint input list follow the new paths.
- Item identity matching (tag plus effective PID), the click-target refetch chain, and live-bounds reads are single-sourced helpers instead of hand-rolled copies across the manager and the IceBar, the same drift that produced #943.
- The test process points the `Defaults` facade at a scratch suite before any test runs, so no suite can write into the real `com.stonerl.Thaw` domain of whoever runs the tests. The tour-slide test that failed on Spanish-locale machines while passing on English CI is green everywhere.
- The search panel reads `AppState` from its SwiftUI environment instead of reaching through the item manager's back-pointer, which no external caller uses anymore.

## [2.0.0-rc.3]

Please report issues at
[github.com/thaw-app/Thaw/issues](https://github.com/thaw-app/Thaw/issues).

Almost all of this release is one reliability track through the launch/move
pipeline, driven by field logs from rc.2.1: cold-start restore, move planning,
control-item pairing, and the persist gates that decide whether any of it
reaches disk. Each storm fix exposed the next failure mode in the same chain,
so they land together.

---

### Highlights

- **Launch restore actually runs**: the saved layout is applied at cold start instead of losing to a move cooldown that launch itself had stamped ~0.4 s earlier (#881, #900).
- **Storms are bounded**: a failed or parked-divider move can no longer hijack the cursor indefinitely or write a half-finished order into `savedSectionOrder`.
- **Control-item pairing repaired**: Thaw's visible chevron is no longer mistaken for the hidden divider, the mispair behind hidden sections reading zero width (#923, #924, #927).
- **Memory leak closed**: recache backoff stops the CA fence port growth reported at 47 GiB on macOS 26 (#933).
- **Field repair**: `Thaw --reset-layout` clears persisted order and re-seeds dividers without starting the app.

---

### Menu bar & layout

#### Cold start and settling
- Launch restore bypasses the saved-layout and move cooldowns that launch itself stamped. `applySavedLayout` had been rejected on every launch by the cooldown its own chain created when it moved our control item (#881).
- Early apply moves identities whose `sourcePID` has already resolved rather than waiting out the full resolution pass, which runs ~8 s on a dense bar while Control Center is slow to answer. The match is exact on `uniqueIdentifier`, so an unresolved sibling cannot be moved by mistake.
- The Thaw icon relocates immediately when macOS parks it left of the hidden divider, instead of leaving the menu bar without a Thaw icon for the whole settling period.

#### Move planning and storm bounds
- The full-sort planner that rearranged the entire bar is gone. Bulk apply keeps the per-item and control-item paths (#885).
- Move success is verified by adjacency in a single snapshot instead of exact `CGFloat` coordinate equality against a target that reflows mid-drag. Stale destinations abort rather than burn retries.
- Failed move attempts no longer starve the operation timeout budget.
- An unfinished bulk apply no longer writes its partial order into `savedSectionOrder`.
- Automatic re-applies are capped: one retry after an unfinished batch, then a 60 s cooldown, and a batch abandons after three consecutive failures. Notch-overflow ejections now go through the failure ledger (#900).
- An automatic bulk apply waits for a 300 ms lull in input before issuing its sequence, capped at 2 s so the batch still runs. A batch holds the cursor for its whole length, so one dispatched the instant a late arrival is noticed used to take the pointer mid-interaction and then contest it move by move (#899, #723).
- Synthetic move events address the window's owner instead of the app that owns the item. On macOS 26 Control Center hosts every status item window, so those are different processes; addressing the host is what lets a slot with an unresolved owner move at all, and it clears move failures that were timing out against a process that did not own the drag (#900, #923, #924).
- Bulk apply restores membership in the hidden and always-hidden sections but no longer reorders *within* them. Each of those moves costs a cursor hijack and a synthesised drag to land an item thousands of points off-screen, where Thaw Bar renders from the cache anyway. Dropping them is most of what shortens long batches on the bars where length hurts.
- Parked off-screen items are excluded from the `H_ctrl` drag anchor, and a parked divider skips the boundary move and records ledger backoff (#899).
- Late-arrival detection ignores unresolved identities, so a `sourcePID` flap no longer reads as a bar full of new items.
- Display-sized overlay windows (Droppy's drag catcher, for one) are no longer treated as an open menu.
- Diagnostics log a section-order digest instead of counts alone.

#### Control items and identity
- Control-item pairing no longer selects Thaw's visible chevron as the hidden divider. The mispair made the hidden section read zero width, so every item landed visible after a restart (#927), hidden icons left of the notch had no region to render into (#924), and layout-editor drags had no divider to verify against (#923).
- Divider seeding and restore write through the section-divider guard, and hide or removal restores divider positions too (#890).
- `preflightSetup` no longer re-stamps the hidden divider to `1` on every launch and status-item recreation. That second write had been draining `savedSectionOrder` across launches, 64/46/12 down to 42/52/12 in two clean starts (#895).
- Source PID resolution no longer skips Thaw's own disabled dividers, which is the normal state of a collapsed section (#899).
- AX-correlated identity can promote an unresolved Control Center placeholder, so layout-editor moves and saved order use the owning app's identifier (#905).
- Owner-titled degraded readings (`bundleId:bundleId`) count as a failed observation rather than a new bar, so they stop minting a second identifier set (#881, #927).
- Stale saved identifiers stop matching once the bar retires them, and foreign items are no longer namespaced under `com.stonerl.Thaw:`.
- Source PIDs are re-asked when the first scan after login leaves items provisional, and a dead cached PID no longer wins over live resolution.
- Silent move refusals log the stage, gate, and owner instead of a bare `cannotComplete` (#905).

#### Persist gates
- An emptied hidden section (everything dragged into Visible) no longer latches `hiddenSectionHasRoom` permanently read-only. A genuine collapse still refuses; parked off-display items are what tell the two apart (#868).
- Temporarily shown items no longer register as layout drift, so opening a hidden item's menu stops dispatching a bulk apply that dumps the hidden section (#907).
- The always-hidden display-spread gate ignores parked items. It had been skipping `saveSectionOrder` on every cache cycle on multi-display setups, 1088 skips and zero writes in one day of field logs, which left always-hidden items looking new and let quitting any app drag them back to Visible (#930, thanks @nightah).
- LyricsX-style lyric titles collapse to a stable identity, so a song change stops minting new items (#815, thanks @yoodu).
- Saved-layout entries that can never match a live item again are pruned.

---

### Settings, profiles & onboarding

- Profile list rows preview the saved layout next to the key behaviour settings (#887).
- "Update All" marks a profile active when its capture matches the running state (#904).
- Applying a profile uses that profile's spacing offset instead of a stale `0` (#903).
- Profiles prune Control-Center-hosted empty-title identifiers that can never match a live item.
- The layout editor names the display it is showing (#886).
- Independent shape and border settings for the menu bar overlay and Thaw Bar (#248, thanks @kn666).
- Per-display option to route only the always-hidden section to Thaw Bar (#751, thanks @MashnoorKek).
- Optional Advanced toggle moves the pointer onto a revealed search result, off by default (#769, thanks @brucemakes012).
- Sections holding nothing but the new-items badge accept drops again (#897, thanks @alvst).
- Advanced settings reset clears every persisted boolean, not just some of them (#910, thanks @YuriNachos). The two toggles added later in this cycle, "Arrange menu bar items" and "Move the pointer to revealed items", are covered too; leaving automatic arrangement off and then resetting to defaults used to keep it off with nothing on screen to explain why layouts stopped restoring.
- `leftAligned` and `rightAligned` accepted as valid `iceBarLocation` values (#911, thanks @YuriNachos).
- Settings search weights un-inverted: title now outranks keywords (#918, thanks @YuriNachos).
- Icon refresh rate normalized onto one grid shared by the slider, URI handler, live capture floor, and Defaults: off, or `1/n` seconds for integer `n` in 1…30 (#929, thanks @CamilleGuillory).
- Relaunches after a revoked permission show the onboarding permissions flow rather than the pre-redesign `PermissionsView`.
- Auto-rehide `focusedApp` and timed strategy guards restored after a merge dropped them.
- New CLI: `Thaw --reset-layout` clears persisted order, pinning, and relocation bookkeeping and re-seeds divider positions without starting the app. It and the settings reset both clear the stale-identifier ledger.

---

### Appearance, capture & IceBar

- ScreenCaptureKit picks the display with the largest intersection and rejects zero-area ones, and refreshes shareable content when cached topology leaves a window looking orphaned (#794, thanks @bpresles).
- Screen recording no longer pushes notch overflow into a `cannotComplete` ejection loop that holds the cursor (#935, thanks @Zophiekat).
- IceBar color sampling survives a horizontal bar that overflows to full screen width; the inset-frame math falls back to panel center instead of dividing by zero (#915, thanks @YuriNachos).
- `IceGradient.averageColor` returns `nil` on an all-nil sample count instead of averaging by zero (#914, thanks @YuriNachos).

---

### Performance & memory

- Change-detector recaches back off while control-item lookups keep failing, exponential and capped at 60 s. Each rebuild was leaking a CA fence Mach port on macOS 26; bounding the retry cadence stops the 47 GiB owned-unmapped growth reported against rc.2.1 (#933, thanks @slatlasdev). This bounds the storm, it does not patch AppKit's `NSSceneStatusItem`.
- No-op status-item rewrites on state reassignment dropped, same leak class.

---

### Platform & engineering

- `swift-subprocess` 1.0.0 adopted; the env trampoline is gone.
- `AlphaChannelView` centralizes alpha-channel access and transparency scanning, so bounds validation happens in one place instead of in each `isTransparent` implementation.
- `LayoutSolver` base-ID extraction deduplicated; three inline copies and a dead helper became one (#906, thanks @YuriNachos).
- Statement coverage raised toward 90% by splitting untestable live AppKit / WindowServer paths out of `ProfileManager` and `DisplaySettingsManager` and covering the decision logic that remains (#916).
- New suites around the storm bounds: layout storm replay, move timeout, section-order digest, control-item seeding and recovery, stale destination, unfinished batch, early-apply restriction, parked divider, section geometry, placeholder alias, Thaw Bar routing.

---

### Release, CI & docs

- Workflows migrated to Blacksmith runners (#901), then narrowed to the release workflows.
- CodeQL runs on GitHub-hosted macOS 26.
- Issue triage keeps regressions open instead of closing P0 reports (#882, thanks @jamesyc), and no longer trips its own threat detection.
- Agentic workflows upgraded to v0.85.4; native GitHub issue taxonomy adopted (#867).
- OpenSSF Best Practices badge moved from Silver to Gold; README badges and links reworked.
- github-actions dependency group bumped (#926).

---

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

### Known limitations

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

## [2.0.0-rc.2.1]

### Hotfix

- **Hidden divider boundary and layout-editor drags**: repair the visible/hidden boundary when `H_ctrl` drifts before the per-item reorder pass, so `applyProfileLayout` no longer reports "all items already in correct positions" while the whole hidden section sits misplaced. Drops into an empty hidden section that only contains the new-items badge no longer snap back, and persistent status-level windows (shelf/HUD) no longer defer every move, though deferral still applies while the pointer is inside a long-open menu (#880, fixes #879).

---

This RC is a large reliability and platform update: menu bar identity/ordering, layout persistence, notch overflow, settings UI, Swift 6.2 / concurrency, and Sparkle update hosting.

---

### Highlights

- **Menu bar reliability overhaul**: safer saved-layout apply/persist, stronger item identity matching, and fewer false “reorder storms,” especially with Control Center items, dynamic titles, and multi-display setups.
- **Settings & onboarding refresh**: redesigned settings UI, glass tour onboarding, stronger AX identity / click paths.
- **Swift 6.2 + approachable concurrency**: MainActor default isolation on the app target, AXSwift6, EventTap synchronization, and cleanup of pre–Swift 6 GCD/Timer patterns.
- **Update distribution**: Sparkle ZIP/deltas/appcast publish to `thaw-app/updates`, with a mirror for legacy `stonerl` Pages installs.

---

### Menu bar & layout

#### Identity, ordering, and clicks
- Deterministic visual ordering with stable identifier tie-breaks (no more shuffle when `minX` ties).
- Volatile metric titles (e.g. `CPU 12%` → `CPU 43%`) canonicalized so saved layouts and failure ledgers keep matching; prune stale title-variant saved entries that fueled reorder storms (#842, thanks @danielhopkins).
- Stop provisional identities from scrambling saved layout (#863).
- Failure ledger stamped with build version so marks clear on update; avoid exclusivity violation when persisting the ledger (thanks @VailElla).
- Click reaction verification: success only if the owner shows a real UI reaction, not just event delivery.
- AX identity catalog + ControlItemPair frame fallback (fixes silent hidden-section death when control items could not be identified, #754).
- Optional AX click delivery (`useAXClickDelivery`, default off) with synthetic-click fallback.
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
- Restore unresolved-`sourcePID` gate in `applySavedLayout`.
- Ignore unresolved Control Center placeholders (#810, thanks @VailElla).
- Resolve parked items titled with their bundle ID (e.g. Little Snitch) (#709, #795 / #797, thanks @lathe-agent-oa).
- Restore legacy profile layout snapshots (#778 / #779, thanks @ShiroKSH).
- Delete profile manifest entries even when the file is already missing.
- Negative-cache TTL for source PID lookups uses per-window backoff instead of a flat 60s (#856, thanks @lathe-agent-oa).

#### Notch overflow
- Only run overflow on the main display; fail closed if active menu bar display is unknown (#808 / #809, thanks @lathe-agent-oa).
- Keep the visible control item in place during overflow (#742).
- Keep overflow running outside profile applies.
- Avoid redundant full-sort replays (#822, thanks @alvst).

#### Moves, rehide, and multi-instance
- Defer item moves while a menu bar item menu is tracking.
- Require stable divergence; suppress bulk cursor warps (#705, #723, #736, #750).
- Stop bulk-apply pointer hijack; release on user input.
- Keep menu bar move events out of screen corners, which stops Hot Corner / Show Desktop false triggers (#625, #766 / #774, thanks @ZeterMordio).
- Recover blocked items before alerting on hidden-section drags (#744).
- Recover control items after lookup failure.
- Bail instead of trapping on inverted control-item order.
- Keep timed rehide armable after deferred rehide; anchor rehide to a neighbor in the item’s own section so temporarily shown items are not rehidden into Visible (#859 / #860, thanks @andredlng).
- Prevent duplicate Thaw instances from competing (#821, thanks @alvst).
- Avoid repeated source PID cache scans (#820, thanks @alvst).
- Each layout-reset waiter gets its own cache continuation.
- Configurable pre-move input-pause threshold (#756, thanks @subway-jack).
- Fall back to Thaw Bar when hiding app menus under fullscreen (#740 / #741, thanks @auspic7).
- Defer/stabilize moves that previously relocated system modules mid-interaction (e.g. AudioVideoModule / WeType, #746) and reduced cursor teleport / dance storms (#718, #723, #750).

---

### Settings, profiles & onboarding

- **Settings UI redesign** (native grouped forms, relocated options, refreshed Ice UI primitives, sidebar search).
- **Glass tour** onboarding in first-launch and settings.
- Unconfigured displays fall back to **global configuration** instead of hardcoded defaults (fixes spacing resets on Space/display changes).
- Ice V1 appearance data converted at import time.
- Cleared hotkey bindings removed instead of persisting JSON `null`.
- Authorization retry allowed after denial (#780 / #781, thanks @VailElla).
- Full onboarding button hit targets (#724, thanks @eli-yip).
- IceBar naming leftover on an Advanced setting corrected (#829).
- Settings About/repository URL updated (thanks @cbguder).
- Hidden debug flags moved into the Defaults registry.
- Unreachable Ice-era migrations removed.
- Layout reset target picker with legacy section moves.

---

### Appearance, capture & IceBar

- Tint no longer covers menu bar items; tint renders above the menu bar under Reduce Transparency (#844, #700).
- Capture bounds validated before WindowServer handoff (#759 / #813).
- Individual captures use the captured scale (layout icon sizing, #703).
- SCStream pinned to 32BGRA; shareable-content fetches coalesced.
- Image cache: LRU/concurrency overhaul, lossless disk keys, rate-limited on-screen capture, stale display ID fallback (#749, thanks @hxu).
- Memory: detach cropped glyphs, lower icon refresh, stop background captures (#680).
- Tooltips stay above Thaw Bar / IceBar grid (#760 / #782, thanks @VailElla) with watchdog placement (#734).
- Cursor restore after profile apply uses CoreGraphics space (fixes multi-monitor warp).
- Virtual display resolver removed (brief resolution / screen-shrink side effects, #708).

---

### Accessibility, hooks & events

- Bounded AX messaging timeouts in the item service and event path (#767).
- Consolidated item failure ledgers; quieter expected `procNotFound`.
- Hook timeouts bounded with process-group teardown; teardown restored after Subprocess 0.5 upgrade.
- Mouse-moved handling throttled by time, not event count.
- Shared/adaptive Mission Control detection (#777).
- EventTap shared runtime state synchronized.
- Clicking items in Thaw Bar no longer spikes CPU via runaway work (#757).

---

### Performance

- Rate-limited on-screen image capture path.
- Memoized per-row item search work.
- Shared Mission Control detection.
- Time-based mouse-moved throttle.

---

### Platform & engineering

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

---

### Release, CI & docs

- Sparkle payloads published to **`thaw-app/updates`** (#840); DMGs remain on GitHub Releases.
- Appcast mirrored to legacy **stonerl Pages** (#843).
- Org CI / brand-assets adoption; Sparkle no longer auto-publishes on every tag push.
- OpenSSF / Scorecard / CodeQL / SLSA provenance / OSV SCA hardening; Sonar coverage path fix.
- README restyle/restructure; `RELEASES.md`, verifying releases, governance/security docs; contribution/install docs (thanks @t4sh); URI scheme docs (thanks @davidnichols-ops).
- Crowdin / localization syncs (#694, #804–#807).

---

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
