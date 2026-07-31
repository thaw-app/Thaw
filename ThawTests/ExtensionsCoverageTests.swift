//
//  ExtensionsCoverageTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Combine
import CoreGraphics
import Foundation
import os.lock
import Testing
@testable import Thaw

/// Builds a tag for a fictional app's status item.
private func fixtureTag(_ title: String, windowID: CGWindowID? = nil) -> MenuBarItemTag {
    .appItem(bundleID: "com.example.Fixture", title: title, windowID: windowID)
}

/// Builds an item whose tag carries no window identifier, so that the item's
/// own window identifier is free to vary independently of tag equality.
private func fixtureItem(_ title: String, windowID: CGWindowID) -> MenuBarItem {
    .fixture(tag: fixtureTag(title), windowID: windowID)
}

/// Covers the non-graphical half of `Utilities/Extensions.swift`: bundle
/// metadata lookup, the `MenuBarItem` collection helpers, the `Bool` unfair
/// lock claim, the Combine operators, and the interface-theme notification
/// name.
///
/// The graphical extensions (`CGColor`, `CGImage`, `NSBezierPath`, `NSImage`,
/// `NSApplication`, `NSPanel`) live in `ExtensionsGraphicsTests`.
///
/// Deliberately out of reach here:
///
/// - `Comparable.clamped`, `EdgeInsets`, and `CGImage.ColorAveragingOption`
///   are already covered by `ExtensionsTests`.
/// - Every `NSScreen` member depends on the number, arrangement, and notch
///   status of the attached displays, or mutates process-global caches shared
///   with the running host app, so none of it can be asserted deterministically
///   from a unit test.
/// - `NSStatusItem.showMenu(_:)` calls `performClick(nil)`, which runs a modal
///   menu tracking loop; it cannot be driven headlessly.
@Suite("Extensions coverage")
struct ExtensionsCoverageTests {
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
                .appendingPathComponent("ExtensionsCoverageTests-\(UUID().uuidString)", isDirectory: true)
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

    // MARK: - MenuBarItem collections

    /// The three lookup helpers are one-liners, but they are the only place
    /// item lookup is expressed, and every caller depends on two things the
    /// implementation does not spell out: the returned index is a real
    /// collection index (so it survives slicing), and matching goes through
    /// `MenuBarItemTag` equality rather than window identity.
    @MainActor
    @Suite("Menu bar item lookup")
    struct MenuBarItemLookupTests {
        private let items = [
            fixtureItem("Alpha", windowID: 1),
            fixtureItem("Beta", windowID: 2),
            fixtureItem("Alpha", windowID: 3),
        ]

        @Test("An empty collection matches nothing")
        func emptyCollectionMatchesNothing() {
            let empty = [MenuBarItem]()

            #expect(empty.firstIndex(matching: fixtureTag("Alpha")) == nil)
            #expect(empty.first(matching: fixtureTag("Alpha")) == nil)
        }

        @Test("An absent tag matches nothing")
        func absentTagMatchesNothing() {
            #expect(items.firstIndex(matching: fixtureTag("Gamma")) == nil)
            #expect(items.first(matching: fixtureTag("Gamma")) == nil)
        }

        @Test("A repeated tag resolves to the earliest element")
        func repeatedTagResolvesToEarliest() throws {
            #expect(items.firstIndex(matching: fixtureTag("Alpha")) == 0)

            let found = try #require(items.first(matching: fixtureTag("Alpha")))
            #expect(found.windowID == 1)
        }

        /// The index has to be usable to subscript the collection it came
        /// from, which rules out anything offset-based.
        @Test("A slice reports an index valid in the slice")
        func sliceReportsUsableIndex() throws {
            let slice = items[1...]

            let index = try #require(slice.firstIndex(matching: fixtureTag("Alpha")))
            #expect(index == 2)
            #expect(slice[index].windowID == 3)
        }

        /// Two items from the same app with the same title but different tag
        /// window identifiers are different items, and lookup must not conflate
        /// them.
        @Test("Tags that differ only by window identifier do not match")
        func windowIDDistinguishesTags() {
            let collection = [MenuBarItem.fixture(tag: fixtureTag("Alpha", windowID: 10), windowID: 10)]

            #expect(collection.firstIndex(matching: fixtureTag("Alpha", windowID: 10)) == 0)
            #expect(collection.firstIndex(matching: fixtureTag("Alpha", windowID: 11)) == nil)
        }

        // `removeFirst(matching:)` is mutating, and the #expect/#require macros
        // capture their argument into a closure that binds it immutably. Each
        // call is therefore made on its own line and the result inspected after.

        @Test("removeFirst takes one occurrence and leaves the rest")
        func removeFirstTakesOneOccurrence() throws {
            var collection = items

            let removedItem = collection.removeFirst(matching: fixtureTag("Alpha"))
            let removed = try #require(removedItem)

            #expect(removed.windowID == 1)
            #expect(collection.map { $0.windowID } == [2, 3])
        }

        @Test("removeFirst leaves the collection alone when nothing matches")
        func removeFirstWithoutMatchIsANoOp() {
            var collection = items

            let removed = collection.removeFirst(matching: fixtureTag("Gamma"))

            #expect(removed == nil)
            #expect(collection.map { $0.windowID } == [1, 2, 3])
        }

        @Test("removeFirst on an empty collection returns nil")
        func removeFirstOnEmptyCollection() {
            var collection = [MenuBarItem]()

            let removed = collection.removeFirst(matching: fixtureTag("Alpha"))

            #expect(removed == nil)
            #expect(collection.isEmpty)
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

            #expect(received.map { $0.0 } == [1, 2, 2, 1])
            #expect(received.map { $0.1 } == ["a", "a", "b", "a"])
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

        @Test("mergeMap flattens one publisher per element of the sequence")
        func mergeMapFlattensPerElement() {
            let subject = PassthroughSubject<[Int], Never>()
            var received = [Int]()

            let cancellable = subject
                .mergeMap { Just($0 * 2) }
                .sink { received.append($0) }

            subject.send([1, 2, 3])
            cancellable.cancel()

            #expect(received.sorted() == [2, 4, 6])
        }

        @Test("An empty sequence produces no downstream elements")
        func mergeMapOnEmptySequenceProducesNothing() {
            let subject = PassthroughSubject<[Int], Never>()
            var received = [Int]()

            let cancellable = subject
                .mergeMap { Just($0 * 2) }
                .sink { received.append($0) }

            subject.send([])
            cancellable.cancel()

            #expect(received.isEmpty)
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
