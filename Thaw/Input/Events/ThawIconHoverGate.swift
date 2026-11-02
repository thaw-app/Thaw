//
//  ThawIconHoverGate.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics

/// Decides when resting on Thaw's icon may reveal the hidden section, and what
/// a click on the icon does to a section hover just revealed.
///
/// - A click soon after a hover reveal takes the section over and keeps it open.
/// - After a press on the icon, it can't start a hover reveal until the pointer
///   leaves, so a click that closes the section doesn't reopen it.
nonisolated struct ThawIconHoverGate {
    /// How soon after a hover reveal a press on the icon still takes it over, and
    /// how long that click's activation, forwarded after the mouse-up, may take.
    static let clickAdoptionWindow: Duration = .seconds(1)

    /// Narrower than this, the icon is the collapsed stand-in left when Show
    /// Thaw icon is off.
    static let minimumIconWidth: CGFloat = 4

    /// Whether a press on the icon holds its hover reveal until the pointer leaves it.
    private(set) var isLatched = false
    private var hoverRevealedAt: ContinuousClock.Instant?
    private var adoptsClickUntil: ContinuousClock.Instant?

    /// Whether the icon can be a hover target at all.
    static func isHoverTarget(showsIcon: Bool, iconWidth: CGFloat) -> Bool {
        showsIcon && iconWidth >= minimumIconWidth
    }

    /// Whether resting on the icon may arm a hover reveal now.
    var mayArmFromIcon: Bool {
        !isLatched
    }

    /// Releases the press latch once the pointer is seen off the icon.
    mutating func notePointer(onIcon: Bool) {
        if !onIcon {
            isLatched = false
        }
    }

    /// Records that hover revealed the hidden section at instant.
    mutating func noteHoverReveal(at instant: ContinuousClock.Instant) {
        hoverRevealedAt = instant
    }

    /// Records a press. Returns true when it lands on the icon soon after a hover
    /// reveal that is still out, so its click should keep the section open.
    mutating func notePress(
        onIcon: Bool,
        isHoverReveal: Bool,
        at instant: ContinuousClock.Instant
    ) -> Bool {
        guard onIcon else {
            return false
        }
        isLatched = true
        let revealedAt = hoverRevealedAt
        hoverRevealedAt = nil
        guard
            isHoverReveal,
            let revealedAt,
            revealedAt.duration(to: instant) < Self.clickAdoptionWindow
        else {
            adoptsClickUntil = nil
            return false
        }
        adoptsClickUntil = instant + Self.clickAdoptionWindow
        return true
    }

    /// Consumes the decision notePress(onIcon:isHoverReveal:at:) made for the
    /// icon's next click: true leaves the section open.
    mutating func claimClick(at instant: ContinuousClock.Instant) -> Bool {
        defer { adoptsClickUntil = nil }
        guard let adoptsClickUntil else {
            return false
        }
        return instant < adoptsClickUntil
    }
}
