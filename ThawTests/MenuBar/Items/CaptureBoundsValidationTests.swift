//
//  CaptureBoundsValidationTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Testing
@testable import Thaw

/// Regression tests for the capture-bounds validation guard added for
/// issue #759 (degenerate capture rectangles crashing WindowServer).
@Suite("Capture bounds validation")
struct CaptureBoundsValidationTests {
    @Test("A null rect is valid")
    func nullBoundsAreValid() {
        #expect(Bridging.isValidCaptureBounds(.null))
    }

    @Test("An ordinary menu bar rect is valid")
    func normalBoundsAreValid() {
        let bounds = CGRect(x: 0, y: 0, width: 1470, height: 33)
        #expect(Bridging.isValidCaptureBounds(bounds))
    }

    @Test("A zero width is invalid")
    func zeroWidthIsInvalid() {
        let bounds = CGRect(x: 0, y: 0, width: 0, height: 33)
        #expect(!Bridging.isValidCaptureBounds(bounds))
    }

    @Test("A zero height is invalid")
    func zeroHeightIsInvalid() {
        let bounds = CGRect(x: 0, y: 0, width: 100, height: 0)
        #expect(!Bridging.isValidCaptureBounds(bounds))
    }

    @Test("A negative width is invalid")
    func negativeWidthIsInvalid() {
        let bounds = CGRect(x: 0, y: 0, width: -100, height: 33)
        #expect(!Bridging.isValidCaptureBounds(bounds))
    }

    @Test("A negative height is invalid")
    func negativeHeightIsInvalid() {
        let bounds = CGRect(x: 0, y: 0, width: 100, height: -33)
        #expect(!Bridging.isValidCaptureBounds(bounds))
    }

    @Test("A non-finite origin is invalid")
    func nonFiniteOriginIsInvalid() {
        let bounds = CGRect(x: CGFloat.nan, y: 0, width: 100, height: 33)
        #expect(!Bridging.isValidCaptureBounds(bounds))
    }

    @Test("The infinite rect is invalid")
    func infiniteRectIsInvalid() {
        #expect(!Bridging.isValidCaptureBounds(.infinite))
    }

    @Test("A dimension exactly at the maximum is valid")
    func dimensionAtMaximumIsValid() {
        let bounds = CGRect(x: 0, y: 0, width: CGFloat(Bridging.maximumCaptureDimension), height: 33)
        #expect(Bridging.isValidCaptureBounds(bounds))
    }

    @Test("A dimension over the maximum is invalid")
    func dimensionOverMaximumIsInvalid() {
        let bounds = CGRect(x: 0, y: 0, width: CGFloat(Bridging.maximumCaptureDimension + 1), height: 33)
        #expect(!Bridging.isValidCaptureBounds(bounds))
    }

    @Test("The scale is applied before the maximum check")
    func scaleAppliedBeforeMaximumCheck() {
        // 8500 points at 2x scale is 17000px, past the 16384px limit even
        // though the point-space rect looks reasonable on its own.
        let bounds = CGRect(x: 0, y: 0, width: 8500, height: 33)
        #expect(!Bridging.isValidCaptureBounds(bounds, scale: 2.0))
    }

    @Test("A non-finite scale is invalid")
    func nonFiniteScaleIsInvalid() {
        let bounds = CGRect(x: 0, y: 0, width: 100, height: 33)
        #expect(!Bridging.isValidCaptureBounds(bounds, scale: .nan))
    }

    @Test("A zero scale is invalid")
    func zeroScaleIsInvalid() {
        let bounds = CGRect(x: 0, y: 0, width: 100, height: 33)
        #expect(!Bridging.isValidCaptureBounds(bounds, scale: 0))
    }

    @Test("A negative scale is invalid")
    func negativeScaleIsInvalid() {
        let bounds = CGRect(x: 0, y: 0, width: 100, height: 33)
        #expect(!Bridging.isValidCaptureBounds(bounds, scale: -1))
    }
}
