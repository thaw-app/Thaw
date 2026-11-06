//
//  SavedOrderMirrorGate.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel

/// Holds back copying the live order into the saved order until the bar has been quiet for a while.
/// After a wake, a display, hiding or item change the bar passes through orders nobody chose.
@MainActor
final class SavedOrderMirrorGate {
    private static let diagLog = DiagLog(category: "SavedOrderMirrorGate")

    /// When the live order last became the saved order, or was found to match it.
    private(set) var lastMirror: ContinuousClock.Instant?

    private let settling: BarSettling
    private var lastIdentifiers: Set<String>?

    init(settling: BarSettling) {
        self.settling = settling
    }

    /// Call once the saved order matches the bar, including when a mirror found nothing to change.
    /// An order kept over an arrival differs from the bar and does not count.
    func noteMirrored(at instant: ContinuousClock.Instant = .now) {
        lastMirror = instant
    }

    /// Whether a drag on the bar ended after the saved order last caught up with it.
    /// Until the next mirror the saved order predates the drag and must not be laid back over the bar.
    func mirrorIsBehind(userDragEndedAt dragEnd: ContinuousClock.Instant?) -> Bool {
        guard let dragEnd else { return false }
        guard let lastMirror else { return true }
        return dragEnd > lastMirror
    }

    /// Whether the cache holding these items may become the saved order now.
    /// A changed item set, a revealed section and an item with a transient frame each count as a disturbance,
    /// and a recent hiding change holds it too.
    func allowsMirror(
        identifiers: Set<String>,
        sectionRevealed: Bool = false,
        transientFrame: String? = nil
    ) -> Bool {
        if let transientFrame {
            Self.diagLog.debug("Holding the saved-order mirror: \(transientFrame)")
        }
        if sectionRevealed || transientFrame != nil || lastIdentifiers.map({ $0 != identifiers }) == true {
            settling.note(.barLayoutShifted)
        }
        lastIdentifiers = identifiers
        return settling.hold(for: .savedOrderMirror) == nil
    }

    /// The first on-screen item still mid-layout, described for the log: its frame is at x == 0, above its display, or over none.
    /// A parked frame, at x == -1 or far below the bar, is settled and does not count.
    static nonisolated func transientFrame(among items: [MenuBarItem], displays: [CGRect]) -> String? {
        guard !displays.isEmpty else { return nil }
        let transient = items.first { item in
            let frame = item.bounds
            guard item.isOnScreen, !frame.isEmpty, !frame.isInfinite, frame.origin.x != -1 else { return false }
            return frame.origin.x == 0 || !displays.contains { display in
                (display.minX ..< display.maxX).contains(frame.midX) && frame.minY >= display.minY - 1
            }
        }
        return transient.map { "\($0.uniqueIdentifier) has a transient frame \(NSStringFromRect($0.bounds))" }
    }
}
