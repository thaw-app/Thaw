//
//  OverflowDeficits.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

/// How much of the macOS 27 overflow budget to withhold, and the items it was measured against.
///
/// Two findings prove the modeled budget is too large: a notch covering one of Thaw's own
/// control items, and Visible items macOS did not draw. Each withholds some width, and that
/// width is sticky: it holds while the same items compete for the bar and is dropped once an
/// item arrives or leaves. Dropping it the moment the icon reappears re-admits the item that
/// covered it, which covers it again.
nonisolated struct OverflowDeficits {
    /// A withheld width and the visible and overflowed items it was measured against.
    typealias Held = (width: CGFloat, visibleUIDs: Set<String>)

    /// What one pass decided, for the caller to log and apply.
    struct Update: Equatable {
        /// The width to withhold now, or nil when nothing is withheld.
        let width: CGFloat?
        /// The width withheld before this pass.
        let previousWidth: CGFloat?

        var changed: Bool { width != previousWidth }
    }

    private(set) var notchOcclusion: Held?
    private(set) var parkedLane: Held?

    /// Nominal width used for the macOS 27 overflow budget when an item's AX
    /// bounds have collapsed to an untrusted sliver (see minimumTrustedGlyphWidth).
    /// Matches the standard status-item footprint so the budget approximates the
    /// real rendered width rather than the collapsed measurement.
    static let nominalStatusItemWidth: CGFloat = 24

    /// The most budget a notch-covered control item may take back. Past five
    /// items' worth, whatever still covers the icon is not a full bar, and
    /// conceal-until-it-shows would empty the visible section.
    static let maximumNotchOcclusionDeficit: CGFloat = nominalStatusItemWidth * 5

    /// Width to charge a non-control item against the macOS 27 overflow budget.
    ///
    /// macOS 27 collapses hidden/overflowed item AX bounds to a sliver, so the
    /// measured width understates the real footprint and deflates the budget's
    /// profile baseline. Below the trust threshold the item is charged a nominal
    /// status-item width instead; otherwise the measured width is used as-is.
    static func budgetWidth(forMeasuredWidth measured: CGFloat) -> CGFloat {
        measured < MenuBarItemImageCache.minimumTrustedGlyphWidth ? nominalStatusItemWidth : measured
    }

    /// The width a held deficit carries into this pass: all of it while the same items
    /// compete for the bar, none of it once an item arrived or left.
    static func carriedWidth(from previous: Held?, membership: Set<String>) -> CGFloat {
        previous.flatMap { $0.visibleUIDs == membership ? $0.width : nil } ?? 0
    }

    /// The overflow budget to withhold for notch-covered control items.
    ///
    /// Each pass that finds a control item under the notch withholds its width
    /// plus one nominal item on top of what earlier passes withheld, so the
    /// conceal set grows until the icon clears the notch. The deficit then
    /// holds while the same items compete for the bar, counting the ones it
    /// concealed, and is dropped once an item arrives or leaves.
    static func notchOcclusionDeficit(
        previous: Held?,
        occludedControlWidth: CGFloat,
        visibleUIDs: Set<String>,
        overflowUIDs: Set<String>
    ) -> Held? {
        let membership = visibleUIDs.union(overflowUIDs)
        let carried = carriedWidth(from: previous, membership: membership)
        let width = occludedControlWidth > 0
            ? min(maximumNotchOcclusionDeficit, carried + occludedControlWidth + nominalStatusItemWidth)
            : carried
        return width > 0 ? (width, membership) : nil
    }

    /// The overflow budget to withhold for Visible items macOS did not draw.
    ///
    /// On a full bar, a notched one in particular, macOS parks the items that
    /// do not fit at x == -1 while the modeled budget can still show hundreds
    /// of points of headroom. Parked items are proof the lane holds exactly
    /// what it seats, so the pass that finds them withholds the whole modeled
    /// headroom plus their width and gaps: the planner then conceals that much
    /// from the left of Visible. A fixed per-item allowance was not enough,
    /// since the model's error can be larger than any number of items.
    ///
    /// The deficit holds while the same items compete for the bar and is
    /// dropped once an item arrives or leaves.
    ///
    /// Parked items only count while macOS shows its own overflow control.
    /// An app switched off in System Settings parks at x == -1 too, and no
    /// amount of concealing brings it back.
    static func parkedLaneDeficit(
        previous: Held?,
        parkedWidths: [CGFloat],
        isNativeOverflowActive: Bool,
        modeledHeadroom: CGFloat,
        visibleUIDs: Set<String>,
        overflowUIDs: Set<String>
    ) -> Held? {
        let membership = visibleUIDs.union(overflowUIDs)
        let carried = carriedWidth(from: previous, membership: membership)
        guard isNativeOverflowActive, !parkedWidths.isEmpty else {
            return carried > 0 ? (carried, membership) : nil
        }
        let parked = parkedWidths.reduce(CGFloat.zero) { $0 + budgetWidth(forMeasuredWidth: $1) + 8 }
        let width = max(carried, max(0, modeledHeadroom) + parked)
        return width > 0 ? (width, membership) : nil
    }

    /// Works out this pass's notch deficit from the held one, and holds the result.
    mutating func updateNotchOcclusion(
        occludedControlWidth: CGFloat,
        visibleUIDs: Set<String>,
        overflowUIDs: Set<String>
    ) -> Update {
        let previousWidth = notchOcclusion?.width
        notchOcclusion = Self.notchOcclusionDeficit(
            previous: notchOcclusion,
            occludedControlWidth: occludedControlWidth,
            visibleUIDs: visibleUIDs,
            overflowUIDs: overflowUIDs
        )
        return Update(width: notchOcclusion?.width, previousWidth: previousWidth)
    }

    /// Works out this pass's parked-lane deficit from the held one, and holds the result.
    mutating func updateParkedLane(
        parkedWidths: [CGFloat],
        isNativeOverflowActive: Bool,
        modeledHeadroom: CGFloat,
        visibleUIDs: Set<String>,
        overflowUIDs: Set<String>
    ) -> Update {
        let previousWidth = parkedLane?.width
        parkedLane = Self.parkedLaneDeficit(
            previous: parkedLane,
            parkedWidths: parkedWidths,
            isNativeOverflowActive: isNativeOverflowActive,
            modeledHeadroom: modeledHeadroom,
            visibleUIDs: visibleUIDs,
            overflowUIDs: overflowUIDs
        )
        return Update(width: parkedLane?.width, previousWidth: previousWidth)
    }
}
