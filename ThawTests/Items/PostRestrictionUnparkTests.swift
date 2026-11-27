//
//  PostRestrictionUnparkTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation
import MenuBarModel
import Testing
@testable import Thaw

/// Where the post-restriction repair drops a parked visible item, and what a failed drop says about the item.
struct PostRestrictionUnparkTests {
    private static let screens = [CGRect(x: 0, y: 0, width: 1728, height: 1117)]
    /// Where macOS 27 parks an item during a reflow, far below the bar.
    private static let parkedY: CGFloat = 1400

    private static func item(_ title: String, x: CGFloat, y: CGFloat = 0, width: CGFloat = 24, windowID: CGWindowID) -> MenuBarItem {
        ItemsFixture.item(title, x: x, y: y, width: width, windowID: windowID)
    }

    private static func item(_ tag: MenuBarItemTag, x: CGFloat, y: CGFloat = 0, windowID: CGWindowID) -> MenuBarItem {
        ItemsFixture.item(tag.title, tag: tag, x: x, y: y, windowID: windowID)
    }

    /// The anchor among `items`, with the items titled in `hidden` in Hidden and the rest in Visible.
    private static func anchor(among items: [MenuBarItem], hidden: Set<String> = []) -> MenuBarItem? {
        PostRestrictionUnpark.anchor(among: items, screens: screens) { hidden.contains($0.tag.title) ? .hidden : .visible }
    }

    private static func fallbacks(
        for anchor: MenuBarItem,
        among items: [MenuBarItem],
        experimentalSystemItemHiding: Bool = false
    ) -> [MoveDestination] {
        PostRestrictionUnpark.fallbacks(
            for: anchor,
            among: items,
            screens: screens,
            experimentalSystemItemHiding: experimentalSystemItemHiding
        )
    }

    // MARK: Anchor

    @Test("The visible control item is the anchor while it is on the bar, even with Visible items to its right")
    func visibleControlIsTheAnchor() {
        let control = Self.item(.visibleControlItem, x: 500, windowID: 1)
        let app = Self.item("App", x: 600, windowID: 2)
        #expect(Self.anchor(among: [app, control]) == control)
    }

    @Test("Without the visible control on the bar, the rightmost Visible item on the bar is the anchor")
    func rightmostVisibleItemIsTheAnchor() {
        let control = Self.item(.visibleControlItem, x: 1000, y: Self.parkedY, windowID: 1)
        // A control item other than the visible one, right of every Visible item, which must not become the anchor.
        let hiddenControl = Self.item(.hiddenControlItem, x: 350, windowID: 2)
        let left = Self.item("Left", x: 100, windowID: 3)
        let right = Self.item("Right", x: 300, windowID: 4)
        let hiddenApp = Self.item("Concealed", x: 400, windowID: 5)
        let parkedApp = Self.item("Parked", x: 900, y: Self.parkedY, windowID: 6)
        // Right comes before Left, so only the position decides which is rightmost.
        let items = [control, right, hiddenControl, left, hiddenApp, parkedApp]
        #expect(Self.anchor(among: items, hidden: ["Concealed"]) == right)
    }

    @Test("There is no anchor when nothing on the bar is the visible control or a Visible item")
    func noAnchorWithoutCandidates() {
        let hiddenControl = Self.item(.hiddenControlItem, x: 350, windowID: 1)
        let hiddenApp = Self.item("Concealed", x: 400, windowID: 2)
        let parkedApp = Self.item("Parked", x: 900, y: Self.parkedY, windowID: 3)
        #expect(Self.anchor(among: [hiddenControl, hiddenApp, parkedApp], hidden: ["Concealed"]) == nil)
    }

    // MARK: Fallbacks

    @Test("The fallbacks are the nearest item on each side of the anchor, the left one first")
    func fallbacksAreTheNearestNeighbours() {
        let farLeft = Self.item("FarLeft", x: 100, windowID: 1)
        let left = Self.item("Left", x: 200, windowID: 2)
        let anchor = Self.item("Anchor", x: 300, windowID: 3)
        let right = Self.item("Right", x: 400, windowID: 4)
        let farRight = Self.item("FarRight", x: 500, windowID: 5)
        let items = [farRight, anchor, farLeft, right, left]
        #expect(Self.fallbacks(for: anchor, among: items) == [.rightOfItem(left), .leftOfItem(right)])
    }

    @Test("An anchor at the end of the bar has a fallback on one side only")
    func anchorAtTheEndHasOneFallback() {
        let left = Self.item("Left", x: 200, windowID: 1)
        let anchor = Self.item("Anchor", x: 300, windowID: 2)
        #expect(Self.fallbacks(for: anchor, among: [anchor, left]) == [.rightOfItem(left)])
        #expect(Self.fallbacks(for: left, among: [anchor, left]) == [.leftOfItem(anchor)])
    }

    @Test("Items a drop can't be placed against are passed over for the next one out")
    func unusableNeighboursArePassedOver() {
        let left = Self.item("Left", x: 100, windowID: 1)
        let pill = Self.item(MenuBarItemTag(namespace: .menuBarAgent, title: "live-activity-pill-1"), x: 150, windowID: 2)
        let control = Self.item(.visibleControlItem, x: 200, windowID: 3)
        let empty = Self.item("Empty", x: 250, width: 0, windowID: 4)
        let anchor = Self.item("Anchor", x: 300, windowID: 5)
        let parked = Self.item("Parked", x: 350, y: Self.parkedY, windowID: 6)
        let clone = Self.item(MenuBarItemTag(namespace: .string("com.example.Clone"), title: "System Status Item Clone"), x: 400, windowID: 7)
        let rightPill = Self.item(MenuBarItemTag(namespace: .menuBarAgent, title: "live-activity-pill-2"), x: 450, windowID: 8)
        let right = Self.item("Right", x: 500, windowID: 9)
        let items = [left, pill, control, empty, anchor, parked, clone, rightPill, right]
        #expect(Self.fallbacks(for: anchor, among: items) == [.rightOfItem(left), .leftOfItem(right)])
    }

    @Test("A system item that moves only with system item hiding on is a fallback only while that setting is on")
    func experimentalHidingDecidesSystemNeighbours() throws {
        let leftClock = Self.item(.clock, x: 200, windowID: 1)
        let rightClock = Self.item(.clock, x: 400, windowID: 2)
        try #require(leftClock.orderabilityRefusal(experimentalSystemItemHiding: false) == .requiresExperimentalHiding)
        let left = Self.item("Left", x: 100, windowID: 3)
        let anchor = Self.item("Anchor", x: 300, windowID: 4)
        let right = Self.item("Right", x: 500, windowID: 5)
        let clockOnLeft = [left, leftClock, anchor]
        #expect(Self.fallbacks(for: anchor, among: clockOnLeft, experimentalSystemItemHiding: false) == [.rightOfItem(left)])
        #expect(Self.fallbacks(for: anchor, among: clockOnLeft, experimentalSystemItemHiding: true) == [.rightOfItem(leftClock)])
        let clockOnRight = [anchor, rightClock, right]
        #expect(Self.fallbacks(for: anchor, among: clockOnRight, experimentalSystemItemHiding: false) == [.leftOfItem(right)])
        #expect(Self.fallbacks(for: anchor, among: clockOnRight, experimentalSystemItemHiding: true) == [.leftOfItem(rightClock)])
    }

    @Test("An anchor that isn't among the items a drop can be placed against has no fallbacks")
    func anchorOutsideTheOrderHasNoFallbacks() {
        let left = Self.item("Left", x: 100, windowID: 1)
        let control = Self.item(.visibleControlItem, x: 200, windowID: 2)
        let right = Self.item("Right", x: 300, windowID: 3)
        let absent = Self.item("Absent", x: 250, windowID: 4)
        #expect(Self.fallbacks(for: control, among: [left, control, right]).isEmpty)
        #expect(Self.fallbacks(for: absent, among: [left, control, right]).isEmpty)
    }

    // MARK: Failures

    @Test("Each unpark error maps to what it says about the item")
    func errorsMapToFailures() {
        let item = Self.item("App", x: 100, windowID: 1)
        typealias EventError = MenuBarItemManager.EventError
        #expect(PostRestrictionUnpark.failure(for: CancellationError()) == .cancelled)
        #expect(PostRestrictionUnpark.failure(for: EventError.destinationAnchorLost(item)) == .anchorsLost)
        #expect(PostRestrictionUnpark.failure(for: EventError.itemNotMovable(item, .requiresExperimentalHiding)) == .awaitsExperimentalHiding)
        #expect(PostRestrictionUnpark.failure(for: EventError.itemNotMovable(item, .systemAnchored)) == .notMovable(.systemAnchored))
        #expect(PostRestrictionUnpark.failure(for: EventError.itemNotMovable(item, nil)) == .notMovable(nil))
        #expect(PostRestrictionUnpark.failure(for: EventError.cannotComplete) == .cannotComplete)
        #expect(PostRestrictionUnpark.failure(for: EventError.eventOperationTimeout(item)) == .other)
        #expect(PostRestrictionUnpark.failure(for: URLError(.timedOut)) == .other)
    }

    /// On the main actor, where the ledger's failure kinds compare.
    @MainActor
    @Test("Only a refusal or an incomplete move is recorded as unmovable; a lost anchor or a gate the user can lift leaves no record")
    func onlyItemFailuresAreRecorded() {
        #expect(PostRestrictionUnpark.Failure.notMovable(.systemAnchored).ledgerKind == .cannotComplete)
        #expect(PostRestrictionUnpark.Failure.notMovable(nil).ledgerKind == .cannotComplete)
        #expect(PostRestrictionUnpark.Failure.cannotComplete.ledgerKind == .cannotComplete)
        #expect(PostRestrictionUnpark.Failure.other.ledgerKind == .other)
        #expect(PostRestrictionUnpark.Failure.anchorsLost.ledgerKind == nil)
        #expect(PostRestrictionUnpark.Failure.awaitsExperimentalHiding.ledgerKind == nil)
        #expect(PostRestrictionUnpark.Failure.cancelled.ledgerKind == nil)
    }
}
