//
//  LayoutBarContainerTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

@testable import Thaw
import XCTest

@MainActor
final class LayoutBarContainerTests: XCTestCase {
    func testBadgeOnlySectionHasNoRegularItemDropTargets() {
        let badge = LayoutBarNewItemsBadgeView()

        let regularItemTargets = LayoutBarContainer.enabledDropTargets(
            in: [badge],
            excludingBadge: true
        )
        let badgeDragTargets = LayoutBarContainer.enabledDropTargets(
            in: [badge],
            excludingBadge: false
        )

        XCTAssertTrue(regularItemTargets.isEmpty)
        XCTAssertEqual(badgeDragTargets.count, 1)
        XCTAssertTrue(badgeDragTargets.first === badge)
    }

    func testBadgeOnlyInsertionIndexUsesDropSideOfBadge() {
        let badge = LayoutBarNewItemsBadgeView()
        badge.setFrameOrigin(CGPoint(x: 100, y: 0))

        let beforeBadgeIndex = LayoutBarContainer.emptyTargetInsertionIndex(
            for: badge.frame.midX - 1,
            in: [badge],
            excludingBadge: true
        )
        let afterBadgeIndex = LayoutBarContainer.emptyTargetInsertionIndex(
            for: badge.frame.midX + 1,
            in: [badge],
            excludingBadge: true
        )

        XCTAssertEqual(beforeBadgeIndex, 0)
        XCTAssertEqual(afterBadgeIndex, 1)
    }

    func testEmptySectionInsertionIndexStartsAtBeginning() {
        let insertionIndex = LayoutBarContainer.emptyTargetInsertionIndex(
            for: 500,
            in: [],
            excludingBadge: true
        )

        XCTAssertEqual(insertionIndex, 0)
    }
}
