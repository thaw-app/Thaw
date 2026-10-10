//
//  ExtensionsTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Combine
import CoreGraphics
import Foundation
import os.lock
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

    // MARK: - Bundle

    /// `Bundle`'s accessors are plain `Info.plist` lookups, but `displayName`
    /// has a three-step fallback chain that is worth pinning down. Each case
    /// builds a throwaway bundle directory so the assertions never depend on
    /// the test host's own `Info.plist`.
    @Suite("Bundle metadata")
    struct BundleMetadataTests {
        /// Writes `info` as `Contents/Info.plist` inside a fresh
        /// `<temp>/<uuid>/Test.bundle` directory and returns the bundle URL.
        /// The caller is expected to delete the enclosing directory.
        private func makeBundleDirectory(info: [String: Any]) throws -> URL {
            let root = FileManager.default.temporaryDirectory
                .appendingPathComponent("BundleMetadataTests-\(UUID().uuidString)", isDirectory: true)
            let bundleURL = root.appendingPathComponent("Test.bundle", isDirectory: true)
            let contents = bundleURL.appendingPathComponent("Contents", isDirectory: true)
            try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
            let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            try data.write(to: contents.appendingPathComponent("Info.plist"))
            return bundleURL
        }

        @Test("Every string accessor reads its own Info.plist key")
        func accessorsReadTheirKeys() throws {
            let url = try makeBundleDirectory(info: [
                "NSHumanReadableCopyright": "Copyright © 2026",
                "CFBundleDisplayName": "Displayed",
                "CFBundleName": "Named",
                "CFBundleShortVersionString": "1.2.3",
                "CFBundleVersion": "456",
            ])
            defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
            let bundle = try #require(Bundle(url: url), "Could not open the generated bundle")

            #expect(bundle.copyrightString == "Copyright © 2026")
            #expect(bundle.displayName == "Displayed")
            #expect(bundle.versionString == "1.2.3")
            #expect(bundle.buildString == "456")
        }

        @Test("displayName falls back to CFBundleName")
        func displayNameFallsBackToBundleName() throws {
            let url = try makeBundleDirectory(info: ["CFBundleName": "Named"])
            defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
            let bundle = try #require(Bundle(url: url), "Could not open the generated bundle")

            #expect(bundle.displayName == "Named")
        }

        @Test("displayName falls back to Thaw when neither name key is present")
        func displayNameFallsBackToThaw() throws {
            let url = try makeBundleDirectory(info: ["NSHumanReadableCopyright": "Copyright © 2026"])
            defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
            let bundle = try #require(Bundle(url: url), "Could not open the generated bundle")

            // The copyright key proves the plist really was read, so the
            // fallback below is a fallback and not a failed lookup.
            #expect(bundle.copyrightString == "Copyright © 2026")
            #expect(bundle.displayName == "Thaw")
        }

        @Test("The optional accessors are nil when their keys are missing")
        func missingKeysAreNil() throws {
            let url = try makeBundleDirectory(info: ["CFBundleName": "Named"])
            defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
            let bundle = try #require(Bundle(url: url), "Could not open the generated bundle")

            #expect(bundle.copyrightString == nil)
            #expect(bundle.versionString == nil)
            #expect(bundle.buildString == nil)
        }

        /// A non-string value must not be surfaced as a string.
        @Test("A wrongly typed value reads as absent")
        func wronglyTypedValueIsNil() throws {
            let url = try makeBundleDirectory(info: [
                "CFBundleShortVersionString": 42,
                "CFBundleDisplayName": ["not", "a", "string"],
            ])
            defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
            let bundle = try #require(Bundle(url: url), "Could not open the generated bundle")

            #expect(bundle.versionString == nil)
            #expect(bundle.displayName == "Thaw")
        }
    }

    // MARK: - OSAllocatedUnfairLock

    /// `tryClaimOnce` exists so a continuation is resumed exactly once when a
    /// timeout and a callback race. The single-claimant case is the contract;
    /// the concurrent case is the reason the contract exists.
    @Suite("Single-shot claiming")
    struct TryClaimOnceTests {
        @Test("The first claim wins and later claims lose")
        func firstClaimWins() {
            let lock = OSAllocatedUnfairLock(initialState: false)

            #expect(lock.tryClaimOnce())
            #expect(!lock.tryClaimOnce())
            #expect(!lock.tryClaimOnce())
        }

        @Test("An already-claimed lock never hands out a claim")
        func preClaimedLockNeverWins() {
            let lock = OSAllocatedUnfairLock(initialState: true)

            #expect(!lock.tryClaimOnce())
        }

        @Test("Exactly one of many concurrent claimants wins")
        func onlyOneConcurrentClaimantWins() async {
            let lock = OSAllocatedUnfairLock(initialState: false)
            let winners = OSAllocatedUnfairLock(initialState: 0)

            await withTaskGroup(of: Void.self) { group in
                for _ in 0 ..< 64 {
                    group.addTask {
                        if lock.tryClaimOnce() {
                            winners.withLock { $0 += 1 }
                        }
                    }
                }
            }

            let total = winners.withLock { $0 }
            #expect(total == 1)
        }
    }

    // MARK: - Publisher

    /// The Combine helpers are all thin, but each one is wired into a live
    /// pipeline in `MenuBarManager`, `ControlItem`, and `IceBarColorManager`,
    /// where a wrong arity (one event instead of one per element) or a dropped
    /// element would be invisible. Every case drives a real subscription.
    @MainActor
    @Suite("Publisher operators")
    struct PublisherOperatorTests {
        @Test("replace calls its closure once per upstream element")
        func replaceCallsClosurePerElement() {
            let subject = PassthroughSubject<Int, Never>()
            var calls = 0
            var received = [String]()

            let cancellable = subject
                .replace { calls += 1; return "x\(calls)" }
                .sink { received.append($0) }

            subject.send(1)
            subject.send(2)
            subject.send(3)
            cancellable.cancel()

            #expect(calls == 3)
            #expect(received == ["x1", "x2", "x3"])
        }

        @Test("replace(with:) republishes the same element every time")
        func replaceWithRepublishesConstant() {
            let subject = PassthroughSubject<Int, Never>()
            var received = [String]()

            let cancellable = subject
                .replace(with: "constant")
                .sink { received.append($0) }

            subject.send(1)
            subject.send(2)
            cancellable.cancel()

            #expect(received == ["constant", "constant"])
        }

        @Test("A publisher that never fires produces no replacements")
        func replaceOnSilentPublisherProducesNothing() {
            let subject = PassthroughSubject<Int, Never>()
            var received = [String]()

            let cancellable = subject
                .replace(with: "constant")
                .sink { received.append($0) }
            cancellable.cancel()

            #expect(received.isEmpty)
        }

        @Test("removeNil drops nil elements and unwraps the rest")
        func removeNilUnwraps() {
            let subject = PassthroughSubject<Int?, Never>()
            var received = [Int]()

            let cancellable = subject
                .removeNil()
                .sink { received.append($0) }

            subject.send(1)
            subject.send(nil)
            subject.send(2)
            subject.send(nil)
            cancellable.cancel()

            #expect(received == [1, 2])
        }

        /// The variadic-tuple overload is the only way the codebase can
        /// deduplicate a `combineLatest` pair, since tuples are not `Equatable`.
        @Test("Consecutive equal pairs are collapsed")
        func removeDuplicatesCollapsesEqualPairs() {
            let subject = PassthroughSubject<(Int, String), Never>()
            var received = [(Int, String)]()

            let cancellable = subject
                .removeDuplicates()
                .sink { received.append($0) }

            subject.send((1, "a"))
            subject.send((1, "a"))
            subject.send((2, "a"))
            subject.send((2, "b"))
            subject.send((1, "a"))
            cancellable.cancel()

            // Rendered as strings so the comparison covers both elements of
            // each pair at once.
            #expect(received.map { "\($0.0)\($0.1)" } == ["1a", "2a", "2b", "1a"])
        }

        @Test("A difference in any element of the tuple counts as a change")
        func removeDuplicatesComparesEveryElement() {
            let subject = PassthroughSubject<(Int, Int, Int), Never>()
            var received = [(Int, Int, Int)]()

            let cancellable = subject
                .removeDuplicates()
                .sink { received.append($0) }

            subject.send((0, 0, 0))
            subject.send((0, 0, 1))
            subject.send((0, 1, 1))
            subject.send((1, 1, 1))
            subject.send((1, 1, 1))
            cancellable.cancel()

            #expect(received.count == 4)
        }

        @Test("discardMerge emits once for every element of either publisher")
        func discardMergeEmitsForBothSides() {
            let left = PassthroughSubject<Int, Never>()
            let right = PassthroughSubject<String, Never>()
            var count = 0

            let cancellable = left
                .discardMerge(right)
                .sink { _ in count += 1 }

            left.send(1)
            right.send("a")
            right.send("b")
            left.send(2)
            cancellable.cancel()

            #expect(count == 4)
        }
    }

    // MARK: - DistributedNotificationCenter

    /// The name is a system-defined string, so a typo would silently stop the
    /// app from noticing light/dark switches. Pinning the literal is the only
    /// way to catch that.
    @MainActor
    @Suite("Interface theme notification")
    struct InterfaceThemeNotificationTests {
        @Test("The theme notification uses the system-defined name")
        func themeNotificationName() {
            #expect(
                DistributedNotificationCenter.interfaceThemeChangedNotification.rawValue
                    == "AppleInterfaceThemeChangedNotification"
            )
        }
    }
}
