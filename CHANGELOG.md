# Changelog

All notable changes to Thaw are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

The `release.yml` workflow reads the section matching the release tag
(`## [tag]`) and uses it as the release notes for both the GitHub Release
and the Sparkle appcast, unless overridden with the `release_notes` input.

## [Unreleased]

## [2.0.0]

Please report issues at
[github.com/thaw-app/Thaw/issues](https://github.com/thaw-app/Thaw/issues).

Hey everyone. Thaw 2.0 rebuilds the app around macOS 26 (Tahoe): Liquid
Glass throughout, a redesigned settings surface, an automation layer built
on `thaw://`, and a menu bar pipeline rewritten around item identity,
layout persistence, and knowing when to leave the bar alone. The cycle is
sixteen releases long: `1.3.0-beta.1` shipped Settings Profiles in April,
fifteen betas followed it, and six release-candidate builds carried the
work home. Nearly everything after beta.15 came out of field logs — real
menu bars misbehaving in ways no test caught. This entry walks the whole
run by theme; the RC sections below keep the detailed per-fix notes.

---

### Highlights

#### Built for macOS 26

- Native Tahoe support with the Liquid Glass design system across the main app, Settings, Search, and onboarding, including the glass tour for first launch.
- New macOS 26-style app icon designed and delivered by @JamesLautner (issue #5), with the clear-mode display refinement reported by @a35hie (#616).
- The minimum deployment target is now macOS 26. Systems on macOS 14 or 15 stay on the 1.x line (#427).

#### Profiles & Focus

The feature that started the cycle, from `1.3.0-beta.1`, implemented by @nightah:

- Save your entire Thaw configuration as a profile and switch instantly — create, duplicate, rename, and delete profiles; import and export them for backup or sharing; update an existing profile with the current layout, configuration, or both.
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
- The `.notch` shape kind splits the background at the physical notch, with a notch margin slider (0–15 px) and four-corner end-cap control; it behaves as full width on displays without a notch.
- Per-display menu bar spacing applies dynamically, preserves settings for disconnected displays, skips the full relaunch when only resolution changed (#551), warns before spacing relaunches with the choice saved per profile (#691), prompts before first apply, and falls back to a global template.

#### Thaw Bar & IceBar

- Horizontal, vertical, and grid layouts; left/right alignment options; panel resizing that follows its content; pill shapes that match the container; grid columns with per-column max widths.
- Independent shape and border settings for the overlay versus Thaw Bar (#248), and a per-display option to route only the always-hidden section to Thaw Bar (#751).
- Item reveal survives CPU load, a grace period stops the "no items" flash on display changes, and the live window ID is re-checked after sleep.
- Icon foreground colors adapt to each screen's menu bar background, including notched MacBooks and secondary displays.

#### Item identity & restoration

- Section restoration follows one deterministic path — baseIdentifier match to saved order, else macOS placement — replacing the namespace fallbacks that pulled unsaved items visible on restart. Blocked items are skipped instead of forced, and placed items stop drifting back into the new-items section.
- Startup settling waits on source-PID resolution rather than timers, auto-relocation is suppressed while settling runs, and stale PID resolution can no longer mis-namespace items after cmd-drag moves.
- A serialized cache gate prevents concurrent rebuild races, and lightweight 60-second polling catches late-registering items from background-only apps that never become frontmost.
- The item cache re-checks after every app launch so late arrivals sort into place, confirms stability across two reads, and keeps `displayID` handling off the main thread.
- LayoutReconciler consolidated the scattered icon-restore paths into one phase-based orchestrator with deferred post-apply refreshes and chevron position persistence.
- Menu bar height queries lost the `-1` sentinel that poisoned the height cache, and item bounds verify against the window server so temporary system items (recording indicators, mic, camera) leave no stale ghosts.

#### Control Center–hosted items

- MarkerPairResolver identifies proxies hosted by Control Center (Little Snitch among them) through width-matched marker windows.
- On single-display Macs a headless virtual display forces marker windows to publish, resolving those widgets to their real owners (#643); the phantom display was later hardened to 640×480 off-main, held briefly, with a one-strike blacklist (#661), and it never appears in Thaw's own display enumeration. Orphans stay put — they are never relocated.
- Title-offset items (AirBuddy, SpamSieve, Cotypist) resolve by corroborated title with a width backstop, system status-item clones are excluded regardless of namespace (#662), and generic slots stay unresolved for the marker pass rather than guessing (#690).

#### Notch overflow

- Items that would hide behind the notch on MacBook displays are properly managed, ejected to Thaw Bar instead of lost (from `1.3.0-beta.1`).
- Overflow budgeting stopped double-counting spacing that ejected correctly-placed profile items at default settings, runs only against settled geometry (#681), and keeps the visible control item in place during ejection.

#### Interaction & everyday fixes

- Clicking File, Edit, View no longer trips show-on-click, hover, or scroll behaviours; event monitors health-check and recover themselves instead of dying until relaunch.
- Synthetic clicks keep out of Hot Corners and Show Desktop, restore the cursor reliably, and rehide logic stops stuck items saturating rehide or spinning popup detection.
- The always-hidden section answers option-click, double-click on the Thaw icon (configurable), and ctrl/option clicks on empty space; transient Live Activities and Game Mode agents are excluded from search, moves, and profile budgets.
- Right-click context menus work on secondary displays, quit lives in the secondary menu with ⌥-hold switching it to Restart Thaw, and a localized Support menu item links help resources.
- The search panel keeps its text between openings if asked, regains focus from the hotkey, and lets sections reorder and filter; layout-bar drags land across sections cleanly without false move alerts.
- Settings gained sidebar auto-fit, freed window sizing, per-pane polish, hidden dependent toggles when a section is disabled, and an option to disable icon refresh entirely (0 FPS).

#### Performance, memory & platform

- Swift strict concurrency landed in beta.3 and deepened to Swift 6.2 with MainActor default isolation on the app target; locks migrated to `OSAllocatedUnfairLock`.
- ScreenCaptureKit replaced the SkyLight capture paths that leaked; the XPC item service answers one batch request instead of 40–64 concurrent per-window calls, which ended the jetsam kills; wallpaper capture went away entirely.
- The image cache got an LRU/concurrency overhaul with lossless disk keys, retain cycles in live refresh were closed, duplicate entries after reconnect removed, and caches rebuild on display connect/disconnect.
- Icon refresh normalized onto one grid — off, or `1/n` seconds for integer n in 1…30.

#### Distribution, security & localization

- Sparkle payloads publish to `thaw-app/updates`, mirrored to the legacy stonerl Pages feed; DMGs are built with a background image, signed, notarized, and carry SLSA Build L3 provenance.
- OSV dependency scanning gates releases, CodeQL analysis runs in CI, SonarCloud findings were cleared, explicit Xcode versions pin reproducible builds, and the project holds OpenSSF Best Practices Gold.
- Crowdin-driven localization with plural-aware strings and separated copy strings for cleaner translation; the tour ships complete in Spanish.

#### Release-candidate reliability work

This was the headline of the RC cycle — deterministic ordering with stable identities replaced the drift that let saved layouts scramble; reorder storms are bounded instead of endless; persist gates stop transient states from being written as user intent; control-item pairing, notch overflow budgeting, scan cost, name memory, and divider recovery were rebuilt from field logs. Cold-start restore works, the 47 GiB memory growth is gone, hidden previews render, and the bar stops repairing itself into collapse. Details live in the RC sections below.

---

### Contributors

Thaw 2.0 was built by Toni Förster (@stonerl), René Jiménez
(@diazdesandi), and Amir Zarrinkafsh (@nightah), with contributions,
reports, diagnostics, translations, and patient testing from:

@aliaskar-rockeater · @alvst · @andredlng · @auspic7 · @beantownbytes · @billchirico · @bpresles · @brucemakes012 · @bytepl · @CamilleGuillory · @cbguder · @danielhopkins · @davidnichols-ops · @Daventure91 · @eli-yip · @exsesx · @gitmichaelqiu · @howardhey · @hxu · @JamesLautner · @jamesyc · @Jizzy015 · @kn666 · @kylewhirl · @lathe-agent-oa · @looseboy · @lucifercraig12345-create · @MashnoorKek · @nk-tedo-001 · @SAY-5 · @ShiroKSH · @Skyearn · @slatlasdev · @stu-carter · @subway-jack · @t4sh · @TheBenMeadows · @VailElla · @volcbs · @warmup72 · @wizaard88 · @yoodu · @YuriNachos · @ZeterMordio · @Zophiekat

and every translator working through Crowdin.

Thank you. This release would not exist without you.

---

### Upgrade notes

1. **From 1.x:** Thaw 2.0 requires macOS 26. On macOS 14 or 15 you stay on `1.3.0-beta.1` (#427).
2. **Per-display spacing:** the schema changed during the beta cycle; older profiles fall back to the active display's value rather than failing to load.
3. **From any 2.0 RC:** in-place Sparkle update. Failure-ledger marks clear on build change, and an explicit `defaults write` override still beats any shipped default.
4. **Update feed:** new installs use `thaw-app/updates`; existing installs on the legacy stonerl feed keep receiving the mirrored appcast.
5. **AX click delivery** is on by default and no longer shown in Settings; `defaults delete com.stonerl.Thaw UseAXClickDelivery` restores that default if you had turned it off during the RCs.

Known issues carried from the RCs are listed at the end of each RC section below.

**Full Changelog**: https://github.com/thaw-app/Thaw/compare/1.3.0-beta.1...2.0.0

### Support

If you find Thaw useful and want to support its development:

- GitHub Sponsors: https://github.com/sponsors/stonerl
- Ko-fi: https://ko-fi.com/stonerl
- Patreon: https://www.patreon.com/c/stonerl
- PayPal: https://www.paypal.me/tonifoerster

## [2.0.0-rc.5]

Please report issues at
[github.com/thaw-app/Thaw/issues](https://github.com/thaw-app/Thaw/issues).

This is planned as the last release candidate before 2.0 stable. Almost all
of it comes out of field logs, and in nearly every report the layout
machinery damages the arrangement it was trying to restore: a divider
rebuild swept a healthy bar into the hidden section, a repair loop fought
the notch overflow eject move by move, a save outran the restore it raced,
and a lost always-hidden divider went unnoticed while its section drained
into Visible (#958, #863). A second track drove the scan-cost work: full
source-PID scans asked every running application for an extras menu bar,
which made the whole system stutter, and until resolution caught up every
item answered to "Menu Bar Item" (#956).

---

### Highlights

- **The bar stops repairing itself into collapse** — both hidden-divider recoveries discarded a stale autosave position by writing the fresh-install seed through the guard-bypassing route; the divider landed back beside the visible chevron and the next save persisted the collapsed span. On the five-hour log attached to #958, a routine notch overflow scored one boundary mismatch, the rebuild fired, and three seconds later the visible section held nothing but Thaw's own icon.
- **Boundary repair moves items instead of dragging the divider across them** — Phase 1 reached for one drag of H_ctrl whenever any managed item read on the wrong side of it. Where that drag would have crossed the entire visible section, the bar collapsed to a 33-point span and the apply still reported a clean classification afterwards. Small mismatches now walk the offending items back to the divider one drag each, and the divider drag is reserved for the empty-side cases it was built for (#879, #958).
- **The overflow planner and the repair pass stop fighting** — on bars persistently over the notch budget, every apply ejected the same item and then recalled it as wrongly concealed, two synthetic drags per cycle for as long as the bar stayed over budget. This matches the "icons jumping randomly and relocating between layouts" reports. Ejected items are now exempt from the boundary tally until the budget frees up (#958).
- **Items keep their names while source-PID resolution catches up** — naming requires knowing which process created an item, and the first cache pass deliberately runs without waiting for the accessibility scan; for its duration every item answered to the generic "Menu Bar Item" on hover and in Search. An item now falls back to the name it resolved to last time. Control Center's generic Item-N slots are refused, because their key encodes hosting order rather than identity and a wrong name gets clicked; custom names still take precedence (#956).
- **Slow item owners get room to answer before Thaw gives up** — the move budget started at 100 ms, but escalation averaged each raise against the standing value, so even eight attempts reached only 476 ms, and every unresponsive-owner failure was filed twice, consuming the ledger's mark threshold in one instant. Defaults are now 250 ms (350 for Bento Boxes), growth is adopted as computed up to a one-second ceiling, failures are filed once, and marking takes three. Fixes the cursor hijack of #687 and the misplaced relaunched items of #960.
- **Scans stop re-probing every running application** — roughly 16 of ~170 running applications have an extras menu bar, but the negative answer did not survive cache cleanup, so nearly every scan re-probed the full application list at ~400 ms steady-state and ~2.8 s during startup. Negative answers now survive cleanup and launches. A zero-area window can no longer start a scan on its own behalf, and the diagnostic names any app whose probe takes longer than 50 ms (#956).
- **Hidden previews render again** — orphaned Control Center slots from an earlier Thaw process carry zero width, corrupt the composite-slicing geometry, and discard every preview batch, so all hidden and always-hidden previews in Settings → Layout came back empty (#962, thanks @alvst).

---

### Menu bar & layout

#### Source-PID scanning

- The negative-cache flag was cleared for every reused app on every cache cleanup, and cleanup is driven by `NSWorkspace.runningApplications`, which changes whenever any process starts or exits; the #956 log shows 46 cleanups in seven minutes. The flag is now a deadline that survives cleanup and backs off as consecutive empty checks accumulate. Early rungs stay inside the startup window, so an application that publishes its status item shortly after launch is still found quickly.
- Consecutive-miss counts are remembered per bundle identifier across launches and seed the first scan of a session, which measured 3.85 s in the log. Seeding is deliberately the ladder's first rung rather than the rung the count earns: memory is trusted to say where to look and never what was found, so skipping an application can reorder work but cannot attribute an item to the wrong owner.
- A zero-area window has no centre worth comparing against an accessibility frame, yet an unresolved window is what selects scan drivers; one such window started eight of nine scans in seven minutes with nothing else on the bar asking for one. Zero-area windows no longer select themselves. Bounds are re-read on every request, so a window that gains area stops being skipped.
- Scan summaries now log total wall time and name any single app whose extras-bar probe exceeds 50 ms, since accessibility reads are serviced by the target process and bounded only by the unresponsive timeout.

#### Save gates

- `saveSectionOrder` honours the same five-second post-move cooldown `applySavedLayout` uses, except when the user's own move is the most recent one, so a Layout-editor drag does not undo itself. In the #958 log the save landed one millisecond after the restore stood down.
- The multi-display gate counted items classified as visible, so a relocation that stranded items in the wrong section erased its own evidence: it fired correctly with sixteen visible items and passed when four were left, which was the save that did the damage. The gate now reads whether the menu bar changed display since the cache cycle being compared, a signal that survives misclassification because it does not read the items at all.

#### Divider recovery

- A hidden-divider rebuild stamps a seed position only when the bar holds no managed items. Discarding the stale `NSStatusItem` is still what gives the divider a window on the current bar, and the follow-up apply walks it to the saved boundary, a move the seeded rebuild could not make anyway while parked off screen (#958).
- The H_ctrl boundary move no longer anchors on Thaw's own chevron. When every profile item has been dragged to the other side, anchoring on the last remaining candidate drags H_ctrl past it and conceals it; returning nil leaves the boundary alone and hands the work to the per-item LCS pass, which has barred Thaw's own items as anchors since #924. The two nil cases log separately (#958).
- Parked dividers are measured at their leading edge instead of their centre. A collapsed hidden divider is 5000 points wide, so its centre sat 2500 points right of the divider and read as on-screen on multi-display arrangements, defeating both the parked-divider drag guard (#899) and the rebuild detector; five hours of log recorded neither warning.
- Chevron relocation and always-hidden control-item ordering skip when the hidden divider fails the on-screen check, so neither drops its target into the parked zone beside a physically parked divider. The existing recovery paths already handle the states these guards refuse.
- An enabled always-hidden section whose divider stops resolving gets its status item recreated once per episode after three authoritative cycles with no reading, and stored position is kept rather than seeded. Provisional AX-frame correlations never advance, reset, or re-arm the streak. The #863 re-plug log showed `alwaysHidden=nil` on every cycle for 12+ hours while the whole always-hidden section drained into Visible and the collapsed arrangement persisted (#863).
- The one-pixel drop-point bias now applies to every control-item divider regardless of width. Expanded, thousands-of-points-wide dividers still produced placements landing one point into the wrong section: a divider's width provides visual concealment, not hit-test slack (#923).

---

### Appearance, capture & IceBar

- Preview batches exclude degenerate zero-width windows from the bounds union. Capture APIs drop them from the composite while including them in the union dragged its geometry across the gap between displays, the widths stopped matching, and the whole batch was discarded. The windows that surfaced this were Control Center-hosted slots orphaned by an earlier Thaw process: Control Center owns them, so they outlive restarts, and their bundle-ID names keep them out of `ControlItemPair`'s strip list (#962).

---

### Dependencies & docs

- Sparkle bumped in the swift group (#971); github-actions group bumped with four updates (#972).
- README OpenSSF badges switched to live shieldcn scorecard/openssf endpoints (#920); contributor image source updated; repository notice added.
- FUNDING.yml gained Ko-fi and PayPal entries.

---

### Upgrade notes

1. **From 2.0.0-rc.4:** in-place Sparkle update.
2. **Move budgets:** defaults rose to 250 ms (350 for Bento Boxes); an explicit `defaults write` override still takes precedence over either.

## [2.0.0-rc.4]

Please report issues at
[github.com/thaw-app/Thaw/issues](https://github.com/thaw-app/Thaw/issues).

This release closes the field reports against rc.3 — hidden items dead
for the first minute after launch, and a cache stall with no deadline at
all — and pays down the debt that made them possible: the item manager's 11,500-line file, the hand-rolled identity
matching that drifted, and a test suite that wrote into the real settings
of whoever ran it.

---

### Highlights

- **Hidden items work from launch, and the cache can no longer stall for good** — on a cold start the item cache froze for a full minute on unresolved identities: every Thaw Bar tooltip read "Menu Bar Item" and every click silently did nothing until the settling deadline expired (#943). In the worse interleaving the settling task deadlocked awaiting itself, past every deadline — one report had the cache rejecting every refresh for 20+ hours, with the Visible row in Settings → Layout permanently empty (#945).
- **The Thaw icon stops drifting left across restarts** — the stalled early apply executed a minute late with the desired order it had narrowed at launch, when only a handful of identities had resolved. Everything that resolved during the stall was re-inserted as "unmanaged" at saved indices, which changed the chevron's planned neighbors and moved it left of the leftmost item; macOS remembers the new position, so each restart ratcheted it further (#947).
- **Items stop shuffling mid-session on localized systems** — saved-order ghosts namespaced by a localized app name (`Control Centre:WiFi`, minted while a bundle ID transiently read nil) counted as "real owners" and deleted their genuine `com.apple.controlcenter` twins from the saved order on every load. The live items then planned as unmanaged and were repositioned by every apply, with the cursor contested for each synthetic drag (#949).
- **Spanish onboarding restored** — two strings shipped as translated-but-empty, so Spanish systems rendered a blank tour slide description and a blank New Items badge hint.
- **XPC session race closed** — a stale cancellation handler could tear down a healthy, newer session and race the lock every other access went through.

---

### Menu bar & layout

- The settling-period early apply no longer waits for settling to end while holding the serial cache gate. The wait deadlocked the pair both ways: when the launch cache cycle owned the gate, settling's early exit needed a cache cycle the held gate rejects, so it ran the full 60 s deadline with the item cache frozen on fallback tags — generic names in Thaw Bar and Search, and every click aborted with no return destination (#943). When the settling task's own poll owned the gate, the apply awaited the very task it was running on, and the deadline check inside that blocked loop could never fire — the gate stayed held indefinitely and every later recache was rejected (#945).
- Clicking an item whose cached tag predates source-PID resolution re-maps it onto its freshly fetched counterpart by windowID, so the click survives a stale cache snapshot instead of dying in the return-destination lookup (#943).
- Because the early apply now runs the moment it is dispatched, it plans against the bar it narrowed itself to. Executed at the deadline instead, its restriction inverted: identities that resolved during the stall were no longer provisional (which excludes them) but "unmanaged" (which re-inserts them at saved indices), and the re-insertion handed the chevron a move to the far left of the bar (#947).
- Saved-order pruning no longer counts a localized display-name namespace as a real owner, and drops such a ghost when its canonical twin exists — the Control Center entry sharing its title, Thaw's own control items by their reserved titles, or a real owner claiming the same non-generic title. A display-name entry with no twin survives, since it may be the only identity a bundle-ID-less app ever got (#949).
- The namespace fallback recovers a transiently nil bundle ID through the app's bundle URL before reaching for the window's owner name, so localized ghosts stop being minted in the first place (#949).

### XPC service

- The session cancellation handler cleared the stored session outside the lock that guarded every other access, and a handler outliving its session could clear a newer one created after it. Storage now synchronizes internally, and invalidation is identity-guarded so only the cancelled session is dropped.
- The single-window `sourcePID` request was dead wire protocol — the batch request replaced it in production — yet its round-trip tests were the only wire-format coverage at all. The request is gone and the tests now exercise the batch case both sides actually use.

### Localization

- The Spanish descriptions for the Hotkeys & Automation tour slide and the New Items badge hint were empty strings marked translated. A catalog sweep found exactly these two; both are filled in the register the catalog already uses.

### Internal

- `MenuBarItemManager.swift` (11,526 lines) is now a folder of per-concern files cut along its existing MARK seams, each importing only what it uses; sonar and the SwiftLint input list follow the new paths.
- Item identity matching (tag plus effective PID), the click-target refetch chain, and live-bounds reads are single-sourced helpers instead of hand-rolled copies across the manager and the IceBar — the same drift that produced #943.
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

- **Launch restore actually runs** — the saved layout is applied at cold start instead of losing to a move cooldown that launch itself had stamped ~0.4 s earlier (#881, #900).
- **Storms are bounded** — a failed or parked-divider move can no longer hijack the cursor indefinitely or write a half-finished order into `savedSectionOrder`.
- **Control-item pairing repaired** — Thaw's visible chevron is no longer mistaken for the hidden divider, the mispair behind hidden sections reading zero width (#923, #924, #927).
- **Memory leak closed** — recache backoff stops the CA fence port growth reported at 47 GiB on macOS 26 (#933).
- **Field repair** — `Thaw --reset-layout` clears persisted order and re-seeds dividers without starting the app.

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

- **Hidden divider boundary and layout-editor drags** — repair the visible/hidden boundary when `H_ctrl` drifts before the per-item reorder pass, so `applyProfileLayout` no longer reports "all items already in correct positions" while the whole hidden section sits misplaced. Drops into an empty hidden section that only contains the new-items badge no longer snap back, and persistent status-level windows (shelf/HUD) no longer defer every move — deferral still applies while the pointer is inside a long-open menu (#880, fixes #879).

---

This RC is a large reliability and platform update: menu bar identity/ordering, layout persistence, notch overflow, settings UI, Swift 6.2 / concurrency, and Sparkle update hosting.

---

### Highlights

- **Menu bar reliability overhaul** — safer saved-layout apply/persist, stronger item identity matching, and fewer false “reorder storms,” especially with Control Center items, dynamic titles, and multi-display setups.
- **Settings & onboarding refresh** — redesigned settings UI, glass tour onboarding, stronger AX identity / click paths.
- **Swift 6.2 + approachable concurrency** — MainActor default isolation on the app target, AXSwift6, EventTap synchronization, and cleanup of pre–Swift 6 GCD/Timer patterns.
- **Update distribution** — Sparkle ZIP/deltas/appcast publish to `thaw-app/updates`, with a mirror for legacy `stonerl` Pages installs.

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
- Refuse saved-layout bulk apply while the hidden-section dividers are collapsed / zero-width — same `hiddenSectionHasRoom` gate the save path already uses — so a collapsed reading cannot drag the whole hidden section and then get persisted (#868 / #876, thanks @TheBenMeadows).
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
- Keep menu bar move events out of screen corners — stops Hot Corner / Show Desktop false triggers (#625, #766 / #774, thanks @ZeterMordio).
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
