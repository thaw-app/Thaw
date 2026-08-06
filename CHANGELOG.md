# Changelog

All notable changes to Thaw are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

The `release.yml` workflow reads the section matching the release tag
(`## [tag]`) and uses it as the release notes for both the GitHub Release
and the Sparkle appcast, unless overridden with the `release_notes` input.

## [Unreleased]

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
