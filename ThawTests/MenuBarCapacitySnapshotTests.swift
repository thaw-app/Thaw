//
//  MenuBarCapacitySnapshotTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

@testable import Thaw
import XCTest

final class MenuBarCapacitySnapshotTests: XCTestCase {
    func testNonNotchedCapacityUsesApplicationMenuAndControlCenter() {
        let snapshot = makeSnapshot(
            displayBounds: CGRect(x: 0, y: 0, width: 1200, height: 800),
            applicationMenuFrame: CGRect(x: 0, y: 0, width: 250, height: 30),
            trailingBoundary: 1100
        )

        XCTAssertEqual(
            snapshot.availableWidth(in: .trailing, applicationMenus: .visible),
            850
        )
    }

    func testNotchedTrailingCapacityUsesOnlyRightLane() {
        let snapshot = makeSnapshot(
            displayBounds: CGRect(x: 0, y: 0, width: 1600, height: 1000),
            notchFrame: CGRect(x: 700, y: 0, width: 200, height: 30),
            applicationMenuFrame: CGRect(x: 0, y: 0, width: 200, height: 30),
            trailingBoundary: 1500
        )

        XCTAssertEqual(
            snapshot.availableWidth(in: .trailing, applicationMenus: .visible),
            576
        )
    }

    func testNotchedInlineCapacitySumsBothLanes() {
        let snapshot = makeSnapshot(
            displayBounds: CGRect(x: 0, y: 0, width: 1600, height: 1000),
            notchFrame: CGRect(x: 700, y: 0, width: 200, height: 30),
            applicationMenuFrame: CGRect(x: 0, y: 0, width: 200, height: 30),
            trailingBoundary: 1500
        )

        XCTAssertEqual(
            snapshot.availableWidth(in: .inline, applicationMenus: .visible),
            1052
        )
        XCTAssertEqual(
            snapshot.availableWidth(in: .inline, applicationMenus: .hidden),
            1252
        )
    }

    func testReservationsAreClippedAndUnionedOnce() {
        let snapshot = makeSnapshot(
            displayBounds: CGRect(x: 0, y: 0, width: 1200, height: 800),
            applicationMenuFrame: CGRect(x: 0, y: 0, width: 250, height: 30),
            trailingBoundary: 1100,
            overflowControlBounds: [CGRect(x: 1000, y: 0, width: 20, height: 30)]
        )

        XCTAssertEqual(
            snapshot.availableWidth(
                in: .trailing,
                applicationMenus: .visible,
                reserving: [
                    CGRect(x: 900, y: 0, width: 50, height: 30),
                    CGRect(x: 925, y: 0, width: 50, height: 30),
                ]
            ),
            755
        )
    }

    func testReservationsFromVerticallyStackedDisplayAreIgnored() {
        let snapshot = makeSnapshot(
            displayBounds: CGRect(x: 0, y: 0, width: 1200, height: 800),
            applicationMenuFrame: CGRect(x: 0, y: 0, width: 250, height: 30),
            trailingBoundary: 1100
        )

        XCTAssertEqual(
            snapshot.availableWidth(
                in: .trailing,
                applicationMenus: .visible,
                reserving: [CGRect(x: 900, y: 900, width: 100, height: 30)]
            ),
            850
        )
    }

    func testSecondaryDisplayGlobalCoordinatesDoNotChangeWidth() {
        let snapshot = makeSnapshot(
            displayBounds: CGRect(x: -1600, y: 0, width: 1600, height: 1000),
            notchFrame: CGRect(x: -900, y: 0, width: 200, height: 30),
            applicationMenuFrame: CGRect(x: -1600, y: 0, width: 200, height: 30),
            trailingBoundary: -100
        )

        XCTAssertEqual(
            snapshot.availableWidth(in: .trailing, applicationMenus: .visible),
            576
        )
    }

    func testMissingApplicationMenuOnlyInvalidatesVisibleMenuCapacity() {
        let snapshot = makeSnapshot(
            displayBounds: CGRect(x: 0, y: 0, width: 1200, height: 800),
            applicationMenuFrame: nil,
            trailingBoundary: 1100
        )

        XCTAssertNil(snapshot.availableWidth(in: .inline, applicationMenus: .visible))
        XCTAssertEqual(
            snapshot.availableWidth(in: .inline, applicationMenus: .hidden),
            1100
        )
    }

    func testInvalidTrailingBoundaryRejectsUnsettledGeometry() {
        let snapshot = makeSnapshot(
            displayBounds: CGRect(x: 0, y: 0, width: 1200, height: 800),
            applicationMenuFrame: CGRect(x: 0, y: 0, width: 250, height: 30),
            trailingBoundary: 1400
        )

        XCTAssertNil(snapshot.availableWidth(in: .trailing, applicationMenus: .visible))
    }

    private func makeSnapshot(
        displayBounds: CGRect,
        notchFrame: CGRect? = nil,
        applicationMenuFrame: CGRect?,
        trailingBoundary: CGFloat,
        overflowControlBounds: [CGRect] = []
    ) -> MenuBarCapacitySnapshot {
        MenuBarCapacitySnapshot(
            displayID: 1,
            displayBounds: displayBounds,
            notchFrame: notchFrame,
            applicationMenuFrame: applicationMenuFrame,
            trailingBoundary: trailingBoundary,
            overflowControlBounds: overflowControlBounds
        )
    }
}
