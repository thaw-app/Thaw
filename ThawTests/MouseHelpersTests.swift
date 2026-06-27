//
//  MouseHelpersTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

@testable import Thaw
import XCTest

final class MouseHelpersTests: XCTestCase {
    func testCoreGraphicsPointUsesTargetDisplayBoundsWithOffsetOrigin() {
        let externalDisplayBounds = CGRect(
            x: 1440,
            y: -180,
            width: 1920,
            height: 1080
        )

        XCTAssertTrue(
            MouseHelpers.isCoreGraphicsPoint(
                CGPoint(x: 1500, y: -170),
                insideDisplayBounds: externalDisplayBounds
            )
        )
        XCTAssertFalse(
            MouseHelpers.isCoreGraphicsPoint(
                CGPoint(x: 1500, y: 920),
                insideDisplayBounds: externalDisplayBounds
            )
        )
    }

    func testCoreGraphicsPointRejectsEmptyDisplayBounds() {
        XCTAssertFalse(
            MouseHelpers.isCoreGraphicsPoint(
                CGPoint(x: 0, y: 0),
                insideDisplayBounds: .zero
            )
        )
    }
}
