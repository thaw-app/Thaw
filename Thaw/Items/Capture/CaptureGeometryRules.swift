//
//  CaptureGeometryRules.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import MenuBarModel

extension MenuBarItemImageCache {
    // MARK: Display And Bounds Selection

    /// Picks the display whose menu bar a capture should read from.
    ///
    /// Preference order matters: the display the item cache was built against
    /// wins, because its item bounds are only meaningful there. Falling through
    /// to the display currently owning the menu bar, and finally to the main
    /// display, keeps a capture possible on a machine whose item cache has not
    /// been populated yet.
    static nonisolated func captureDisplayID(
        itemCacheDisplayID: CGDirectDisplayID?,
        activeMenuBarDisplayID: CGDirectDisplayID?,
        mainDisplayID: CGDirectDisplayID
    ) -> CGDirectDisplayID {
        itemCacheDisplayID ?? activeMenuBarDisplayID ?? mainDisplayID
    }

    static nonisolated func shouldUseFreshBounds(
        for section: MenuBarSection.Name,
        revealedSection: MenuBarSection.Name?
    ) -> Bool {
        switch (section, revealedSection) {
        // Visible items also move when the capture indicator or a neighbour
        // appears. Retrying their cached layout rectangles cannot recover.
        case (.visible, _),
             (.hidden, .hidden),
             (.hidden, .alwaysHidden),
             (.alwaysHidden, .alwaysHidden):
            true
        default:
            false
        }
    }

    static nonisolated func captureBounds(
        for items: [MenuBarItem],
        freshBounds: Bool,
        liveBoundsByID: [String: CGRect],
        screenFrame: CGRect?
    ) -> [(item: MenuBarItem, bounds: CGRect)] {
        items.compactMap { item in
            // NSScreen.frame is Y-up and AX bounds Y-down, so compare X only.
            guard let bounds = freshBounds ? liveBoundsByID[item.uniqueIdentifier] : item.bounds,
                  !bounds.isEmpty,
                  screenFrame.map({ screen in
                      screen.minX < bounds.maxX && bounds.minX < screen.maxX
                  }) != false
            else {
                return nil
            }
            return (item, bounds)
        }
    }

    /// Same-width stacked displays own the bar nearest their top edge; ties remain unknown.
    static nonisolated func isBarOnScreen(barFrames: [CGRect], display: CGRect, displays: [CGRect] = []) -> Bool {
        func matchesHorizontalSpan(_ frame: CGRect, _ screen: CGRect) -> Bool {
            abs(frame.minX - screen.minX) < 1 && abs(frame.width - screen.width) < 1
        }
        let bars = barFrames.filter { frame in
            guard matchesHorizontalSpan(frame, display) else { return false }
            let distance = abs(frame.minY - display.minY)
            return !displays.contains { other in
                other != display && matchesHorizontalSpan(frame, other)
                    && abs(frame.minY - other.minY) <= distance
            }
        }
        guard !bars.isEmpty else { return true }
        return bars.contains { $0.minY >= display.minY - 1 }
    }
}
