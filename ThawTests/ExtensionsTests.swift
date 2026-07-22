//
//  ExtensionsTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI
@testable import Thaw
import XCTest

// MARK: - NSBezierPath.drawShadow Tests

final class NSBezierPathDrawShadowTests: XCTestCase {
    @MainActor
    func testDrawShadowNoOpsForEmptyPath() {
        NSBezierPath().drawShadow(color: .black, radius: 5)
    }
}

// MARK: - Comparable.clamped Tests

final class ComparableClampedTests: XCTestCase {
    // MARK: - clamped(min:max:)

    func testClampedValueBelowMin() {
        let value = 5
        let result = value.clamped(min: 10, max: 20)
        XCTAssertEqual(result, 10)
    }

    func testClampedValueAboveMax() {
        let value = 25
        let result = value.clamped(min: 10, max: 20)
        XCTAssertEqual(result, 20)
    }

    func testClampedValueInRange() {
        let value = 15
        let result = value.clamped(min: 10, max: 20)
        XCTAssertEqual(result, 15)
    }

    func testClampedValueAtMin() {
        let value = 10
        let result = value.clamped(min: 10, max: 20)
        XCTAssertEqual(result, 10)
    }

    func testClampedValueAtMax() {
        let value = 20
        let result = value.clamped(min: 10, max: 20)
        XCTAssertEqual(result, 20)
    }

    func testClampedWithDoubles() {
        let value = 1.5
        let result = value.clamped(min: 2.0, max: 3.0)
        XCTAssertEqual(result, 2.0)
    }

    func testClampedWithNegativeValues() {
        let value = -15
        let result = value.clamped(min: -10, max: 10)
        XCTAssertEqual(result, -10)
    }

    func testClampedWithSameMinMax() {
        let value = 50
        let result = value.clamped(min: 25, max: 25)
        XCTAssertEqual(result, 25)
    }

    // MARK: - clamped(to:)

    func testClampedToRangeBelowMin() {
        let value = 5.0
        let result = value.clamped(to: 10.0 ... 20.0)
        XCTAssertEqual(result, 10.0)
    }

    func testClampedToRangeAboveMax() {
        let value = 25.0
        let result = value.clamped(to: 10.0 ... 20.0)
        XCTAssertEqual(result, 20.0)
    }

    func testClampedToRangeInRange() {
        let value = 15.0
        let result = value.clamped(to: 10.0 ... 20.0)
        XCTAssertEqual(result, 15.0)
    }

    func testClampedToZeroToOneRange() {
        XCTAssertEqual((-0.5).clamped(to: 0.0 ... 1.0), 0.0)
        XCTAssertEqual(0.5.clamped(to: 0.0 ... 1.0), 0.5)
        XCTAssertEqual(1.5.clamped(to: 0.0 ... 1.0), 1.0)
    }
}

// MARK: - EdgeInsets Extension Tests

final class EdgeInsetsExtensionTests: XCTestCase {
    // MARK: - horizontal

    func testHorizontalPreservesLeadingTrailing() {
        let insets = EdgeInsets(top: 10, leading: 20, bottom: 30, trailing: 40)
        let horizontal = insets.horizontal

        XCTAssertEqual(horizontal.leading, 20)
        XCTAssertEqual(horizontal.trailing, 40)
    }

    func testHorizontalZerosTopBottom() {
        let insets = EdgeInsets(top: 10, leading: 20, bottom: 30, trailing: 40)
        let horizontal = insets.horizontal

        XCTAssertEqual(horizontal.top, 0)
        XCTAssertEqual(horizontal.bottom, 0)
    }

    // MARK: - vertical

    func testVerticalPreservesTopBottom() {
        let insets = EdgeInsets(top: 10, leading: 20, bottom: 30, trailing: 40)
        let vertical = insets.vertical

        XCTAssertEqual(vertical.top, 10)
        XCTAssertEqual(vertical.bottom, 30)
    }

    func testVerticalZerosLeadingTrailing() {
        let insets = EdgeInsets(top: 10, leading: 20, bottom: 30, trailing: 40)
        let vertical = insets.vertical

        XCTAssertEqual(vertical.leading, 0)
        XCTAssertEqual(vertical.trailing, 0)
    }

    // MARK: - init(all:)

    func testInitAllSetsAllEdges() {
        let insets = EdgeInsets(all: 15)

        XCTAssertEqual(insets.top, 15)
        XCTAssertEqual(insets.leading, 15)
        XCTAssertEqual(insets.bottom, 15)
        XCTAssertEqual(insets.trailing, 15)
    }

    func testInitAllWithZero() {
        let insets = EdgeInsets(all: 0)

        XCTAssertEqual(insets.top, 0)
        XCTAssertEqual(insets.leading, 0)
        XCTAssertEqual(insets.bottom, 0)
        XCTAssertEqual(insets.trailing, 0)
    }

    func testInitAllWithNegative() {
        let insets = EdgeInsets(all: -5)

        XCTAssertEqual(insets.top, -5)
        XCTAssertEqual(insets.leading, -5)
        XCTAssertEqual(insets.bottom, -5)
        XCTAssertEqual(insets.trailing, -5)
    }
}

// MARK: - RangeReplaceableCollection.removingDuplicates Tests

final class RemovingDuplicatesTests: XCTestCase {
    func testRemovingDuplicatesFromArrayWithDuplicates() {
        let array = [1, 2, 2, 3, 3, 3, 4]
        let result = array.removingDuplicates()

        XCTAssertEqual(result, [1, 2, 3, 4])
    }

    func testRemovingDuplicatesFromArrayWithoutDuplicates() {
        let array = [1, 2, 3, 4, 5]
        let result = array.removingDuplicates()

        XCTAssertEqual(result, [1, 2, 3, 4, 5])
    }

    func testRemovingDuplicatesFromEmptyArray() {
        let array: [Int] = []
        let result = array.removingDuplicates()

        XCTAssertEqual(result, [])
    }

    func testRemovingDuplicatesPreservesOrder() {
        let array = [3, 1, 2, 1, 3, 2]
        let result = array.removingDuplicates()

        // First occurrence of each element preserved
        XCTAssertEqual(result, [3, 1, 2])
    }

    func testRemovingDuplicatesWithStrings() {
        let array = ["a", "b", "a", "c", "b"]
        let result = array.removingDuplicates()

        XCTAssertEqual(result, ["a", "b", "c"])
    }

    func testRemovingDuplicatesAllSame() {
        let array = [5, 5, 5, 5, 5]
        let result = array.removingDuplicates()

        XCTAssertEqual(result, [5])
    }

    func testRemovingDuplicatesSingleElement() {
        let array = [42]
        let result = array.removingDuplicates()

        XCTAssertEqual(result, [42])
    }
}

// MARK: - CGImage.ColorAveragingOption Tests

final class ColorAveragingOptionTests: XCTestCase {
    func testIgnoreAlphaRawValue() {
        let option = CGImage.ColorAveragingOption.ignoreAlpha
        XCTAssertEqual(option.rawValue, 1 << 0)
    }

    func testEmptyOptionSet() {
        let option: CGImage.ColorAveragingOption = []
        XCTAssertFalse(option.contains(.ignoreAlpha))
    }

    func testContainsIgnoreAlpha() {
        let option: CGImage.ColorAveragingOption = [.ignoreAlpha]
        XCTAssertTrue(option.contains(.ignoreAlpha))
    }
}

// MARK: - CGImage Background Knockout Tests

final class CGImageBackgroundKnockOutTests: XCTestCase {
    func testKnockingOutNearUniformBackgroundClearsFillKeepsGlyph() throws {
        let width = 32
        let height = 24
        let bytesPerRow = width * 4
        var data = [UInt8](repeating: 0, count: bytesPerRow * height)
        // Opaque dark fill.
        for i in stride(from: 0, to: data.count, by: 4) {
            data[i] = 40
            data[i + 1] = 40
            data[i + 2] = 40
            data[i + 3] = 255
        }
        // Bright glyph block in the center.
        for y in 8 ..< 16 {
            for x in 12 ..< 20 {
                let i = y * bytesPerRow + x * 4
                data[i] = 240
                data[i + 1] = 240
                data[i + 2] = 240
                data[i + 3] = 255
            }
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let image = try XCTUnwrap(
            CGContext(
                data: &data,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )?.makeImage()
        )

        let cleaned = try XCTUnwrap(image.knockingOutNearUniformBackground(maxColorDistance: 40))
        XCTAssertFalse(cleaned.isTransparent(alphaThreshold: 0.05))

        // Corner should be cleared; center glyph should remain.
        let cornerAlpha = try XCTUnwrap(alpha(atX: 0, y: 0, in: cleaned))
        let centerAlpha = try XCTUnwrap(alpha(atX: 16, y: 12, in: cleaned))
        XCTAssertLessThan(cornerAlpha, 10)
        XCTAssertGreaterThan(centerAlpha, 200)
    }

    private func alpha(atX x: Int, y: Int, in image: CGImage) -> UInt8? {
        var pixel = [UInt8](repeating: 0, count: 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: &pixel,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        context.draw(
            image,
            in: CGRect(x: -x, y: -y, width: image.width, height: image.height)
        )
        return pixel[3]
    }
}
