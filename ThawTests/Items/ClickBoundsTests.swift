//
//  ClickBoundsTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import MenuBarModel
import Testing
@testable import Thaw

/// Pins where a click reads an item's frame: its own app first, every app only when that fails.
@Suite("Click bounds")
struct ClickBoundsTests {
    private static let warp: pid_t = 995

    private static func item(owner: pid_t, x: CGFloat, title: String = "Item-0") -> MenuBarItem {
        MenuBarItem(
            tag: MenuBarItemTag(namespace: .string("com.cloudflare.1dot1dot1dot1.macos"), title: title, windowID: 41, instanceIndex: 0),
            windowID: 41,
            ownerPID: owner,
            sourcePID: owner,
            bounds: CGRect(x: x, y: 2.5, width: 30, height: 28),
            title: title,
            isOnScreen: true
        )
    }

    /// Records which reads ran.
    private final class Reads: @unchecked Sendable {
        var ownApp: [Set<pid_t>] = []
        var everyApp = 0
    }

    private static func bounds(
        for item: MenuBarItem,
        ownApp: [MenuBarItem]?,
        everyApp: [MenuBarItem],
        reads: Reads
    ) async throws -> CGRect {
        try await ClickBoundsRead.bounds(
            for: item,
            ownApp: { owners in
                reads.ownApp.append(owners)
                return ownApp
            },
            everyApp: {
                reads.everyApp += 1
                return everyApp
            }
        )
    }

    @Test("The item's own app answers, and every app is never asked")
    func ownAppAnswers() async throws {
        let reads = Reads()
        let held = Self.item(owner: Self.warp, x: 900)

        let bounds = try await Self.bounds(for: held, ownApp: [Self.item(owner: Self.warp, x: 930)], everyApp: [], reads: reads)

        #expect(bounds.minX == 930)
        #expect(reads.ownApp == [[Self.warp]])
        #expect(reads.everyApp == 0)
    }

    @Test("When the own-app read can't vouch for the item, or lacks it, every app is asked")
    func fallsBackToEveryApp() async throws {
        let held = Self.item(owner: Self.warp, x: 900)
        let everyApp = [Self.item(owner: Self.warp, x: 931)]

        let unanswered = Reads()
        #expect(try await Self.bounds(for: held, ownApp: nil, everyApp: everyApp, reads: unanswered).minX == 931)
        #expect(unanswered.everyApp == 1)

        let missing = Reads()
        #expect(try await Self.bounds(for: held, ownApp: [], everyApp: everyApp, reads: missing).minX == 931)
        #expect(missing.everyApp == 1)
    }

    @Test("An item with no known process goes straight to every app")
    func noProcessAsksEveryApp() async throws {
        let reads = Reads()
        let held = Self.item(owner: 0, x: 900)

        let bounds = try await Self.bounds(for: held, ownApp: [Self.item(owner: Self.warp, x: 930)], everyApp: [Self.item(owner: Self.warp, x: 931)], reads: reads)

        #expect(bounds.minX == 931)
        #expect(reads.ownApp.isEmpty)
    }

    @Test("An item neither read finds has no frame to click")
    func missingEverywhere() async {
        await #expect(throws: (any Error).self) {
            try await Self.bounds(for: Self.item(owner: Self.warp, x: 900), ownApp: [], everyApp: [], reads: Reads())
        }
    }

    // MARK: pressTarget

    @Test("The press goes to the fresh item with the same identity")
    func pressTargetMatchesIdentity() {
        let held = Self.item(owner: Self.warp, x: 900)
        let fresh = [Self.item(owner: Self.warp, x: 960, title: "Item-1"), Self.item(owner: Self.warp, x: 930)]

        #expect(ClickBoundsRead.pressTarget(for: held, among: fresh)?.bounds.minX == 930)
    }

    @Test("A changed transient title still finds the app's only item")
    func pressTargetTakesTheOnlySibling() {
        let held = Self.item(owner: Self.warp, x: 900)

        #expect(ClickBoundsRead.pressTarget(for: held, among: [Self.item(owner: Self.warp, x: 931, title: "Item-3")])?.bounds.minX == 931)
    }

    @Test("With several items of the app and none matching, nothing is pressed")
    func pressTargetRefusesASibling() {
        let held = Self.item(owner: Self.warp, x: 900)
        let fresh = [Self.item(owner: Self.warp, x: 931, title: "Item-3"), Self.item(owner: Self.warp, x: 961, title: "Item-4")]

        #expect(ClickBoundsRead.pressTarget(for: held, among: fresh) == nil)
        #expect(ClickBoundsRead.pressTarget(for: held, among: [Self.item(owner: 777, x: 931)]) == nil)
    }
}
