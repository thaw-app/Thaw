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
