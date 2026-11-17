//
//  MenuBarItemAXProvider+ChevronFallback.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation
import os.lock

/// The chevron hit-test fallback for an extras-bar walk that found none, and its answer while the
/// strip cannot be hit-tested: a reveal mask is up, or Thaw is the menu bar owner.
nonisolated extension MenuBarItemAXProvider {
    /// Displays where the extras-bar walk has found the chevron, so a complete walk there that finds
    /// none means it is gone. A notchless display draws its chevron outside the bar and never joins.
    private static let displaysWhereWalkSeesChevron = OSAllocatedUnfairLock(
        initialState: Set<CGDirectDisplayID>()
    )

    /// The walk's chevron frames, or the strip hit-test's when the walk found none, and whether
    /// that hit-test gave up before finishing.
    static func chevronFrames(
        walkFrames: [CGRect],
        on display: CGDirectDisplayID,
        displayBounds: CGRect,
        attributeReadFailed: Bool,
        unframedControlCount: Int
    ) -> (frames: [CGRect], hitTestGaveUp: Bool) {
        let walkRulesOut = walkRulesOutChevron(
            on: display,
            frames: walkFrames,
            attributeReadFailed: attributeReadFailed,
            unframedControlCount: unframedControlCount
        )
        guard walkFrames.isEmpty else {
            return (walkFrames, false)
        }
        switch chevronObservationByHitTest(on: display, displayBounds: displayBounds, walkRulesOut: walkRulesOut) {
        case let .present(hitTestFrames):
            var seen = Set<CGRect>()
            return (hitTestFrames.filter { seen.insert($0).inserted }, false)
        case .absent:
            return ([], false)
        case .unavailable:
            return ([], true)
        }
    }

    /// Notes a sighting from the extras-bar walk, then whether this walk rules the chevron out.
    static func walkRulesOutChevron(
        on display: CGDirectDisplayID,
        frames: [CGRect],
        attributeReadFailed: Bool,
        unframedControlCount: Int
    ) -> Bool {
        let hasSeen = displaysWhereWalkSeesChevron.withLock { displays in
            if !frames.isEmpty {
                displays.insert(display)
            }
            return displays.contains(display)
        }
        return frames.isEmpty && walkRulesOutChevron(
            walkHasSeenChevron: hasSeen,
            attributeReadFailed: attributeReadFailed,
            unframedControlCount: unframedControlCount
        )
    }

    /// Whether a walk that found no chevron is proof there is none: only where the walk has seen
    /// one, and only from a read that completed and found no control it could not place.
    static func walkRulesOutChevron(
        walkHasSeenChevron: Bool,
        attributeReadFailed: Bool,
        unframedControlCount: Int
    ) -> Bool {
        walkHasSeenChevron && !attributeReadFailed && unframedControlCount == 0
    }

    /// A walk that rules the chevron out answers first. Otherwise a known chevron or an absence
    /// inside its cooldown stands, and anything else is unavailable.
    static func chevronObservationWhileMasked(
        hint: CGRect?,
        lastAbsentAt: ContinuousClock.Instant?,
        now: ContinuousClock.Instant,
        cooldown: Duration = chevronAbsenceCooldown(isBuiltIn: true),
        walkRulesOutChevron: Bool = false
    ) -> NativeOverflowObservation {
        if walkRulesOutChevron {
            return .absent
        }
        if let hint {
            return .present([hint])
        }
        if let lastAbsentAt, now - lastAbsentAt < cooldown {
            return .absent
        }
        return .unavailable
    }
}
