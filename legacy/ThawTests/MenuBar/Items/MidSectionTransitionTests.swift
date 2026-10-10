//
//  MidSectionTransitionTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Testing
@testable import Thaw

/// Spots a cache pass taken part-way through a section expand or collapse.
///
/// A collapsed section stretches its divider across the displays; an expanded
/// one leaves it at `NSStatusItem.variableLength`. Drag and resize are separate
/// steps, so a pass can see revealed items behind a still-stretched divider,
/// and classifying that mixture moves a whole section into `visible`.
@Suite("Mid-section transition")
struct MidSectionTransitionTests {
    /// A collapsed divider's width as reported (#851 log): the requested 10000 pt
    /// is clamped to roughly the span of the displays.
    private let stretchedWidth: CGFloat = 5000

    /// `variableLength` measures in single digits once laid out; the #851 log also shows 0.
    private let markerWidth: CGFloat = 0

    @Test("A collapsed section with a stretched divider is consistent")
    func collapsedSectionWithStretchedDividerIsConsistent() {
        #expect(
            !MenuBarItemManager.isMidSectionTransition(
                dividerWidth: stretchedWidth,
                isSectionCollapsed: true
            )
        )
    }

    @Test("An expanded section with a marker divider is consistent")
    func expandedSectionWithMarkerDividerIsConsistent() {
        #expect(
            !MenuBarItemManager.isMidSectionTransition(
                dividerWidth: markerWidth,
                isSectionCollapsed: false
            )
        )
    }

    /// The #851 pass: items already at revealed coordinates, divider still stretched.
    @Test("An expanded section with a stretched divider is mid-transition")
    func expandedSectionWithStretchedDividerIsMidTransition() {
        #expect(
            MenuBarItemManager.isMidSectionTransition(
                dividerWidth: stretchedWidth,
                isSectionCollapsed: false
            )
        )
    }

    /// The reverse, while collapsing: the divider has shrunk but items are not parked yet.
    @Test("A collapsed section with a marker divider is mid-transition")
    func collapsedSectionWithMarkerDividerIsMidTransition() {
        #expect(
            MenuBarItemManager.isMidSectionTransition(
                dividerWidth: markerWidth,
                isSectionCollapsed: true
            )
        )
    }

    /// A laid-out `variableLength` divider is a few points wide, not zero, and
    /// must still read as a marker.
    @Test("A small non-zero width still counts as a marker")
    func smallNonZeroWidthCountsAsMarker() {
        #expect(
            MenuBarItemManager.isMidSectionTransition(
                dividerWidth: 8,
                isSectionCollapsed: true
            )
        )
        #expect(
            !MenuBarItemManager.isMidSectionTransition(
                dividerWidth: 8,
                isSectionCollapsed: false
            )
        )
    }

    /// Observed widths range from 4656 to 5002 by display arrangement; all read as stretched.
    @Test("Every observed stretched width reads as a stretched divider")
    func observedStretchedWidthsAllReadAsCollapsed() {
        for width in [4656, 5000, 5002, 3068] as [CGFloat] {
            #expect(
                !MenuBarItemManager.isMidSectionTransition(
                    dividerWidth: width,
                    isSectionCollapsed: true
                ),
                "width \(width) should read as a stretched divider"
            )
        }
    }
}
