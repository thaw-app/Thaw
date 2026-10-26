//
//  RevealCoverGeometry.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel
import Synchronization

/// Where RevealCover's bands go and how their left ends fade, worked out from
/// plain values so RevealCover itself only moves panels.
nonisolated enum RevealCoverGeometry {
    /// Room left for the pill's rounded end left of the first visible item.
    static let pillInset: CGFloat = 10
    /// Gap macOS leaves between adjacent status items.
    static let itemSpacing: CGFloat = 8
    /// Least width an item counts for when its reported width is unusable.
    static let minimumItemWidth: CGFloat = 24
    /// Slack on the summed width, for estimates that come in short.
    static let widthMargin: CGFloat = 1.25
    /// Length of the fade at the band's left end.
    static let fadeWidth: CGFloat = 32

    /// A display's CG-global frame and menu bar height.
    struct ScreenBar: Sendable {
        let displayID: CGDirectDisplayID
        let frame: CGRect
        let height: CGFloat
    }

    /// Whether an item's frame can anchor the band. The Thaw icon is the
    /// leftmost visible item on most bars and does not always report itself
    /// on screen, so it is taken on its width alone.
    static func anchorsBand(width: CGFloat, isVisibleControlItem: Bool, isOnScreen: Bool, isInVisibleSection: Bool) -> Bool {
        width > 0 && (isVisibleControlItem || (isOnScreen && isInVisibleSection))
    }

    /// Whether an item will appear in the band while the restriction is down.
    static func isConcealed(isVisibleControlItem: Bool, isInVisibleSection: Bool) -> Bool {
        !isVisibleControlItem && !isInVisibleSection
    }

    /// The width the concealed items take once revealed. Parked items can
    /// report a zero or shrunken width, and a leak at the far end is the one
    /// failure a user sees, so each counts at least minimumItemWidth and the
    /// total carries widthMargin.
    static func concealedWidth(itemWidths: [CGFloat]) -> CGFloat {
        itemWidths.reduce(CGFloat.zero) { $0 + max($1, minimumItemWidth) + itemSpacing } * widthMargin
    }

    /// The cover band per display, from the frames of the visible items.
    ///
    /// Only seated frames anchor: an item parked at the x == -1 sentinel still
    /// reports itself on screen and would leave every display uncovered. A
    /// display without seated items mirrors the right-edge distance of the
    /// home display, the one liveAnchorX was read on.
    static func bands(
        visibleFrames: [CGRect],
        liveAnchorX: CGFloat?,
        screens: [ScreenBar],
        concealedWidth: CGFloat
    ) -> [CGDirectDisplayID: CGRect] {
        guard concealedWidth > 0 else { return [:] }
        let screenFrames = screens.map(\.frame)
        var leadingEdges: [CGDirectDisplayID: CGFloat] = [:]
        var home: (screen: ScreenBar, x: CGFloat)?
        for frame in visibleFrames {
            guard let seat = MenuBarItemGeometry.barScreen(holding: frame, among: screenFrames),
                  let screen = screens.first(where: { $0.frame == seat })
            else {
                continue
            }
            leadingEdges[screen.displayID] = min(leadingEdges[screen.displayID] ?? frame.minX, frame.minX)
            if home.map({ frame.minX < $0.x }) ?? true {
                home = (screen, frame.minX)
            }
        }
        guard let home else { return [:] }
        if let liveAnchorX, liveAnchorX > home.screen.frame.minX, liveAnchorX < home.screen.frame.maxX {
            leadingEdges[home.screen.displayID] = liveAnchorX
        }
        let homeEdge = leadingEdges[home.screen.displayID] ?? home.x
        let offsetFromRight = home.screen.frame.maxX - (homeEdge - pillInset)
        var bands: [CGDirectDisplayID: CGRect] = [:]
        for screen in screens {
            let frame = screen.frame
            let right = leadingEdges[screen.displayID].map { $0 - pillInset } ?? frame.maxX - offsetFromRight
            let left = max(frame.minX, right - concealedWidth - pillInset)
            guard right > left else { continue }
            bands[screen.displayID] = CGRect(x: left, y: frame.minY, width: right - left, height: screen.height)
        }
        return bands
    }

    /// Where the fade ends, as a fraction of the band's width: fadeWidth in,
    /// and never past the middle of a narrow band.
    static func fadeEnd(width: CGFloat) -> Double {
        Double(min(fadeWidth / max(width, 1), 0.5))
    }

    /// Fades the band in over its left end. The backdrop is a hair off the
    /// live bar, and a hard edge makes that difference a visible seam; a fade
    /// spreads it over fadeWidth, where it reads as the bar.
    @MainActor
    static func fadeMask(width: CGFloat, height: CGFloat) -> CAGradientLayer {
        let mask = CAGradientLayer()
        mask.frame = CGRect(x: 0, y: 0, width: width, height: height)
        mask.startPoint = CGPoint(x: 0, y: 0.5)
        mask.endPoint = CGPoint(x: 1, y: 0.5)
        mask.colors = [NSColor.clear.cgColor, NSColor.black.cgColor, NSColor.black.cgColor]
        mask.locations = [0, NSNumber(value: fadeEnd(width: width)), 1]
        return mask
    }

    /// Whether a new holder's deadline replaces the watchdog's. A deadline is
    /// pushed out by each new holder, never pulled in.
    static func extendsWatchdog<Instant: Comparable>(to deadline: Instant, from current: Instant?) -> Bool {
        current.map { deadline > $0 } ?? true
    }
}

/// Whether a RevealCover is up, so the nonisolated chevron probe can
/// tell a covered hit-test from a real bar reading.
nonisolated enum RevealCoverActivity {
    private static let covers = Mutex(0)

    static var isAnyMaskShowing: Bool {
        covers.withLock { $0 > 0 }
    }

    static func noteShown() {
        covers.withLock { $0 += 1 }
    }

    /// Counts one cover down, never below zero.
    static func noteHidden() {
        covers.withLock { $0 = max(0, $0 - 1) }
    }
}
