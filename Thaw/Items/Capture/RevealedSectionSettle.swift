//
//  RevealedSectionSettle.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import MenuBarModel

extension MenuBarItemImageCache {
    /// How long after a reveal a hidden section's pictures wait for its icons to stop moving.
    /// Later passes skip the wait, so a clock or graph doesn't cost a settle budget on every pass.
    static nonisolated let revealedSettleWindow = Duration.seconds(3)

    /// Whether a pass over section should wait for settled pixels before its screenshot. macOS reports
    /// a revealed item's final frame while its icon still slides in, so an early picture is cut.
    static nonisolated func settlesRevealedPixels(
        for section: MenuBarSection.Name,
        revealedSection: MenuBarSection.Name?,
        lastRevealChange: ContinuousClock.Instant?,
        now: ContinuousClock.Instant
    ) -> Bool {
        section != .visible
            && shouldUseFreshBounds(for: section, revealedSection: revealedSection)
            && BarSettling.isWithin(revealedSettleWindow, of: lastRevealChange, now: now)
    }

    /// Whether a capture pass is skipped because the bar is mid-reflow. After
    /// maximumReflowSkips skips in a row the next pass runs regardless.
    static nonisolated func skipsPassForReflow(reflowing: Bool, consecutiveSkips: Int) -> Bool {
        reflowing && consecutiveSkips < maximumReflowSkips
    }

    /// Waits, within the reveal settle budget, for items' icons to stop moving. Their frames are read fresh,
    /// since the cache can still hold where they were parked; with none on the bar there is nothing to wait for.
    func settleRevealedSection(
        _ items: [MenuBarItem],
        appState: AppState,
        reader: some MenuBarCaptureReading,
        clock: RevealCaptureSession.SettleClock = RevealCaptureSession.SettleClock()
    ) async {
        let displayID = Self.captureDisplayID(
            itemCacheDisplayID: appState.itemManager.itemDisplayID,
            activeMenuBarDisplayID: Bridging.getActiveMenuBarDisplayID(),
            mainDisplayID: CGMainDisplayID()
        )
        let live = await reader.menuBarItems(displayID: displayID).filter { live in
            items.contains { $0.tag.matchesIgnoringWindowID(live.tag) }
        }
        guard !live.isEmpty else { return }
        await RevealCaptureSession.settleRevealedPixels(live, displayID: displayID, reader: reader, clock: clock)
    }
}
