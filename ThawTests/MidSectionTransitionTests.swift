//
//  MidSectionTransitionTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
@testable import Thaw
import XCTest

/// Tests for the rule that spots a cache pass taken part-way through a
/// section expand or collapse.
///
/// A collapsed section stretches its control item across the displays; an
/// expanded one leaves it at `NSStatusItem.variableLength`. The drag and the
/// resize are separate steps, so a pass can observe revealed items behind a
/// still-stretched divider — and classifying against that mixture moves an
/// entire section into `visible`.
final class MidSectionTransitionTests: XCTestCase {
    /// Width the window server reports for a collapsed section's divider. The
    /// requested 10000 pt is clamped to roughly the span of the displays; this
    /// is a real value from the #851 log.
    private let stretchedWidth: CGFloat = 5000

    /// A marker-width divider. `NSStatusItem.variableLength` measures in
    /// single digits once laid out, and the #851 log also shows exactly 0.
    private let markerWidth: CGFloat = 0

    func testCollapsedSectionWithStretchedDividerIsConsistent() {
        XCTAssertFalse(
            MenuBarItemManager.isMidSectionTransition(
                dividerWidth: stretchedWidth,
                isSectionCollapsed: true
            )
        )
    }

    func testExpandedSectionWithMarkerDividerIsConsistent() {
        XCTAssertFalse(
            MenuBarItemManager.isMidSectionTransition(
                dividerWidth: markerWidth,
                isSectionCollapsed: false
            )
        )
    }

    /// The #851 pass: the section had been expanded and its items were already
    /// at revealed coordinates, but the divider still carried the stretched
    /// width of the collapsed layout.
    func testExpandedSectionWithStretchedDividerIsMidTransition() {
        XCTAssertTrue(
            MenuBarItemManager.isMidSectionTransition(
                dividerWidth: stretchedWidth,
                isSectionCollapsed: false
            )
        )
    }

    /// The reverse straddle, seen while a section collapses: the divider has
    /// already shrunk but the items have not been parked yet.
    func testCollapsedSectionWithMarkerDividerIsMidTransition() {
        XCTAssertTrue(
            MenuBarItemManager.isMidSectionTransition(
                dividerWidth: markerWidth,
                isSectionCollapsed: true
            )
        )
    }

    /// A laid-out `variableLength` divider is a few points wide, not zero, and
    /// must still read as a marker.
    func testSmallNonZeroWidthCountsAsMarker() {
        XCTAssertTrue(
            MenuBarItemManager.isMidSectionTransition(
                dividerWidth: 8,
                isSectionCollapsed: true
            )
        )
        XCTAssertFalse(
            MenuBarItemManager.isMidSectionTransition(
                dividerWidth: 8,
                isSectionCollapsed: false
            )
        )
    }

    /// Widths from the #851 log, which range from 4656 to 5002 depending on the
    /// display arrangement, all have to read as stretched.
    func testObservedStretchedWidthsAllReadAsCollapsed() {
        for width in [4656, 5000, 5002, 3068] as [CGFloat] {
            XCTAssertFalse(
                MenuBarItemManager.isMidSectionTransition(
                    dividerWidth: width,
                    isSectionCollapsed: true
                ),
                "width \(width) should read as a stretched divider"
            )
        }
    }
}
