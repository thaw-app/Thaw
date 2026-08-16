# Changelog

All notable changes to Thaw are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

The `release.yml` workflow reads the section matching the release tag
(`## [tag]`) and uses it as the release notes for both the GitHub Release
and the Sparkle appcast, unless overridden with the `release_notes` input.

## [Unreleased]

Please report issues at
[github.com/thaw-app/Thaw/issues](https://github.com/thaw-app/Thaw/issues).

This release closes the field report against rc.3 — hidden items dead
for the first minute after launch — and pays down the debt that made it
possible: the item manager's 11,500-line file, the hand-rolled identity
matching that drifted, and a test suite that wrote into the real settings
of whoever ran it.

---

### Highlights

- **Hidden items work from launch** — on a cold start the item cache froze for a full minute on unresolved identities: every Thaw Bar tooltip read "Menu Bar Item" and every click silently did nothing until the settling deadline expired (#943).
- **Spanish onboarding restored** — two strings shipped as translated-but-empty, so Spanish systems rendered a blank tour slide description and a blank New Items badge hint.
- **XPC session race closed** — a stale cancellation handler could tear down a healthy, newer session and race the lock every other access went through.

---

### Menu bar & layout

- The settling-period early apply no longer waits for settling to end while holding the serial cache gate. The wait deadlocked the pair: settling's early exit needs a cache cycle the held gate rejects, so it always ran the full 60 s deadline with the item cache frozen on fallback tags — generic names in Thaw Bar and Search, and every click aborted with no return destination (#943).
- Clicking an item whose cached tag predates source-PID resolution re-maps it onto its freshly fetched counterpart by windowID, so the click survives a stale cache snapshot instead of dying in the return-destination lookup (#943).

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
