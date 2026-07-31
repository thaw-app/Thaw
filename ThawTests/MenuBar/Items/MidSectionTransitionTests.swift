//
//  MidSectionTransitionTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Testing
@testable import Thaw

/// Tests for the rule that spots a cache pass taken part-way through a
/// section expand or collapse.
///
/// A collapsed section stretches its control item across the displays; an
/// expanded one leaves it at `NSStatusItem.variableLength`. The drag and the
/// resize are separate steps, so a pass can observe revealed items behind a
/// still-stretched divider — and classifying against that mixture moves an
/// entire section into `visible`.
@Suite("Mid-section transition")
struct MidSectionTransitionTests {
    /// Width the window server reports for a collapsed section's divider. The
    /// requested 10000 pt is clamped to roughly the span of the displays; this
    /// is a real value from the #851 log.
    private let stretchedWidth: CGFloat = 5000

    /// A marker-width divider. `NSStatusItem.variableLength` measures in
    /// single digits once laid out, and the #851 log also shows exactly 0.
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

    /// The #851 pass: the section had been expanded and its items were already
    /// at revealed coordinates, but the divider still carried the stretched
    /// width of the collapsed layout.
    @Test("An expanded section with a stretched divider is mid-transition")
    func expandedSectionWithStretchedDividerIsMidTransition() {
        #expect(
            MenuBarItemManager.isMidSectionTransition(
                dividerWidth: stretchedWidth,
                isSectionCollapsed: false
            )
        )
    }

    /// The reverse straddle, seen while a section collapses: the divider has
    /// already shrunk but the items have not been parked yet.
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

    /// Widths from the #851 log, which range from 4656 to 5002 depending on the
    /// display arrangement, all have to read as stretched.
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
