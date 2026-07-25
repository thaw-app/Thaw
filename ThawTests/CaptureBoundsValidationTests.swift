//
//  CaptureBoundsValidationTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

@testable import Thaw
import XCTest

/// Regression tests for the capture-bounds validation guard added for
/// issue #759 (degenerate capture rectangles crashing WindowServer).
final class CaptureBoundsValidationTests: XCTestCase {
    func testNullBoundsAreValid() {
        XCTAssertTrue(Bridging.isValidCaptureBounds(.null))
    }

    func testNormalBoundsAreValid() {
        let bounds = CGRect(x: 0, y: 0, width: 1470, height: 33)
        XCTAssertTrue(Bridging.isValidCaptureBounds(bounds))
    }

    func testZeroWidthIsInvalid() {
        let bounds = CGRect(x: 0, y: 0, width: 0, height: 33)
        XCTAssertFalse(Bridging.isValidCaptureBounds(bounds))
    }

    func testZeroHeightIsInvalid() {
        let bounds = CGRect(x: 0, y: 0, width: 100, height: 0)
        XCTAssertFalse(Bridging.isValidCaptureBounds(bounds))
    }

    func testNegativeWidthIsInvalid() {
        let bounds = CGRect(x: 0, y: 0, width: -100, height: 33)
        XCTAssertFalse(Bridging.isValidCaptureBounds(bounds))
    }

    func testNegativeHeightIsInvalid() {
        let bounds = CGRect(x: 0, y: 0, width: 100, height: -33)
        XCTAssertFalse(Bridging.isValidCaptureBounds(bounds))
    }

    func testNonFiniteOriginIsInvalid() {
        let bounds = CGRect(x: CGFloat.nan, y: 0, width: 100, height: 33)
        XCTAssertFalse(Bridging.isValidCaptureBounds(bounds))
    }

    func testInfiniteRectIsInvalid() {
        XCTAssertFalse(Bridging.isValidCaptureBounds(.infinite))
    }

    func testDimensionAtMaximumIsValid() {
        let bounds = CGRect(x: 0, y: 0, width: CGFloat(Bridging.maximumCaptureDimension), height: 33)
        XCTAssertTrue(Bridging.isValidCaptureBounds(bounds))
    }

    func testDimensionOverMaximumIsInvalid() {
        let bounds = CGRect(x: 0, y: 0, width: CGFloat(Bridging.maximumCaptureDimension + 1), height: 33)
        XCTAssertFalse(Bridging.isValidCaptureBounds(bounds))
    }

    func testScaleAppliedBeforeMaximumCheck() {
        // 8500 points at 2x scale is 17000px, past the 16384px limit even
        // though the point-space rect looks reasonable on its own.
        let bounds = CGRect(x: 0, y: 0, width: 8500, height: 33)
        XCTAssertFalse(Bridging.isValidCaptureBounds(bounds, scale: 2.0))
    }

    func testNonFiniteScaleIsInvalid() {
        let bounds = CGRect(x: 0, y: 0, width: 100, height: 33)
        XCTAssertFalse(Bridging.isValidCaptureBounds(bounds, scale: .nan))
    }

    func testZeroScaleIsInvalid() {
        let bounds = CGRect(x: 0, y: 0, width: 100, height: 33)
        XCTAssertFalse(Bridging.isValidCaptureBounds(bounds, scale: 0))
    }

    func testNegativeScaleIsInvalid() {
        let bounds = CGRect(x: 0, y: 0, width: 100, height: 33)
        XCTAssertFalse(Bridging.isValidCaptureBounds(bounds, scale: -1))
    }
}
