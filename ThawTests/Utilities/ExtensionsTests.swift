//
//  ExtensionsTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import SwiftUI
import Testing
@testable import Thaw

@Suite("Extensions")
struct ExtensionsTests {
    // MARK: - Comparable.clamped Tests

    @Suite("Comparable.clamped")
    struct ComparableClampedTests {
        // MARK: - clamped(min:max:)

        @Test("A value below the minimum clamps up to it")
        func clampedValueBelowMin() {
            let value = 5
            let result = value.clamped(min: 10, max: 20)
            #expect(result == 10)
        }

        @Test("A value above the maximum clamps down to it")
        func clampedValueAboveMax() {
            let value = 25
            let result = value.clamped(min: 10, max: 20)
            #expect(result == 20)
        }

        @Test("A value inside the range is unchanged")
        func clampedValueInRange() {
            let value = 15
            let result = value.clamped(min: 10, max: 20)
            #expect(result == 15)
        }

        @Test("A value at the minimum is unchanged")
        func clampedValueAtMin() {
            let value = 10
            let result = value.clamped(min: 10, max: 20)
            #expect(result == 10)
        }

        @Test("A value at the maximum is unchanged")
        func clampedValueAtMax() {
            let value = 20
            let result = value.clamped(min: 10, max: 20)
            #expect(result == 20)
        }

        @Test("Doubles clamp the same way")
        func clampedWithDoubles() {
            let value = 1.5
            let result = value.clamped(min: 2.0, max: 3.0)
            #expect(result == 2.0)
        }

        @Test("Negative bounds clamp the same way")
        func clampedWithNegativeValues() {
            let value = -15
            let result = value.clamped(min: -10, max: 10)
            #expect(result == -10)
        }

        @Test("An equal minimum and maximum collapse to one value")
        func clampedWithSameMinMax() {
            let value = 50
            let result = value.clamped(min: 25, max: 25)
            #expect(result == 25)
        }

        // MARK: - clamped(to:)

        @Test("A value below a range clamps to its lower bound")
        func clampedToRangeBelowMin() {
            let value = 5.0
            let result = value.clamped(to: 10.0 ... 20.0)
            #expect(result == 10.0)
        }

        @Test("A value above a range clamps to its upper bound")
        func clampedToRangeAboveMax() {
            let value = 25.0
            let result = value.clamped(to: 10.0 ... 20.0)
            #expect(result == 20.0)
        }

        @Test("A value inside a range is unchanged")
        func clampedToRangeInRange() {
            let value = 15.0
            let result = value.clamped(to: 10.0 ... 20.0)
            #expect(result == 15.0)
        }

        @Test("The unit range clamps at both ends")
        func clampedToZeroToOneRange() {
            #expect((-0.5).clamped(to: 0.0 ... 1.0) == 0.0)
            #expect(0.5.clamped(to: 0.0 ... 1.0) == 0.5)
            #expect(1.5.clamped(to: 0.0 ... 1.0) == 1.0)
        }
    }

    // MARK: - EdgeInsets Extension Tests

    @Suite("EdgeInsets")
    struct EdgeInsetsExtensionTests {
        // MARK: - horizontal

        @Test("horizontal keeps leading and trailing")
        func horizontalPreservesLeadingTrailing() {
            let insets = EdgeInsets(top: 10, leading: 20, bottom: 30, trailing: 40)
            let horizontal = insets.horizontal

            #expect(horizontal.leading == 20)
            #expect(horizontal.trailing == 40)
        }

        @Test("horizontal zeroes top and bottom")
        func horizontalZerosTopBottom() {
            let insets = EdgeInsets(top: 10, leading: 20, bottom: 30, trailing: 40)
            let horizontal = insets.horizontal

            #expect(horizontal.top == 0)
            #expect(horizontal.bottom == 0)
        }

        // MARK: - vertical

        @Test("vertical keeps top and bottom")
        func verticalPreservesTopBottom() {
            let insets = EdgeInsets(top: 10, leading: 20, bottom: 30, trailing: 40)
            let vertical = insets.vertical

            #expect(vertical.top == 10)
            #expect(vertical.bottom == 30)
        }

        @Test("vertical zeroes leading and trailing")
        func verticalZerosLeadingTrailing() {
            let insets = EdgeInsets(top: 10, leading: 20, bottom: 30, trailing: 40)
            let vertical = insets.vertical

            #expect(vertical.leading == 0)
            #expect(vertical.trailing == 0)
        }

        // MARK: - init(all:)

        @Test("init(all:) sets every edge")
        func initAllSetsAllEdges() {
            let insets = EdgeInsets(all: 15)

            #expect(insets.top == 15)
            #expect(insets.leading == 15)
            #expect(insets.bottom == 15)
            #expect(insets.trailing == 15)
        }

        @Test("init(all:) accepts zero")
        func initAllWithZero() {
            let insets = EdgeInsets(all: 0)

            #expect(insets.top == 0)
            #expect(insets.leading == 0)
            #expect(insets.bottom == 0)
            #expect(insets.trailing == 0)
        }

        @Test("init(all:) accepts a negative inset")
        func initAllWithNegative() {
            let insets = EdgeInsets(all: -5)

            #expect(insets.top == -5)
            #expect(insets.leading == -5)
            #expect(insets.bottom == -5)
            #expect(insets.trailing == -5)
        }
    }

    // MARK: - CGImage.ColorAveragingOption Tests

    @Suite("CGImage.ColorAveragingOption")
    struct ColorAveragingOptionTests {
        @Test("ignoreAlpha is bit 0")
        func ignoreAlphaRawValue() {
            let option = CGImage.ColorAveragingOption.ignoreAlpha
            #expect(option.rawValue == 1 << 0)
        }

        @Test("An empty option set contains nothing")
        func emptyOptionSet() {
            let option: CGImage.ColorAveragingOption = []
            #expect(!option.contains(.ignoreAlpha))
        }

        @Test("A set containing ignoreAlpha reports it")
        func containsIgnoreAlpha() {
            let option: CGImage.ColorAveragingOption = [.ignoreAlpha]
            #expect(option.contains(.ignoreAlpha))
        }
    }
}
